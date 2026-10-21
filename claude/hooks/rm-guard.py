#!/usr/bin/env python3
"""Claude Code PreToolUse hook for Bash, in background sessions only: refuse an rm or rmdir that Claude
Code's own rm check would stop for approval. Even in bypassPermissions mode Claude Code asks before an rm
whose target it can't check up front, and in a background session that request waits on the user's
phone with no timeout, so the agent stalls until someone answers.

The check it stands in for asks about a target that is a variable, a $(...), a glob, an empty or root
path, or a relative path after cd, and about an rm that another shell runs (sh -c, ssh, eval, trap and the
like) or that sits in a heredoc. This hook refuses all of those and a little more, so the agent gets the
refusal at once with how to rewrite the command. At the top level a literal path passes, quoted or not, if
it has no expansion or glob, and so does a "${VAR:?}" target. An rm another shell runs, or one in a
heredoc, never passes. A quoted string no shell runs, such as a commit message or a grep pattern, is only
text. Text it can't follow (a quote or paren that never closes, or nesting too deep) is refused when it
mentions rm. If the hook itself fails, Claude Code runs the command as usual.
"""
import json
import os
import re
import sys

LIT = r"[A-Za-z0-9._/@+,:=%-]"  # characters of a literal path: no quotes, expansions or globs
QLIT = r"[A-Za-z0-9._/@+,:=%^ -]"  # the same inside quotes, where a space is literal too
ASSIGN = r"[A-Za-z_]\w*=.*"
REDIR_OP = r"(\d*|&)[<>]{1,2}&?"  # a redirect whose target is the next word
RM = re.compile(r"\brm(dir)?\b")
HEREDOC = re.compile(r"<<(-?)[ \t]*\\?(['\"]?)([A-Za-z0-9_.-]+)\2")
FED = {"xargs", "parallel", "-exec", "-execdir", "-ok", "-okdir"}  # they hand rm its targets at run time
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "!", "{", "time", "coproc"}  # an rm right after is the command
WRAPPERS = {"sudo", "doas", "env", "nohup", "nice", "ionice", "timeout", "stdbuf", "setsid", "command", "exec",
            "builtin", "flock", "chroot", "watch", "strace", "unbuffer", "busybox", "runuser", "unshare", "nsenter",
            "setpriv", "systemd-run", "taskset", "chrt"} | FED  # an rm anywhere after
REMOTE = {"ssh", "eval", "watch"}  # their arguments are a script another shell runs
SHELLS = REMOTE | {"sh", "bash", "zsh", "dash", "ksh", "mksh", "fish", "su", "runuser", "watch", "parallel", "trap",
                   "script", "tmux", "screen", "nix-shell"}  # so is a quoted word after these
RUN_WORDS = {"--command", "--run", "foreach"}  # a quoted word right after one is a script: git submodule foreach
LEADS = KEYWORDS | WRAPPERS | REMOTE
SUBCOMMANDS = {"git", "docker", "podman", "kubectl", "npm", "pnpm", "yarn", "bun", "cargo", "pip", "pip3", "uv",
               "brew", "conda", "gh", "helm", "jj", "hg", "svn"}  # git rm, docker rm: not the rm command
NONRUNNERS = {"grep", "egrep", "fgrep", "rg", "ugrep", "ag", "ack", "echo", "printf", "man", "which", "whatis",
              "apropos", "whereis", "type", "info"}  # an rm after these is a word they print or look for
ASIDE = SUBCOMMANDS | NONRUNNERS
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


def heredoc_bodies(s, i, pending):
    """The bodies of the pending heredocs, which start at s[i] just after their command's line, and the
    index past the last one."""
    bodies = []
    for delim, tabs in pending:
        body = []
        while i < len(s):
            j = s.find("\n", i)
            j = len(s) if j < 0 else j
            line, i = s[i:j], j + 1
            if (line.lstrip("\t") if tabs else line) == delim:
                break
            body.append(line)
        bodies.append("\n".join(body))
    return bodies, i


def closing_quote(s, i, escapes, d=0):
    """Index of the quote that closes the one at s[i], past any $(...) inside double quotes; len(s) or
    more when there's none. escapes says whether a backslash escapes the next character."""
    c, j = s[i], i + 1
    while j < len(s) and s[j] != c:
        if c == '"' and s.startswith("$(", j):
            j = closing_paren(s, j + 1, d + 1) + 1
        else:
            j += 2 if escapes and s[j] == "\\" else 1
    return j


def closing_paren(s, k, d=0):
    """Index of the ')' that closes the '(' at s[k], past quotes, comments and heredoc bodies; len(s) when
    there's none, or when the nesting is too deep to follow."""
    depth, j, pending = 0, k, []
    while d <= 50 and j < len(s):
        c = s[j]
        if c == "\\":
            j += 2
        elif c in "'\"`":
            j = closing_quote(s, j, c != "'" or s[j - 1] == "$", d + 1) + 1
        elif s.startswith("<<", j) and not s.startswith("<<<", j) and HEREDOC.match(s, j):
            m = HEREDOC.match(s, j)
            pending.append((m.group(3), m.group(1) == "-"))
            j = m.end()
        elif c == "\n" and pending:
            j = heredoc_bodies(s, j + 1, pending)[1]
            pending = []
        elif c == "#" and s[j - 1] in " \t\n;&|(":
            e = s.find("\n", j)
            j = len(s) if e < 0 else e
        else:
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
    """Split shell text into simple commands (lists of raw words), the texts nested in it that a shell
    runs, and whether a quote or paren in it never closes. A nested text is (text, prose): $(...),
    backticks, <(...) and quoted strings another shell runs (sh -c, ssh, eval, trap and the like) are
    scripts; a heredoc body is prose, where an apostrophe is only text."""
    cmds, words, nested, heredocs = [], [], [], []
    word, inword, i, n, unclosed = "", False, 0, len(s), False
    shell, runs = False, False  # a shell name so far in this command; a quoted word now is a script it runs

    def end_word():
        nonlocal word, inword, shell, runs
        if inword:
            words.append(word)
            b = bare(word)
            name = os.path.basename(b)
            shell = shell or name in SHELLS or (b.startswith("$") and head(words) == name)  # $SHELL -c
            runs = shell or name in RUN_WORDS or (
                re.fullmatch(r"-[A-Za-z]*c", name) is not None and head(words) not in NONRUNNERS)
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
            j = closing_quote(s, i, c != "'" or word.endswith("$"))  # $'...' takes backslash escapes
            unclosed = unclosed or j >= n
            raw = s[i + 1:j]
            if c == "`":
                nested.append((raw, False))
            elif runs:
                nested.append((re.sub(r'\\([\\"$`])', r"\1", raw) if c == '"' else raw, False))
            elif c == '"':
                nested += [(t, False) for t in substitutions(raw)]
            word += s[i:j + 1]
            inword = True
            i = j + 1
            continue
        if c in "$<>" and s.startswith("(", i + 1):
            j = closing_paren(s, i + 1)
            unclosed = unclosed or j >= n
            nested.append((s[i + 2:j], False))
            word += s[i:j + 1]
            inword = True
            i = j + 1
            continue
        if s.startswith("<<", i) and not s.startswith("<<<", i):
            m = HEREDOC.match(s, i)
            if m:
                end_word()
                heredocs.append((m.group(3), m.group(1) == "-"))
                i = m.end()
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
            if c == "\n" and heredocs:
                bodies, i = heredoc_bodies(s, i, heredocs)
                nested += [(b, True) for b in bodies]
                heredocs = []
            continue
        word += c
        inword = True
        i += 1
    end_word()
    if words:
        cmds.append(words)
    return cmds, nested, unclosed


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
    quoted = len(w) >= 2 and w[0] == w[-1] and w[0] in "'\"" and w[0] not in w[1:-1]
    s = w[1:-1] if quoted else w
    if not re.fullmatch((QLIT if quoted else LIT) + "+", s) or s.strip() in (".", ".."):
        return False
    if s.startswith("/"):
        p = os.path.normpath("/" + s.lstrip("/"))  # normpath keeps a leading //
        return p.count("/") > 1 and p not in (HOME, os.path.dirname(HOME))  # not /, /etc, ~ or /home
    return not after_cd


def problems(script, nested, after_cd, depth=0, prose=False):
    """The rm commands in script that Claude Code would stop for approval."""
    if depth > 8:
        return ["(nested too deep to check)"] if RM.search(bare(script)) else []
    cmds, inner, unclosed = lex(script)
    found = []
    if unclosed and not prose and RM.search(bare(script)):
        found.append("(a quote or paren that never closes, so its rm can't be checked)")
    for words in cmds:
        first = head(words)
        if first in ("cd", "pushd"):
            after_cd = True
        text = " ".join(words)
        if first == "eval" and any(re.search(r"[$`]", x) for x in words[1:]) and RM.search(bare(text)):
            found.append(text[:50] + "  (eval of a script built at run time)")
        before = set()
        for k, w in enumerate(words):
            name = os.path.basename(bare(w))
            if name not in ("rm", "rmdir"):
                before.add(name)
                continue
            prev = bare(words[k - 1]) if k else None
            fed, remote = FED & before, REMOTE & before
            if not (fed or remote) and (ASIDE & before or not (
                    first in WRAPPERS or prev is None or prev in LEADS or prev.startswith(("/", "~", "."))
                    or (k > 1 and (prev.startswith("-") or re.fullmatch(REDIR_OP, bare(words[k - 2]))))
                    or prev.isdigit() or re.fullmatch(ASSIGN, prev) or redirect(prev))):
                before.add(name)
                continue  # an argument (echo rm, grep rm) or a subcommand (git rm, docker rm)
            args, skip, opts = [], False, True
            for x in words[k + 1:]:
                if skip:
                    skip = False
                elif redirect(x):
                    skip = re.fullmatch(REDIR_OP, x) is not None
                elif opts and x == "--":
                    opts = False
                elif not (opts and x.startswith("-") and len(x) > 1):
                    args.append(x)
            shown = " ".join([bare(w)] + words[k + 1:k + 12])
            shown = shown if len(shown) <= 70 else shown[:67] + "..."
            if fed:
                found.append(shown + "  (targets fed in at run time)")
            elif (nested or remote) and args:
                found.append(shown + "  (in a heredoc, or run by another shell: sh -c, ssh, eval, trap)")
            elif not (nested or remote) and not all(target_ok(x, after_cd) for x in args):
                found.append(shown)
            break  # the words after this rm are its own arguments
    for text, is_prose in inner:
        found += problems(text, True, after_cd, depth + 1, is_prose)
    return found


def main():
    data = json.load(sys.stdin)
    cmd = (data.get("tool_input") or {}).get("command") or ""
    if data.get("tool_name") != "Bash" or not RM.search(bare(cmd)) or not background(data):
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
            "ssh, eval, trap or a heredoc), write the commands to a script file with the Write tool and "
            "run `bash /absolute/path/script.sh`. If the rm is only text in a heredoc, such as a commit "
            "message, write that text to a file with the Write tool and pass the file instead. Never "
            "leave a command waiting on the user's approval.",
    }}))


try:
    main()
except Exception:
    sys.exit(0)
