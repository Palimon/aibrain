#!/usr/bin/env python3
"""Claude Code PreToolUse hook for Bash, in background sessions only: refuse an rm or rmdir that Claude
Code's own rm check would stop for approval. Even in bypassPermissions mode Claude Code asks before an rm
whose target it can't check up front, and in a background session that request waits on the user's
phone with no timeout, so the agent stalls until someone answers.

The check it stands in for asks about a target that is a variable, a $(...), a glob, an empty or root
path, or a relative path after cd, and about an rm that another shell runs (sh -c, ssh, eval) or that sits
in a heredoc. This hook refuses all of those and a little more, so the agent gets the refusal at once with
how to rewrite the command. At the top level a literal path passes, and so does a "${VAR:?}" target. An rm
another shell runs, or one in a heredoc, never passes. A quoted string no shell runs, such as a commit
message or a grep pattern, is only text. If the hook itself fails, Claude Code runs the command as usual.
"""
import json
import os
import re
import sys

LIT = r"[A-Za-z0-9._/@+,:=%-]"  # characters of a literal path: no quotes, expansions or globs
ASSIGN = r"[A-Za-z_]\w*=.*"
FED = {"xargs", "parallel", "-exec", "-execdir", "-ok", "-okdir"}  # they hand rm its targets at run time
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "!", "{", "time"}  # an rm right after is the command
WRAPPERS = {"sudo", "doas", "env", "nohup", "nice", "ionice", "timeout", "stdbuf", "setsid", "command", "exec",
            "builtin", "flock", "chroot", "watch", "strace", "unbuffer", "busybox"} | FED  # an rm anywhere after
REMOTE = {"ssh", "eval"}  # their arguments are a script another shell runs
SHELLS = REMOTE | {"sh", "bash", "zsh", "dash", "ksh", "su", "watch", "parallel"}  # so is a quoted word after these
LEADS = KEYWORDS | WRAPPERS | REMOTE
SUBCOMMANDS = {"git", "docker", "podman", "kubectl", "npm", "pnpm", "yarn", "bun", "cargo", "pip", "pip3", "uv",
               "brew", "conda", "gh", "helm", "jj", "hg", "svn"}  # git rm, docker rm: not the rm command
HOME = os.path.expanduser("~")


def background(data):
    """True in a background session: Claude Code sets CLAUDE_JOB_DIR there and keeps a job folder."""
    if os.environ.get("CLAUDE_JOB_DIR"):
        return True
    sid = data.get("session_id") or ""
    config = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
    return len(sid) >= 8 and os.path.isdir(os.path.join(config, "jobs", sid[:8]))


def bare(w):
    return re.sub(r"[\\'\"]", "", w)


def closing_paren(s, k):
    """Index of the ')' that closes the '(' at s[k], skipping quoted text; len(s) when there's none."""
    depth, j = 0, k
    while j < len(s):
        c = s[j]
        if c == "\\":
            j += 2
            continue
        if c in "'\"`":
            e = s.find(c, j + 1)
            j = len(s) if e < 0 else e + 1
            continue
        depth += {"(": 1, ")": -1}.get(c, 0)
        if depth == 0:
            return j
        j += 1
    return len(s)


def substitutions(t):
    """The $(...) and backtick texts in the body of a double-quoted string, which the shell runs even when
    the string itself is only text."""
    found, j = [], 0
    while j < len(t):
        if t[j] == "\\":
            j += 2
        elif t.startswith("$(", j):
            e = closing_paren(t, j + 1)
            found.append(t[j + 2:e])
            j = e + 1
        elif t[j] == "`":
            e = t.find("`", j + 1)
            e = len(t) if e < 0 else e
            found.append(t[j + 1:e])
            j = e + 1
        else:
            j += 1
    return found


def lex(s):
    """Split shell text into simple commands (lists of raw words) and the texts nested in it that a shell
    runs: $(...), backticks, <(...), heredoc bodies, and quoted strings passed to sh -c, ssh or eval."""
    cmds, words, nested, heredocs = [], [], [], []
    word, inword, i, n = "", False, 0, len(s)
    shell, runs = False, False  # a shell name so far in this command; a quoted word now is a script it runs

    def end_word():
        nonlocal word, inword, shell, runs
        if inword:
            words.append(word)
            name = os.path.basename(bare(word))
            shell = shell or name in SHELLS
            runs = shell or name == "-c"
        word, inword = "", False

    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            if s[i + 1] != "\n":
                word += s[i:i + 2]
                inword = True
            i += 2
            continue
        if c in "'\"`":
            escapes = c != "'" or word.endswith("$")  # $'...' takes backslash escapes
            j = i + 1
            while j < n and s[j] != c:
                if c == '"' and s.startswith("$(", j):
                    j = closing_paren(s, j + 1) + 1
                else:
                    j += 2 if escapes and s[j] == "\\" else 1
            raw = s[i + 1:j]
            if c == "`":
                nested.append(raw)
            elif runs:
                nested.append(re.sub(r'\\([\\"$`])', r"\1", raw) if c == '"' else raw)
            elif c == '"':
                nested += substitutions(raw)
            word += s[i:j + 1]
            inword = True
            i = j + 1
            continue
        if c in "$<>" and s.startswith("(", i + 1):
            j = closing_paren(s, i + 1)
            nested.append(s[i + 2:j])
            word += s[i:j + 1]
            inword = True
            i = j + 1
            continue
        if s.startswith("<<", i) and not s.startswith("<<<", i):
            m = re.match(r"<<(-?)[ \t]*\\?(['\"]?)([A-Za-z0-9_.-]+)\2", s[i:])
            if m:
                end_word()
                heredocs.append((m.group(3), m.group(1) == "-"))
                i += m.end()
                continue
        if c == "#" and not inword:
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "&" and (word.endswith((">", "<")) or s.startswith(">", i + 1)):
            word += c  # 2>&1 and &>file are redirects, not command separators
            inword = True
            i += 1
            continue
        if c in " \t":
            end_word()
            i += 1
            continue
        if c in ";&|()\n":
            end_word()
            if words:
                cmds.append(words)
                words = []
            shell, runs = False, False
            i += 1
            if c == "\n":
                for delim, tabs in heredocs:
                    body = []
                    while i < n:
                        j = s.find("\n", i)
                        j = n if j < 0 else j
                        line, i = s[i:j], j + 1
                        if (line.lstrip("\t") if tabs else line) == delim:
                            break
                        body.append(line)
                    nested.append("\n".join(body))
                heredocs = []
            continue
        word += c
        inword = True
        i += 1
    end_word()
    if words:
        cmds.append(words)
    return cmds, nested


def head(words):
    """The command name of a simple command, past keywords such as then or do, VAR=value words, and
    command or builtin."""
    for w in words:
        b = bare(w)
        if b not in KEYWORDS and b not in ("command", "builtin") and not re.fullmatch(ASSIGN, b):
            return os.path.basename(b)
    return ""


def redirect(w):
    return re.match(r"(\d*|&)[<>]", w) is not None


def target_ok(w, after_cd):
    """A top-level rm target Claude Code can check up front: a literal path, or a quoted "${VAR:?}"."""
    if ".." not in w and re.fullmatch(r'"\$\{[A-Za-z_]\w*:\?[^}"$`]*\}(' + LIT + r'*"|"' + LIT + r"*)", w):
        return True
    s = w[1:-1] if len(w) >= 2 and w[0] == w[-1] and w[0] in "'\"" and w[0] not in w[1:-1] else w
    if not re.fullmatch(LIT + "+", s) or s in (".", ".."):
        return False
    if s.startswith("/"):
        p = os.path.normpath("/" + s.lstrip("/"))  # normpath keeps a leading //
        return p.count("/") > 1 and p not in (HOME, os.path.dirname(HOME))  # not /, /etc, ~ or /home
    return not after_cd


def problems(script, nested, after_cd, depth=0):
    """The rm commands in script that Claude Code would stop for approval."""
    if depth > 8:
        return []
    cmds, inner = lex(script)
    found = []
    for words in cmds:
        first = head(words)
        if first in ("cd", "pushd"):
            after_cd = True
        for k, w in enumerate(words):
            if os.path.basename(bare(w)) not in ("rm", "rmdir"):
                continue
            before = {os.path.basename(bare(x)) for x in words[:k]}
            prev = bare(words[k - 1]) if k else None
            fed, remote = FED & before, REMOTE & before
            if not (fed or remote) and (SUBCOMMANDS & before or not (
                    first in WRAPPERS or prev is None or prev in LEADS or prev.startswith(("-", "/", "~", "."))
                    or prev.isdigit() or re.fullmatch(ASSIGN, prev) or redirect(prev))):
                continue  # an argument (echo rm, grep rm) or a subcommand (git rm, docker rm)
            args, skip, opts = [], False, True
            for x in words[k + 1:]:
                if skip:
                    skip = False
                elif redirect(x):
                    skip = re.fullmatch(r"(\d*|&)[<>]{1,2}&?", x) is not None
                elif opts and x == "--":
                    opts = False
                elif not (opts and x.startswith("-") and len(x) > 1):
                    args.append(x)
            shown = " ".join([bare(w)] + words[k + 1:])
            shown = shown if len(shown) <= 70 else shown[:67] + "..."
            if fed:
                found.append(shown + "  (targets fed in at run time)")
            elif (nested or remote) and args:
                found.append(shown + "  (in a heredoc, or run by another shell: sh -c, ssh, eval)")
            elif not (nested or remote) and not all(target_ok(x, after_cd) for x in args):
                found.append(shown)
    for text in inner:
        found += problems(text, True, after_cd, depth + 1)
    return found


def main():
    data = json.load(sys.stdin)
    cmd = (data.get("tool_input") or {}).get("command") or ""
    if data.get("tool_name") != "Bash" or not re.search(r"\brm(dir)?\b", bare(cmd)) or not background(data):
        return
    found = problems(cmd, False, False)
    if not found:
        return
    listed = "; ".join(f"'{f}'" for f in dict.fromkeys(found))
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason":
            f"Refused before it could ask the user: {listed}. Claude Code stops an rm whose target it "
            "can't check up front for approval, and in a background session that request waits on the "
            "user's phone with no timeout. Rewrite it: give rm a literal path, or a quoted \"${VAR:?}\" "
            "target. For anything else (variables, globs, $(...), an rm after cd, an rm inside sh -c, "
            "ssh, eval or a heredoc), write the commands to a script file with the Write tool and run "
            "`bash /absolute/path/script.sh`. If the rm is only text in a heredoc, such as a commit "
            "message, write that text to a file with the Write tool and pass the file instead. Never "
            "leave a command waiting on the user's approval.",
    }}))


try:
    main()
except Exception:
    sys.exit(0)
