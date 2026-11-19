#!/usr/bin/env python3
"""bin/aibrain-authorized-keys: the logins bootstrap.sh writes into authorized_keys.

Every listed line must carry a from= limit; a line without one fails the whole run, so nothing is written.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "bin" / "aibrain-authorized-keys"
A = "AAAAC3NzaC1lZDI1NTE5AAAAIAaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
B = "AAAAC3NzaC1lZDI1NTE5AAAAIBbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
OLD = "AAAAC3NzaC1lZDI1NTE5AAAAIOoooooooooooooooooooooooooooooooooooooooooo"
OTHER = "AAAAC3NzaC1lZDI1NTE5AAAAIXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
BEGIN = "# >>> aibrain: from the personal layer's ssh/authorized_keys, managed by bootstrap.sh >>>"
END = "# <<< aibrain <<<"


class AuthorizedKeys(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())

    def file(self, name, *lines):
        p = self.dir / name
        p.write_text("".join(l + "\n" for l in lines))
        return str(p)

    def run_helper(self, *args):
        return subprocess.run([sys.executable, "-I", str(HELPER), *args], capture_output=True, text=True)

    def test_a_line_without_from_fails_and_prints_nothing(self):
        lists = self.file("list", f'from="192.0.2.1" ssh-ed25519 {A} one', f"ssh-ed25519 {B} two")
        r = self.run_helper("-", "-", lists)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(r.stdout, "")
        self.assertIn("from=", r.stderr)

    def test_from_must_be_an_option_not_a_comment(self):
        lists = self.file("list", f'restrict ssh-ed25519 {A} from="192.0.2.1"')
        self.assertEqual(self.run_helper("-", "-", lists).returncode, 1)

    def test_a_line_in_a_second_list_without_from_fails(self):
        first = self.file("list", f'from="192.0.2.1" ssh-ed25519 {A} one')
        second = self.file("extra", f'restrict,command="/bin/true" ssh-ed25519 {B} two')
        self.assertEqual(self.run_helper("-", "-", first, second).returncode, 1)

    def test_block_revoked_and_listed_keys(self):
        lists = self.file("list", "# a comment", "", f'from="192.0.2.1" ssh-ed25519 {A} one')
        extra = self.file("extra", f'from="192.0.2.9",restrict,command="/bin/true" ssh-ed25519 {B} two')
        revoked = self.file("revoked", f"ssh-ed25519 {OLD} old")
        current = self.file("current", f'from="192.0.2.5" ssh-ed25519 {OLD} old', f"ssh-ed25519 {A} one, unlimited",
                            f"ssh-ed25519 {OTHER} kept")
        r = self.run_helper(current, revoked, lists, extra)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            BEGIN, f'from="192.0.2.1" ssh-ed25519 {A} one',
            f'from="192.0.2.9",restrict,command="/bin/true" ssh-ed25519 {B} two', END,
            f"ssh-ed25519 {OTHER} kept"])
        # Written back, a second run changes nothing
        Path(current).write_text(r.stdout)
        self.assertEqual(self.run_helper(current, revoked, lists, extra).stdout, r.stdout)

    def test_missing_files(self):
        r = self.run_helper(str(self.dir / "none"), str(self.dir / "none"), str(self.dir / "none"))
        self.assertEqual((r.returncode, r.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
