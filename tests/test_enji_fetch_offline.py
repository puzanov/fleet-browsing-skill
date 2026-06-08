#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HELPER = REPO_ROOT / "enji-fleet-browser/scripts/enji-fetch.sh"
MOCKS = REPO_ROOT / "tests/mocks"
OBSCURA_WEB_RE = re.compile(r"\bobscura\b.*\b(fetch|scrape|download)\b")


class EnjiFetchOfflineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="enji-fetch-offline.")
        self.root = Path(self.tmp.name)
        self.env = os.environ.copy()
        self.env.update(
            {
                "ENJI_AGENT_BROWSER_BIN": str(MOCKS / "agent-browser"),
                "ENJI_OBSCURA_BIN": str(MOCKS / "obscura"),
                "AGENT_BROWSER_SOCKET_DIR": str(self.root / "sockets"),
                "ENJI_AGENT_BROWSER_SOCKET_DIR": str(self.root / "sockets"),
                "MOCK_AGENT_BROWSER_STATE_DIR": str(self.root / "state"),
                "NO_COLOR": "1",
            }
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_capture(self, url: str, name: str) -> Path:
        out = self.root / name
        proc = subprocess.run(
            [str(HELPER), url, str(out)],
            env=self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return out

    def test_normal_path_records_expected_artifacts_without_obscura(self) -> None:
        out = self.run_capture("https://ok.test", "ok")

        self.assertEqual((out / "status.txt").read_text().strip(), "ok")
        self.assertEqual((out / "title.txt").read_text().strip(), "Enji Mock Page")
        self.assertTrue((out / "page.png").exists())
        self.assertTrue((out / "commands.log").exists())
        self.assertFalse((out / "obscura-bin.txt").exists())

        commands = (out / "commands.log").read_text()
        self.assertIn("agent-browser", commands)
        self.assertNotRegex(commands, OBSCURA_WEB_RE)

    def test_blocked_path_uses_obscura_with_stealth_only(self) -> None:
        out = self.run_capture("https://blocked.test", "blocked")

        self.assertEqual((out / "status.txt").read_text().strip(), "blocked")
        self.assertEqual((out / "title.txt").read_text().strip(), "Just a moment...")
        self.assertTrue((out / "obscura-bin.txt").exists())
        self.assertTrue((out / "obscura-stealth.md").exists())
        self.assertTrue((out / "obscura-stealth.html").exists())

        commands = (out / "commands.log").read_text().splitlines()
        obscura_lines = [line for line in commands if OBSCURA_WEB_RE.search(line)]
        self.assertGreaterEqual(len(obscura_lines), 2)
        self.assertEqual([line for line in obscura_lines if "--stealth" not in line], [])


if __name__ == "__main__":
    unittest.main()

