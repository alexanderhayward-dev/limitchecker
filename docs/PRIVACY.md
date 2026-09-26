# Privacy

LimitChecker is designed to read subscription-limit information locally.

## Data it reads

The native helper opens the Claude Code and Codex CLIs already installed on the
current Mac and issues their built-in `/usage` and `/status` commands. Those
CLIs authenticate using their own existing local sessions.

LimitChecker does not collect passwords, API keys, OAuth tokens, prompts, source
code, repository paths, chat content, or account identifiers.

## Data it stores

The app stores a rolling twelve-hour history containing only a timestamp and
two percentage values. The file is located at:

`~/Library/Application Support/LimitChecker/history.json`

Delete that file, or the entire `LimitChecker` directory in Application
Support, to remove the history.

## Network use

LimitChecker has no first-party server and does not send data to a service run
by this project. The installed Claude Code and Codex CLIs may contact their own
providers as part of their normal startup and authentication behavior. Their
privacy policies apply to that traffic.

### Update check

Once a day, and whenever you ask for it explicitly, the app requests the public
GitHub release feed of this repository to learn whether a newer version exists:

`https://api.github.com/repos/alexanderhayward-dev/limitchecker/releases/latest`

The request is unauthenticated and carries no identifier: only the standard
`User-Agent` naming the app and its version. GitHub sees the originating IP
address, as with any web request. No usage data, limit values, or account
information leave the Mac. The session is ephemeral, so no cookies or caches
persist between checks.

Turn the check off under the `...` menu in the app: **Automatisch nach Updates
suchen**. With it off, the app makes no network requests at all unless you press
**Jetzt nach Updates suchen**.
