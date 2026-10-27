#!/usr/bin/env python3
"""Exercise label provisioning against a fake gh, without network or real credentials."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "bin/aibrain-labels"
FAKE_GH = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
state = pathlib.Path(os.environ["LABEL_TEST_STATE"])
with open(os.environ["LABEL_TEST_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")
labels = json.loads(state.read_text())
if args[0] == "api":
    if os.environ.get("LABEL_TEST_FAIL_READ"):
        print("Issues read permission denied", file=sys.stderr)
        sys.exit(1)
    assert "--paginate" in args and "--slurp" in args
    print(json.dumps([labels[:1], labels[1:]]))
elif args[:2] == ["label", "create"]:
    if os.environ.get("LABEL_TEST_FAIL_WRITE"):
        print("Issues write permission denied", file=sys.stderr)
        sys.exit(1)
    assert "--force" in args and args[-2] == "--"
    name = args[-1]
    updated = {"name": name, "color": args[args.index("--color") + 1],
               "description": args[args.index("--description") + 1]}
    found = next((x for x in labels if x["name"].casefold() == name.casefold()), None)
    if found is None:
        labels.append(updated)
    else:
        found.update(updated)
    state.write_text(json.dumps(labels))
else:
    sys.exit(9)
'''


class LabelProvisioning(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.project = self.home / "project"
        self.project.mkdir()
        stub = self.home / "bin"
        stub.mkdir()
        gh = stub / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        self.state = self.home / "state.json"
        self.state.write_text("[]")
        self.log = self.home / "calls.jsonl"
        self.env = {
            "HOME": str(self.home), "PATH": str(stub) + os.pathsep + os.defpath,
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "XDG_DATA_HOME": str(self.home / ".local/share"),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "DBUS_SESSION_BUS_ADDRESS": "disabled:",
            "AIBRAIN_REPO": str(SCRIPT.parents[1]),
            "AIBRAIN_PERSONAL_REPO": str(self.home / "personal"),
            "LABEL_TEST_STATE": str(self.state), "LABEL_TEST_LOG": str(self.log),
        }
        self.git("init", "-q", "-b", "main")
        self.git("remote", "add", "origin", "https://github.com/example/engine.git")
        self.wanted = [
            {"role": "bug", "name": "bug", "color": "d73a4a", "description": "A bug"},
            {"role": "ready-for-agent", "name": "agent:ready", "color": "0e8a16",
             "description": "Ready to implement"},
        ]
        self.config = self.project / "docs/agents/labels.json"
        self.config.parent.mkdir(parents=True)
        self.configure(self.wanted)

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.project), *args], env=self.env,
                       capture_output=True, check=True)

    def configure(self, labels):
        self.config.write_text(json.dumps(labels))

    def run_sync(self, *args, success=True):
        result = subprocess.run([sys.executable, "-I", str(SCRIPT), str(self.project), *args],
                                env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def writes(self):
        return [call for call in self.calls() if call[:2] == ["label", "create"]]

    def test_create_preserve_unrelated_and_second_run_does_not_write(self):
        unrelated = {"name": "documentation", "color": "0075ca", "description": "Keep this"}
        self.state.write_text(json.dumps([unrelated]))
        self.run_sync()
        actual = {label["name"]: label for label in json.loads(self.state.read_text())}
        self.assertEqual(set(actual), {"documentation", "bug", "agent:ready"})
        self.assertEqual(actual["documentation"], unrelated)
        self.assertEqual(actual["agent:ready"]["color"], "0e8a16")
        self.assertEqual(len(self.writes()), 2)
        before = self.state.read_bytes()
        self.run_sync()
        self.assertEqual(self.state.read_bytes(), before)
        self.assertEqual(len(self.writes()), 2)

    def test_repairs_color_and_description_without_duplicate_labels(self):
        self.state.write_text(json.dumps([
            {"name": "Bug", "color": "ffffff", "description": "Old text"},
            {"name": "agent:ready", "color": "0E8A16", "description": "Ready to implement"},
        ]))
        self.run_sync()
        actual = json.loads(self.state.read_text())
        self.assertEqual(len(actual), 2)
        self.assertEqual(actual[0], {"name": "bug", "color": "d73a4a", "description": "A bug"})
        self.assertEqual(len(self.writes()), 1)

    def test_check_reports_drift_without_writing_then_passes_after_sync(self):
        self.run_sync("--check", success=False)
        self.assertEqual(self.writes(), [])
        self.assertEqual(json.loads(self.state.read_text()), [])
        self.run_sync()
        self.run_sync("--check")
        self.assertEqual(len(self.writes()), 2)

    def test_missing_manifest_and_empty_manifest_make_no_api_calls(self):
        self.config.unlink()
        self.run_sync()
        self.configure([])
        self.run_sync()
        self.assertEqual(self.calls(), [])

    def test_non_github_origin_makes_no_api_calls(self):
        self.git("remote", "set-url", "origin", str(self.home / "local.git"))
        self.run_sync()
        self.assertEqual(self.calls(), [])

    def test_ssh_origin_and_label_name_that_looks_like_an_option(self):
        self.git("remote", "set-url", "origin", "git@github.com:example/engine.git")
        self.wanted[1]["name"] = "--agent-ready"
        self.configure(self.wanted)
        self.run_sync()
        self.assertEqual({x["name"] for x in json.loads(self.state.read_text())}, {"bug", "--agent-ready"})
        self.assertTrue(all(call[call.index("--repo") + 1] == "example/engine" for call in self.writes()))

    def test_invalid_manifest_is_rejected_before_api_access(self):
        bad = [self.wanted[0], {**self.wanted[1], "name": "BUG"}]
        for labels in [bad, [{**self.wanted[0], "color": "invalid"}], {"labels": self.wanted}]:
            with self.subTest(labels=labels):
                self.configure(labels)
                self.run_sync(success=False)
                self.assertEqual(self.calls(), [])

    def test_read_failure_does_not_attempt_writes(self):
        self.env["LABEL_TEST_FAIL_READ"] = "1"
        result = self.run_sync(success=False)
        self.assertIn("permission denied", result.stderr)
        self.assertEqual(self.writes(), [])

    def test_write_failure_is_reported(self):
        self.env["LABEL_TEST_FAIL_WRITE"] = "1"
        result = self.run_sync(success=False)
        self.assertIn("permission denied", result.stderr)
        self.assertEqual(json.loads(self.state.read_text()), [])


if __name__ == "__main__":
    unittest.main()
