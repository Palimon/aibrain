#!/usr/bin/env python3
"""Privacy scan for the public aibrain repo: nothing personal goes in it.

Two sets of rules:
- Generic rules, always on: email addresses, tokens and private keys, home folders with a user name,
  Tailscale tailnet names, and private or Tailscale IP addresses. `privacy/allow` in this repo lists the
  few strings that are fine to publish anyway, such as noreply addresses.
- The personal denylist: names, email addresses, machine names, project names and anything else of
  yours, one entry per line. It lives outside this repo, in the personal overlay, because the list is
  itself personal. Nothing in this repo can loosen it.

The denylist is read from $AIBRAIN_DENYLIST_TEXT (its content, used by CI), else the file
$AIBRAIN_DENYLIST, else privacy/denylist in the overlay ($AIBRAIN_PERSONAL, default
~/Projects/aibrain-personal). If the overlay exists without a denylist, every scan fails: a guard that
silently lost its list is worse than one that stops you.

Denylist format: one entry per line; blank lines and lines starting with # are skipped.
  word or phrase      matched without regard to case, as a whole word where it starts or ends with one
  re:<regex>          a Python regular expression, matched without regard to case
  allow:<text>        text that is fine to publish although it contains an entry, such as a repo URL

Usage:
  scan.py staged                 the files staged for commit, their names, and the commit identity
  scan.py message <file>         a commit message
  scan.py push                   the commits a push sends, read as pre-push's stdin lines
  scan.py tree [<rev>]           every tracked file at <rev> (default HEAD) or, with no repo, nothing
  scan.py history                every commit reachable from any ref: messages, identities, changes
  scan.py text [<label>]         stdin
Exit status: 0 clean, 1 findings, 2 the scan couldn't run.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUIET = bool(os.environ.get("CI"))  # in public CI logs, name the rule, not the matched text

GENERIC = [
    ("email address", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[a-z]{2,}", re.I)),
    ("token or key", re.compile(
        r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[\w-]{10,}|sk-[A-Za-z0-9]{32,}"
        r"|ops_[A-Za-z0-9]{20,}|tskey-[\w-]{10,}|xox[baprs]-[\w-]{10,}|AKIA[0-9A-Z]{16}|AIza[\w-]{30,}"
        r"|eyJ[\w-]{10,}\.eyJ[\w-]{10,}\.[\w-]+)")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("home folder with a user name", re.compile(r"/(?:home|Users)/(?!(?:user|you|me|example|<[^>]*>)\b)[A-Za-z_][\w.-]*")),
    ("tailnet name", re.compile(r"\b[\w-]+\.ts\.net\b", re.I)),
    ("private or Tailscale IP address", re.compile(
        r"\b(?:10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])|192\.168|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b")),
]


class Rules:
    def __init__(self):
        self.allow = []   # generic-rule exceptions, from privacy/allow in this repo
        self.deny = []    # (label, regex) from the personal denylist
        self.deny_allow = []  # allow: entries from the denylist itself
        self.source = None
        for line in read_lines(os.path.join(ROOT, "privacy", "allow")):
            self.allow.append(re.compile(re.escape(line) if not line.startswith("re:") else line[3:], re.I))
        text, self.source = load_denylist()
        n = 0
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("allow:"):
                self.deny_allow.append(re.compile(re.escape(line[6:].strip()), re.I))
                continue
            n += 1
            if line.startswith("re:"):
                pat = line[3:]
            else:
                pat = re.escape(line)
                if re.match(r"\w", line):
                    pat = r"(?<![\w])" + pat
                if re.search(r"\w$", line):
                    pat += r"(?![\w])"
            try:
                self.deny.append((f"personal denylist entry {n}", re.compile(pat, re.I)))
            except re.error as e:
                fail(f"denylist entry {n} isn't a valid regex: {e}")

    def findings(self, text):
        """Yield (rule, matched text) for every problem in one line of text."""
        cleared = text
        for a in self.deny_allow:
            cleared = a.sub(lambda m: " " * len(m.group(0)), cleared)
        for label, rx in self.deny:
            for m in rx.finditer(cleared):
                yield label, m.group(0)
        for label, rx in GENERIC:
            for m in rx.finditer(text):
                if not any(a.fullmatch(m.group(0)) for a in self.allow):
                    yield label, m.group(0)


def read_lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            return [l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")]
    except OSError:
        return []


def load_denylist():
    if os.environ.get("AIBRAIN_DENYLIST_TEXT"):
        return os.environ["AIBRAIN_DENYLIST_TEXT"], "AIBRAIN_DENYLIST_TEXT"
    path = os.environ.get("AIBRAIN_DENYLIST")
    overlay = os.environ.get("AIBRAIN_PERSONAL", os.path.expanduser("~/Projects/aibrain-personal"))
    if not path:
        path = os.path.join(overlay, "privacy", "denylist")
        if not os.path.isdir(overlay):
            if not os.environ.get("CI"):
                print("privacy scan: no personal overlay, so only the generic rules apply", file=sys.stderr)
            return "", None
    try:
        with open(path, encoding="utf-8") as f:
            return f.read(), path
    except OSError:
        fail(f"can't read the personal denylist at {path}. Without it nothing personal is caught, "
             "so nothing is committed or pushed until it's back.")


def fail(msg):
    print(f"privacy scan: {msg}", file=sys.stderr)
    sys.exit(2)


def git(*args, input=None):
    r = subprocess.run(["git", *args], capture_output=True, input=input)
    if r.returncode != 0:
        fail(f"git {' '.join(args)} failed: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout


class Report:
    def __init__(self, rules):
        self.rules, self.count = rules, 0

    def text(self, where, text):
        for i, line in enumerate(text.splitlines(), 1):
            for rule, s in self.rules.findings(line):
                self.count += 1
                shown = "" if QUIET else f": {s!r}"
                print(f"{where}:{i}: {rule}{shown}", file=sys.stderr)

    def blob(self, where, data):
        if b"\0" in data[:8000]:
            # Binary: check its printable strings, which is where names and addresses would show
            data = b"\n".join(re.findall(rb"[\x20-\x7e]{6,}", data))
        self.text(where, data.decode("utf-8", errors="replace"))


def scan_staged(rep):
    names = git("diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR").split(b"\0")
    for name in filter(None, names):
        n = name.decode(errors="replace")
        rep.text(f"file name {n}", n)
        rep.blob(n, git("show", f":{n}"))
    for var in ("GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"):
        ident = git("var", var).decode(errors="replace")
        rep.text(var.lower().replace("git_", "").replace("_ident", " identity"), re.sub(r" \d+ [+-]\d{4}$", "", ident.strip()))


def scan_commit(rep, sha):
    short = sha[:10]
    meta = git("show", "-s", "--format=%an <%ae>%n%cn <%ce>", sha).decode(errors="replace")
    rep.text(f"commit {short} identity", meta)
    rep.text(f"commit {short} message", git("show", "-s", "--format=%B", sha).decode(errors="replace"))
    diff = git("show", "--format=", "--no-color", "--no-ext-diff", "-U0", "--no-renames", "--binary", sha).decode(errors="replace")
    current = "?"
    for line in diff.splitlines():
        if line.startswith("+++ "):
            current = line[6:] if line.startswith("+++ b/") else line[4:]
            rep.text(f"commit {short} file name", current)
        elif line.startswith("+") and not line.startswith("+++"):
            rep.text(f"commit {short} {current}", line[1:])


def scan_tree(rep, rev):
    for name in filter(None, git("ls-tree", "-r", "-z", "--name-only", rev).split(b"\0")):
        n = name.decode(errors="replace")
        rep.text(f"file name {n}", n)
        rep.blob(f"{rev}:{n}", git("show", f"{rev}:{n}"))


def scan_tag(rep, ref, sha):
    if git("cat-file", "-t", sha).strip() == b"tag":
        rep.text(f"tag {ref}", git("cat-file", "-p", sha).decode(errors="replace"))


ZERO = "0" * 40


def scan_push(rep, stdin):
    for line in stdin.splitlines():
        parts = line.split()
        if len(parts) != 4:
            continue
        local_ref, local_sha, remote_ref, remote_sha = parts
        if local_sha == ZERO:
            continue  # a delete sends nothing
        rep.text("ref name", f"{local_ref} {remote_ref}")
        scan_tag(rep, remote_ref, local_sha)
        if remote_sha != ZERO and subprocess.run(["git", "cat-file", "-e", remote_sha + "^{commit}"],
                                                  capture_output=True).returncode == 0:
            rng = [f"{remote_sha}..{local_sha}"]
        else:
            rng = [local_sha, "--not", "--remotes"]
        for sha in filter(None, git("rev-list", *rng).decode().split()):
            scan_commit(rep, sha)
        if git("cat-file", "-t", local_sha).strip() == b"commit":
            scan_tree(rep, local_sha)


def main():
    if len(sys.argv) < 2:
        fail("usage: scan.py staged|message <file>|push|tree [<rev>]|history|text [<label>]")
    mode = sys.argv[1]
    rep = Report(Rules())
    if mode == "staged":
        scan_staged(rep)
    elif mode == "message":
        with open(sys.argv[2], encoding="utf-8", errors="replace") as f:
            msg = "\n".join(l for l in f.read().splitlines() if not l.startswith("#"))
        rep.text("commit message", msg)
    elif mode == "push":
        scan_push(rep, sys.stdin.read())
    elif mode == "tree":
        scan_tree(rep, sys.argv[2] if len(sys.argv) > 2 else "HEAD")
    elif mode == "history":
        for sha in filter(None, git("rev-list", "--all").decode().split()):
            scan_commit(rep, sha)
        for line in git("for-each-ref", "--format=%(refname) %(objectname)", "refs/tags").decode().splitlines():
            ref, sha = line.split()
            rep.text("ref name", ref)
            scan_tag(rep, ref, sha)
    elif mode == "text":
        rep.text(sys.argv[2] if len(sys.argv) > 2 else "stdin", sys.stdin.read())
    else:
        fail(f"unknown mode {mode}")
    if rep.count:
        print(f"\nprivacy scan: {rep.count} finding(s), so this is stopped. This repo is public: move personal "
              "details to the personal overlay (aibrain-personal) or write them generically, such as "
              "\"my workstation\" or ~/ instead of a home path. Never bypass or weaken this check "
              "(AGENTS.md, \"Privacy\").", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
