#!/usr/bin/env python3
"""Claude Code PreToolUse hook for Bash and Monitor: an agent can't spend the 1Password read budget in a loop.

Service accounts share one daily request limit per 1Password account, so one poll that reads a secret
every minute can lock every computer out of the vault for the rest of the day. This hook refuses:
- a Monitor command that calls the 1Password CLI (`op`) at all, directly or through a script file;
- a Bash command with an `op` call inside a loop (`for`, `while`, `until`, `select`, `watch`, `xargs`,
  `parallel`), counting a run of a script file that calls op as an op call;
- a Bash command that runs a script file which calls op inside a polling loop: a `while` or `until`
  loop, or any loop that sleeps. A script that reads a few items in a `for` loop once per run is fine.
Script files are followed two levels deep (the command, the script it runs, the scripts that one runs).
Only an `op` in command position counts, so `grep 'op read' file` in a loop is fine. If the hook
itself fails, Claude Code runs the command anyway.
"""
import json
import os
import re
import sys

VERBS = r"(?:read|run|inject|item|document|vault|whoami|service-account|signin|user|group)"
# What may stand before a command word: the start, a separator, a keyword, a wrapper, assignments.
# A pipe counts only with a space after it, so a grep pattern like 'op read|op run' is no op call.
LEAD = (r"(?:^|[;&(`\n{!]|\|\s|\$\(|<\s*|\b(?:then|do|else|if|elif|while|until|sudo|env|exec|nohup|command|time)\s)\s*"
        r"(?:\w+=(?:\$\([^)]*\)|\"[^\"]*\"|'[^']*'|\S+)\s+)*(?:timeout\s+(?:-\S+\s+)*\S+\s+)?")
OP_CALL = re.compile(LEAD + r"op\s+" + VERBS + r"\b")
OP_ANY = re.compile(r"(?<![\w'\"./-])op\s+" + VERBS + r"\b")  # an op anywhere, for watch and xargs
INTERP = r"(?:(?:ba|z|da)?sh|python3?|uv\s+run)\s+(?:-(?!n\s)\S+\s+)*"  # bash -n only parses
RUNS_HERE = re.compile(LEAD + r"(?:" + INTERP + r")?$")
PATH_WORD = re.compile(r"[^\s'\"`;&|<>(){}]*[/.][^\s'\"`;&|<>(){}]*")
SCRIPT_DIR = re.compile(r'"?\$\(dirname\s+"?\$(?:0|\{BASH_SOURCE\[0\]\}|\{?BASH_SOURCE\}?)"?\)"?|\$\{0%/\*\}')
PY_OP = re.compile(r"""["']op["']\s*,\s*["']""" + VERBS + r"""["']|["']op\s+""" + VERBS + r"\b")
LOOP_OPEN = re.compile(r"\b(for|while|until|select)\b")
DO = re.compile(r"(?:^|[;\n])\s*do\b")
DONE = re.compile(r"(?:^|[;\n&|])\s*done\b")
PIPE_LOOP = re.compile(r"(?<![\w.-])(?:watch|xargs|parallel)\s")
READ_LOOP = re.compile(r"\bwhile\s+(?:\w+=\S*\s+)*read\b")
SLEEP = re.compile(r"(?<![\w.-])sleep\s")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")
SHELL_WORD = re.compile(r"(?<![\w.-])(?:(?:ba|z|da)?sh|ssh)\b")
COMMENT = re.compile(r"(?m)(?:^|\s)#(?![!{]).*$")

_reads = {}


def resolve(token, base):
    """The script file a command word names, or None."""
    t = token.strip("\"'")
    home = os.path.expanduser("~")
    for prefix in ("~", "$HOME", "${HOME}"):
        if t.startswith(prefix + "/"):
            t = home + t[len(prefix):]
    if "$" in t or not ("/" in t or t.endswith((".sh", ".bash", ".py"))):
        return None
    path = t if os.path.isabs(t) else os.path.join(base, t)
    try:
        if not os.path.isfile(path) or os.path.getsize(path) > 1_000_000:
            return None
        if not path.endswith((".sh", ".bash", ".py")):
            with open(path, "rb") as f:
                if f.read(2) != b"#!":
                    return None  # a script without an extension starts with #!
    except OSError:
        return None
    return os.path.realpath(path)


def text_of(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def drop_data(text):
    """The text without here-documents that feed something other than a shell: a file written with
    cat, an edit made with python. Those are data, not commands; a here-document fed to bash or ssh runs."""
    lines, out, end = text.split("\n"), [], None
    for line in lines:
        if end is not None:
            if line.strip() == end:
                end = None
                out.append(line)
            else:
                out.append("")
            continue
        out.append(line)
        m = HEREDOC.search(line)
        if m and not SHELL_WORD.search(line[:m.start()]):
            end = m.group(2)
    return "\n".join(out)


def normalize(text, base):
    """A script's own folder, the way scripts name it, written out, so the scripts it runs resolve."""
    return SCRIPT_DIR.sub(lambda _: base, drop_data(text))


def scripts_run(text, base):
    """(end position, path) of each script file the shell text runs as a command."""
    for m in PATH_WORD.finditer(text):
        line = text[text.rfind("\n", 0, m.start()) + 1:m.start()]
        if RUNS_HERE.search(line):
            path = resolve(m.group(0), base)
            if path:
                yield m.end(), path


def calls(text, base, depth):
    """Positions in shell text where op runs: an op call, or a run of a script that reads op."""
    found = [m.end() for m in OP_CALL.finditer(text)]
    if depth > 0:
        found += [end for end, path in scripts_run(text, base) if reads_op(path, depth - 1)]
    return sorted(found)


def reads_op(path, depth):
    key = (path, depth)
    if key not in _reads:
        _reads[key] = False  # a script that runs itself stops here
        text = text_of(path)
        if path.endswith(".py"):
            _reads[key] = bool(PY_OP.search(text))
        else:
            base = os.path.dirname(path)
            _reads[key] = bool(calls(normalize(COMMENT.sub("", text), base), base, depth))
    return _reads[key]


def op_in_loop(text, base, depth, polling_only):
    """True when an op call sits inside a loop (only a polling loop, if polling_only)."""
    text = normalize(COMMENT.sub("", text) if polling_only else text, base)
    ops = calls(text, base, depth)
    events = [(p, "op") for p in ops]
    events += [(m.start(), "open:" + m.group(1)) for m in LOOP_OPEN.finditer(text)]
    events += [(m.end(), "do") for m in DO.finditer(text)]
    events += [(m.end(), "done") for m in DONE.finditer(text)]
    events += [(m.end(), "sleep") for m in SLEEP.finditer(text)]
    for m in PIPE_LOOP.finditer(text):
        end = re.compile(r"[;&\n]").search(text, m.end())
        stop = end.start() if end else len(text)
        if OP_ANY.search(text, m.end(), stop) or any(m.end() < p <= stop for p in ops):
            return True
    events.sort()
    stack, pending, header, header_op, opened = [], "for", False, False, 0
    for pos, kind in events:
        if kind.startswith("open:"):
            pending, opened = kind[5:], pos
            header, header_op = pending in ("while", "until"), False
        elif kind == "do":
            if header and READ_LOOP.search(text, opened, pos):
                pending = "for"  # `while read` walks its input once; it polls only if it sleeps
            stack.append({"kind": pending, "op": header_op, "sleep": False})
            header = False
        elif kind == "op" and header:
            if not polling_only:
                return True  # a while or until condition runs on every pass
            header_op = True
        elif kind == "op" and stack:
            if not polling_only:
                return True
            stack[-1]["op"] = True
        elif kind == "sleep" and stack:
            stack[-1]["sleep"] = True
        elif kind == "done" and stack:
            loop = stack.pop()
            if loop["op"] and (loop["kind"] in ("while", "until") or loop["sleep"]):
                return True
            if stack:
                stack[-1]["op"] |= loop["op"]
                stack[-1]["sleep"] |= loop["sleep"]
    return False


def polling_script(text, base):
    """A script file the command runs that calls op inside a polling loop, or None."""
    for _, path in scripts_run(normalize(text, base), base):
        body = text_of(path)
        if path.endswith(".py"):
            if PY_OP.search(body) and re.search(r"\bwhile\b", body) and re.search(r"\bsleep\(", body):
                return path
        elif op_in_loop(body, os.path.dirname(path), 1, polling_only=True):
            return path
    return None


def main():
    data = json.load(sys.stdin)
    tool = data.get("tool_name") or ""
    cmd = (data.get("tool_input") or {}).get("command") or ""
    if not cmd or tool not in ("Bash", "Monitor"):
        return
    base = data.get("cwd") or os.getcwd()
    why = None
    if tool == "Monitor" and calls(cmd, base, 2):
        why = "this Monitor would call the 1Password CLI (op) on every event or poll"
    elif op_in_loop(cmd, base, 2, polling_only=False):
        why = "this command calls the 1Password CLI (op), or a script that does, inside a loop"
    else:
        script = polling_script(cmd, base)
        if script:
            why = f"{script} calls the 1Password CLI (op) inside a polling loop"
    if why:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason":
                f"Refused: {why}. Every service account in the 1Password account shares one daily read limit "
                "(1000 a day on a personal account; `op read` by name costs 3), and when it runs out every "
                "computer loses its secrets for the rest of the day. Read each secret once per action, outside "
                "any loop or poll: into a variable, or a mode-600 file you empty afterwards, then loop over that. "
                "If each pass would read a different item, write the few op calls out one by one instead. Better, poll something that needs no secret, such as a health endpoint. Check what is left with "
                "`op service-account ratelimit` (it costs a read too).",
        }}))


main()
