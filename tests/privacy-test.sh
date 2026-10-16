#!/usr/bin/env bash
# Tests for the privacy guard: privacy/scan.py through the git hooks in .githooks/, and the Claude Code
# hook claude/hooks/privacy-guard.py. Runs real commits and pushes in a throwaway repo with a throwaway
# denylist; no network needed. The made-up personal details below are put together at run time, so this
# file passes the scan itself.
# Usage: tests/privacy-test.sh
set -u
SRC="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fails=0
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

AT=@
EMAIL="jane.roe${AT}corp.test.com"
NOREPLY="12345+someone${AT}users.noreply.github.com"
HOMEPATH="/ho""me/janeroe/notes"
TAILNET="laptop.tail9z9z9z.ts"".net"
LANIP="192.16""8.1.20"
TOKEN="gh""p_$(printf 'a%.0s' {1..30})"

# A personal layer with a denylist, and a repo with the hooks on
P="$W/personal"; mkdir -p "$P/privacy"
cat > "$P/privacy/denylist" <<EOF
# test denylist
Jane Roe
secretproject
re:\bbox\d{2}\b
allow:github.com/secretproject/public
EOF
export AIBRAIN_PERSONAL="$P"
unset AIBRAIN_DENYLIST AIBRAIN_DENYLIST_TEXT CI
R="$W/repo"; mkdir -p "$R"
cp -r "$SRC/privacy" "$SRC/.githooks" "$R/"
git init -q -b main "$R"
git -C "$R" config core.hooksPath .githooks
git -C "$R" config user.name tester
git -C "$R" config user.email "$NOREPLY"
git -C "$R" add -A && git -C "$R" commit -qm "Add the guard" 2>/dev/null
git init -q --bare "$W/remote.git" && git -C "$R" remote add origin "$W/remote.git"

commit() { # commit <file> <content> [<message>]: try to commit one file; true if git took it
  printf '%s\n' "$2" > "$R/$1"
  git -C "$R" add -- "$1"
  if git -C "$R" commit -qm "${3:-test}" >/dev/null 2>&1; then return 0; fi
  git -C "$R" reset -q HEAD -- "$1"; rm -f "$R/$1"; return 1
}

# 1. The first commit, holding the guard itself, passed its own scan
check "guard's own files pass" test "$(git -C "$R" rev-list --count HEAD 2>/dev/null)" = 1

# 2. Content
check "clean file is committed" commit clean.md "Plain notes about agents."
check "denylisted phrase is refused" not commit a.md "Written by Jane Roe."
check "denylist ignores case" not commit a.md "written by jane roe"
check "denylist matches whole words only" commit b.md "secretprojectile is a different word"
check "denylist regex is refused" not commit a.md "ssh box07"
check "denylist regex leaves other text" commit c.md "ssh box7"
check "allow: entry lets its text through" commit d.md "https://github.com/secretproject/public"
check "email address is refused" not commit a.md "mail $EMAIL"
check "noreply address is allowed" commit e.md "author $NOREPLY"
check "example.com address is allowed" commit f.md "you${AT}example.com"
check "home folder with a user name is refused" not commit a.md "see $HOMEPATH"
check "home folder written with ~ is allowed" commit g.md "see ~/notes"
check "tailnet name is refused" not commit a.md "ssh $TAILNET"
check "private IP address is refused" not commit a.md "route $LANIP"
check "token is refused" not commit a.md "$TOKEN"
check "denylisted file name is refused" not commit secretproject.md "ok"
printf 'xx\000\001Jane Roe\000' > "$R/a.bin"; git -C "$R" add a.bin
check "binary file is checked" not git -C "$R" commit -qm binary 2>/dev/null
git -C "$R" reset -q HEAD -- a.bin; rm -f "$R/a.bin"

# 3. Commit message and identity
check "denylisted commit message is refused" not commit h.md "fine" "Fix for secretproject"
printf 'x\n' > "$R/i.md"; git -C "$R" add i.md
check "personal author email is refused" not git -C "$R" -c user.email="$EMAIL" commit -qm "identity" 2>/dev/null
git -C "$R" reset -q HEAD -- i.md; rm -f "$R/i.md"

# 4. Push: catches what --no-verify let in, in content, messages and tags
check "clean push goes through" git -C "$R" push -q origin main 2>/dev/null
printf 'by Jane Roe\n' > "$R/j.md"; git -C "$R" add j.md; git -C "$R" commit -q --no-verify -m "sneak" 2>/dev/null
check "push refuses a --no-verify commit" not git -C "$R" push -q origin main 2>/dev/null
git -C "$R" reset -q --hard HEAD~1
git -C "$R" commit -q --no-verify --allow-empty -m "about box12" 2>/dev/null
check "push refuses a --no-verify message" not git -C "$R" push -q origin main 2>/dev/null
git -C "$R" reset -q --hard HEAD~1
git -C "$R" tag -a v1 -m "for Jane Roe" 2>/dev/null
check "push refuses a tag message" not git -C "$R" push -q origin v1 2>/dev/null
git -C "$R" tag -d v1 >/dev/null

# 5. Where the denylist comes from
mv "$P/privacy/denylist" "$P/privacy/gone"
out="$(cd "$R" && python3 -I privacy/scan.py text 2>&1 <<< "hello")"; rc=$?
check "missing denylist stops every scan" test "$rc" = 2
mv "$P/privacy/gone" "$P/privacy/denylist"
check "no personal layer: generic rules still run" not env AIBRAIN_PERSONAL="$W/none" python3 -I "$R/privacy/scan.py" text <<< "$EMAIL" 2>/dev/null
check "no personal layer: denylist terms pass" env AIBRAIN_PERSONAL="$W/none" python3 -I "$R/privacy/scan.py" text <<< "Jane Roe" 2>/dev/null
check "AIBRAIN_DENYLIST_TEXT is used" not env AIBRAIN_PERSONAL="$W/none" AIBRAIN_DENYLIST_TEXT="Zork Person" python3 -I "$R/privacy/scan.py" text <<< "zork person" 2>/dev/null
out="$(CI=1 python3 -I "$R/privacy/scan.py" text <<< "Jane Roe and $EMAIL" 2>&1)"
check "CI output names the rule, not the text" bash -c '[[ "$1" == *"denylist entry 1"* && "$1" != *Jane* && "$1" != *corp* ]]' _ "$out"
check "history scan passes the pushed history" bash -c 'cd "$1" && python3 -I privacy/scan.py history 2>/dev/null' _ "$R"

# 6. The Claude Code hook: no skipping the hooks in ~/Projects/aibrain
guard() { # guard <command> <cwd>: print the hook's decision
  jq -nc --arg c "$1" --arg d "$2" '{tool_input: {command: $c}, cwd: $d}' |
    python3 -I "$SRC/claude/hooks/privacy-guard.py" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}
PUB="$HOME/Projects/aibrain"
check "guard refuses --no-verify in the repo" test "$(guard 'git commit --no-verify -m x' "$PUB")" = deny
check "guard refuses commit -n in the repo" test "$(guard 'git commit -anm x' "$PUB/tests")" = deny
check "guard refuses a hooksPath override naming the repo" test "$(guard 'git -C ~/Projects/aibrain -c core.hooksPath=/dev/null push' "$W")" = deny
check "guard refuses --no-verify on a push naming the repo" test "$(guard 'cd $HOME/Projects/aibrain && git push --no-verify' "$W")" = deny
check "guard refuses setting hooksPath" test "$(guard 'git config core.hooksPath /dev/null' "$PUB")" = deny
check "guard refuses unsetting hooksPath" test "$(guard 'git config --unset core.hooksPath' "$PUB")" = deny
check "guard refuses hooksPath through the environment" test "$(guard "GIT_CONFIG_PARAMETERS=\"'core.hooksPath=/x'\" git commit -m x" "$PUB")" = deny
check "guard allows a normal commit" test -z "$(guard 'git commit --amend -m "fix"' "$PUB")"
check "guard allows reading hooksPath" test -z "$(guard 'git config core.hooksPath' "$PUB")"
check "guard allows text that mentions hooksPath" test -z "$(guard $'printf "core.hooksPath is set by bootstrap\\n" >> notes.md\ngit add notes.md && git commit -m notes' "$PUB")"
check "guard leaves the personal layer alone" test -z "$(guard 'git commit --no-verify -m x' "$HOME/Projects/aibrain-personal")"
check "guard leaves other repos alone" test -z "$(guard 'git commit --no-verify -m x' "$W")"

echo
if (( fails )); then echo "$fails FAILED"; exit 1; fi
echo "all passed"
