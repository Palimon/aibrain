#!/usr/bin/env python3
"""Claude Code PreToolUse hook for Bash: an agent can't get around the privacy guard of the public aibrain
repo (privacy/scan.py, run by the git hooks in .githooks/).

It refuses a git command that skips the hooks (--no-verify, or commit -n) or swaps them out
(core.hooksPath), when the command runs in ~/Projects/aibrain or names it. The personal layer,
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
bypass = re.search(r"--no-verify|core\.hookspath|\bcommit\b[^;&|\n]*\s-[a-z]*n[a-z]*\b", cmd, re.I)
if bypass:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason":
            f"Refused: '{bypass.group(0).strip()}' would get around the privacy guard of the public aibrain repo. "
            "If its scan stopped a commit, take the personal detail out (move it to ~/Projects/aibrain-personal "
            "or write it generically) and commit again. Never bypass or weaken the guard (AGENTS.md, \"Privacy\").",
    }}))
