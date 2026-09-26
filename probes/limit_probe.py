#!/usr/bin/env python3
from __future__ import annotations

import argparse
import concurrent.futures
import fcntl
import json
import os
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import tempfile
import time
from dataclasses import asdict, dataclass
from typing import Callable


CODEX_BIN_CANDIDATES = (
    "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
    os.path.expanduser("~/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"),
    "/Applications/ChatGPT.app/Contents/Resources/codex",
    os.path.expanduser("~/Applications/ChatGPT.app/Contents/Resources/codex"),
)
CLAUDE_BIN = os.path.expanduser("~/.local/bin/claude")
PROBE_DIRECTORY = os.path.join(tempfile.gettempdir(), "limitchecker-cli-probe")


@dataclass
class LimitWindow:
    name: str
    percent_used: int | None = None
    percent_left: int | None = None
    resets: str | None = None


@dataclass
class ServiceUsage:
    service: str
    ok: bool
    windows: list[LimitWindow]
    error: str | None = None
    raw_excerpt: str | None = None


ANSI_RE = re.compile(
    r"""
    \x1b
    (?:
        \[[0-?]*[ -/]*[@-~]
      | \][^\x07]*(?:\x07|\x1b\\)
      | [PX^_].*?\x1b\\
      | [()#*+\-.\/].?
      | [@-Z\\-_]
    )
    """,
    re.VERBOSE | re.DOTALL,
)


def strip_terminal_controls(data: bytes) -> str:
    text = data.decode("utf-8", errors="ignore")
    text = ANSI_RE.sub("", text)
    text = text.replace("\r", "\n")
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text


def collapse_spaces(text: str) -> str:
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def compact_for_matching(text: str) -> str:
    return re.sub(r"\s+", "", text).lower()


def run_tui_probe(
    argv: list[str],
    command: str,
    *,
    wait_for: str | None,
    dialog_handlers: list[tuple[str, list[bytes] | bytes]] | None = None,
    timeout: float = 18.0,
    rows: int = 42,
    cols: int = 120,
    env: dict[str, str] | None = None,
    after_command: Callable[[int], None] | None = None,
    wait_after_ready: float = 2.0,
) -> tuple[int | None, str]:
    master_fd, slave_fd = pty.openpty()
    fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    proc_env = os.environ.copy()
    proc_env.update(
        {
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "NO_COLOR": "",
        }
    )
    if env:
        proc_env.update(env)

    def set_controlling_terminal() -> None:
        os.setsid()
        fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)

    os.makedirs(PROBE_DIRECTORY, exist_ok=True)
    proc = subprocess.Popen(
        argv,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        cwd=PROBE_DIRECTORY,
        env=proc_env,
        preexec_fn=set_controlling_terminal,
    )
    os.close(slave_fd)

    captured = bytearray()
    dialog_handlers = dialog_handlers or []
    handled_dialogs: set[str] = set()
    pending_dialog: tuple[str, float] | None = None
    sent = False
    start = time.monotonic()
    last_data = start
    ready_at: float | None = None

    try:
        while time.monotonic() - start < timeout:
            ready, _, _ = select.select([master_fd], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(master_fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                captured.extend(chunk)
                last_data = time.monotonic()

            plain = strip_terminal_controls(bytes(captured))
            matching_dialog = next(
                (
                    (prompt, responses)
                    for prompt, responses in dialog_handlers
                    if prompt not in handled_dialogs
                    and compact_for_matching(prompt) in compact_for_matching(plain)
                ),
                None,
            )
            if matching_dialog:
                prompt, responses = matching_dialog
                if pending_dialog is None or pending_dialog[0] != prompt:
                    pending_dialog = (prompt, time.monotonic())
                    continue
                if time.monotonic() - pending_dialog[1] < 0.8:
                    continue
                if isinstance(responses, bytes):
                    responses = [responses]
                for response in responses:
                    os.write(master_fd, response)
                    time.sleep(0.8)
                handled_dialogs.add(prompt)
                pending_dialog = None
                ready_at = None
                continue

            if not sent and (wait_for is None or wait_for in plain):
                if ready_at is None:
                    ready_at = time.monotonic()
                    continue
                if time.monotonic() - ready_at < wait_after_ready:
                    continue
                os.write(master_fd, command.encode("utf-8"))
                sent = True
                if after_command:
                    after_command(master_fd)

            if sent and time.monotonic() - last_data > 8.0:
                break

            if proc.poll() is not None:
                break
    finally:
        try:
            os.write(master_fd, b"\x1b")
            os.write(master_fd, b"/exit\r")
            os.write(master_fd, b"/quit\r")
        except OSError:
            pass
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except OSError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass
        os.close(master_fd)

    return proc.poll(), strip_terminal_controls(bytes(captured))


def parse_claude_usage(text: str) -> ServiceUsage:
    compact = collapse_spaces(text)
    windows: list[LimitWindow] = []

    session_match = re.search(
        r"Current session\s+.*?(\d{1,3})%\s*used\s+Resets\s+(.+?)(?=\nCurrent week|\nWhat's|\Z)",
        compact,
        re.DOTALL,
    )
    if session_match:
        used = int(session_match.group(1))
        windows.append(
            LimitWindow(
                name="Current session",
                percent_used=used,
                percent_left=max(0, 100 - used),
                resets=session_match.group(2).strip(),
            )
        )

    week_match = re.search(
        r"Current week(?: \(all models\))?\s+.*?(\d{1,3})%\s*used\s+Resets\s+(.+?)(?=\n\+|\nWhat's|\Z)",
        compact,
        re.DOTALL,
    )
    if week_match:
        used = int(week_match.group(1))
        windows.append(
            LimitWindow(
                name="Current week",
                percent_used=used,
                percent_left=max(0, 100 - used),
                resets=week_match.group(2).strip(),
            )
        )

    return ServiceUsage(
        service="claude",
        ok=bool(windows),
        windows=windows,
        error=None if windows else "Could not find Claude limit windows in /usage output.",
        raw_excerpt=compact[-2000:] if not windows else None,
    )


def parse_codex_status(text: str) -> ServiceUsage:
    compact = collapse_spaces(text)
    windows: list[LimitWindow] = []

    five_hour = re.search(
        r"5h limit:\s+\[[^\]]+\]\s+(\d{1,3})%\s+left\s+\(resets\s+([^)]+)\)",
        compact,
    )
    if five_hour:
        left = int(five_hour.group(1))
        windows.append(
            LimitWindow(
                name="5h limit",
                percent_left=left,
                percent_used=max(0, 100 - left),
                resets=five_hour.group(2).strip(),
            )
        )

    weekly = re.search(
        r"Weekly limit:\s+\[[^\]]+\]\s+(\d{1,3})%\s+left\s+\(resets\s+([^)]+)\)",
        compact,
    )
    if weekly:
        left = int(weekly.group(1))
        windows.append(
            LimitWindow(
                name="Weekly limit",
                percent_left=left,
                percent_used=max(0, 100 - left),
                resets=weekly.group(2).strip(),
            )
        )

    return ServiceUsage(
        service="codex",
        ok=bool(windows),
        windows=windows,
        error=None if windows else "Could not find Codex limit windows in /status output.",
        raw_excerpt=compact[-2000:] if not windows else None,
    )


def confirm_slash_command(fd: int) -> None:
    time.sleep(0.8)
    os.write(fd, b"\r")


def probe_claude() -> ServiceUsage:
    try:
        claude_bin = CLAUDE_BIN if os.path.exists(CLAUDE_BIN) else "claude"
        _, text = run_tui_probe(
            [claude_bin],
            "/usage",
            wait_for="Claude Code",
            dialog_handlers=[("Quick safety check", [b"\x1b[B", b"\r"])],
            timeout=28,
            after_command=confirm_slash_command,
        )
        return parse_claude_usage(text)
    except FileNotFoundError:
        return ServiceUsage("claude", False, [], "claude command not found.")
    except Exception as exc:
        return ServiceUsage("claude", False, [], f"{type(exc).__name__}: {exc}")


def resolve_codex_bin() -> str | None:
    for candidate in CODEX_BIN_CANDIDATES:
        if os.path.exists(candidate):
            return candidate
    return shutil.which("codex")


def probe_codex() -> ServiceUsage:
    codex_bin = resolve_codex_bin()
    if codex_bin is None:
        checked = ", ".join(CODEX_BIN_CANDIDATES)
        return ServiceUsage("codex", False, [], f"Codex binary not found in {checked} or on PATH.")
    try:
        _, text = run_tui_probe(
            [codex_bin, "--no-alt-screen"],
            "/status",
            wait_for="Ask Codex to do anything",
            dialog_handlers=[
                ("Do you trust", b"\r"),
                ("Hooks need review", [b"\x1b[B", b"\x1b[B", b"\r"]),
            ],
            timeout=28,
            env={"CODEX_HOME": os.path.expanduser("~/.codex")},
            after_command=confirm_slash_command,
        )
        return parse_codex_status(text)
    except Exception as exc:
        return ServiceUsage("codex", False, [], f"{type(exc).__name__}: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--service", choices=["all", "claude", "codex"], default="all")
    parser.add_argument("--pretty", action="store_true")
    args = parser.parse_args()

    if args.service == "all":
        # The CLIs are independent. Starting them together cuts refresh time roughly in half.
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            claude_future = executor.submit(probe_claude)
            codex_future = executor.submit(probe_codex)
            results = [claude_future.result(), codex_future.result()]
    elif args.service == "claude":
        results = [probe_claude()]
    else:
        results = [probe_codex()]

    payload = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "results": [asdict(result) for result in results],
    }
    print(json.dumps(payload, indent=2 if args.pretty else None, ensure_ascii=False))
    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
