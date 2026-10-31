import json
import pathlib
import subprocess
import unittest


PROJECT_ROOT = pathlib.Path(__file__).parents[1]
PROBE_PATH = PROJECT_ROOT / ".build" / "debug" / "LimitProbe"


class LimitParserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not PROBE_PATH.exists():
            subprocess.run(
                ["swift", "build", "--product", "LimitProbe"],
                cwd=PROJECT_ROOT,
                check=True,
            )

    def parse(self, service, text):
        completed = subprocess.run(
            [str(PROBE_PATH), "--parse-output", service],
            input=text,
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(completed.stdout)["results"][0]

    def test_parses_claude_usage_without_spacing_after_percent(self):
        result = self.parse(
            "claude",
            """
            Current session
            ████████ 19%used
            Resets 12pm (Europe/Berlin)
            Current week (all models)
            ███████ 18%used
            Resets Sep 10 at 2am (Europe/Berlin)
            +50% weekly limits promo
            """
        )

        self.assertTrue(result["ok"])
        self.assertEqual([window["percent_left"] for window in result["windows"]], [81, 82])
        self.assertEqual(result["windows"][1]["resets"], "Sep 10 at 2am (Europe/Berlin)")

    def test_parses_codex_status_without_progress_bar(self):
        result = self.parse(
            "codex",
            """
            5h limit: 89% left (resets 12:10)
            Weekly limit: 98% left (resets 07:10 on 15 Sep)
            """
        )

        self.assertTrue(result["ok"])
        self.assertEqual([window["percent_used"] for window in result["windows"]], [11, 2])
        self.assertEqual(result["windows"][0]["resets"], "12:10")

    def test_keeps_the_available_claude_window(self):
        result = self.parse(
            "claude",
            """
            Current session
            100% used
            Resets 12pm (Europe/Berlin)
            """,
        )

        self.assertTrue(result["ok"])
        self.assertEqual(result["windows"], [{
            "name": "Current session",
            "percent_used": 100,
            "percent_left": 0,
            "resets": "12pm (Europe/Berlin)",
        }])

    def test_reports_claude_login_requirement(self):
        result = self.parse("claude", "Please log in to continue.")

        self.assertFalse(result["ok"])
        self.assertEqual(
            result["error"],
            "Claude Code ist nicht angemeldet. Öffne Claude Code im Terminal und melde dich an.",
        )

    def test_reports_claude_expired_login(self):
        for output in (
            "OAuth token revoked · Please run /login",
            "OAuth refresh token is no longer valid; run /login to re-authenticate",
            "Your session expired, run /login to renew",
        ):
            with self.subTest(output=output):
                result = self.parse("claude", output)

                self.assertFalse(result["ok"])
                self.assertIn("nicht angemeldet", result["error"])

    def test_reports_codex_login_requirement(self):
        result = self.parse("codex", "You are not logged in. Run codex login.")

        self.assertFalse(result["ok"])
        self.assertEqual(
            result["error"],
            "Codex ist nicht angemeldet. Öffne Codex im Terminal und melde dich an.",
        )

    def test_reports_unrecognized_output_with_next_step(self):
        result = self.parse("codex", "Codex is starting up")

        self.assertFalse(result["ok"])
        self.assertEqual(
            result["error"],
            "Codex hat keine erkennbaren Nutzungsdaten geliefert. Prüfe /status im Terminal.",
        )


if __name__ == "__main__":
    unittest.main()
