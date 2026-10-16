#!/usr/bin/env python3
"""Claude Code PreToolUse hook for Bash: an agent can't get around the privacy guard of the public aibrain
repo (privacy/scan.py, run by the git hooks in .githooks/).

It refuses a git command that skips the hooks (--no-verify, or commit -n) or swaps them out (sets,
unsets or overrides core.hooksPath), when the command runs in ~/Projects/aibrain or names it. Reading
the setting, or writing text that mentions it, is fine. The personal layer,
~/Projects/aibrain-personal, isn't covered: it's private. If the hook itself fails, Claude Code runs the
command anyway, and the git hooks still apply.
"""
import json
import os
import re
import sys

data = json.load(sys.stdin)
cmd = (data.get("tool_input") or {}).get("command") or ""
if "git" not in cmd:
    sys.exit(0)
home = os.path.expanduser("~")
public = os.path.join(home, "Projects", "aibrain")
cwd = data.get("cwd") or ""
here = cwd == public or cwd.startswith(public + os.sep)
named = re.search(r"(?:~|\$HOME|\$\{HOME\}|" + re.escape(home) + r")/Projects/aibrain(?![\w-])", cmd)
if not (here or named):
    sys.exit(0)
SEG = r"[^;&|\n]*"  # the rest of one shell command
bypass = re.search(
    r"\bgit\b" + SEG + r"--no-verify"                                   # skip the hooks
    r"|\bgit\b" + SEG + r"\bcommit\b" + SEG + r"\s-[a-z]*n[a-z]*\b"     # commit -n, the same
    r"|-c\s*core\.hookspath="                                           # swap them for one command
    r"|\bconfig\b" + SEG + r"(?:--unset(?:-all)?\s+core\.hookspath|core\.hookspath\s+[^\s;&|]+)"  # or for good
    r"|\bGIT_CONFIG_\w*=\S*hookspath",                                  # or through the environment
    cmd, re.I)
if bypass:
    shown = bypass.group(0).strip()
    shown = shown if len(shown) <= 80 else "..." + shown[-77:]
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason":
            f"Refused: '{shown}' would get around the privacy guard of the public aibrain repo. "
            "If its scan stopped a commit, take the personal detail out (move it to ~/Projects/aibrain-personal "
            "or write it generically) and commit again. Never bypass or weaken the guard (AGENTS.md, \"Privacy\").",
    }}))
