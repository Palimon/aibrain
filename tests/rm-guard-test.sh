#!/usr/bin/env bash
# Unit tests for claude/hooks/rm-guard.py: feed it PreToolUse events for Bash commands and check which
# rm commands it refuses in a background session. No Claude Code session needed.
# Usage: tests/rm-guard-test.sh
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/claude/hooks/rm-guard.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fails=0

ev() { # ev <command> [session id]: run the hook on a Bash call in a background session, print its stdout
  python3 -I -c 'import json, sys; print(json.dumps({"session_id": sys.argv[2], "hook_event_name": "PreToolUse",
    "tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1" "${2:-sess1}" |
    CLAUDE_JOB_DIR="$W/jobs/sess1" CLAUDE_CONFIG_DIR="$W" python3 -I "$HOOK"
}
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
denies() { [[ "$1" == *'"permissionDecision": "deny"'* ]]; }
allows() { [[ -z "$1" ]]; }
deny() { check "denied: $1" denies "$(ev "$1")"; }
allow() { check "allowed: $1" allows "$(ev "$1")"; }

# Only background sessions: CLAUDE_JOB_DIR, or a job folder named for the session.
fg='{"session_id":"fgsess12","tool_name":"Bash","tool_input":{"command":"rm -rf \"$D\""}}'
check "interactive session: allowed" allows "$(printf '%s' "$fg" | env -u CLAUDE_JOB_DIR CLAUDE_CONFIG_DIR="$W" python3 -I "$HOOK")"
mkdir -p "$W/jobs/bgsess12"
bg='{"session_id":"bgsess12-rest","tool_name":"Bash","tool_input":{"command":"rm -rf \"$D\""}}'
check "job folder without CLAUDE_JOB_DIR: denied" denies "$(printf '%s' "$bg" | env -u CLAUDE_JOB_DIR CLAUDE_CONFIG_DIR="$W" python3 -I "$HOOK")"
other='{"session_id":"sess1","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
check "another tool: allowed" allows "$(printf '%s' "$other" | CLAUDE_JOB_DIR=x python3 -I "$HOOK")"
check "bad input: allowed, no error" allows "$(printf 'not json' | CLAUDE_JOB_DIR=x python3 -I "$HOOK" 2>&1)"

# Targets Claude Code can check up front pass.
allow 'rm -f /tmp/build.log'
allow 'rm -rf /tmp/scratch/run-1 /var/tmp/x.out 2>/dev/null; rm -f /tmp/y 2>&1 | tail -1'
allow 'rm -rf "${D:?}"'
allow 'rm -rf "${D:?}/sub" "${D:?}"/other'
allow 'rm -f out.txt'
allow 'rm -rf -- /tmp/a'
allow 'git rm -r --cached "$f"'
allow 'docker rm "$id"'
allow 'echo rm -rf "$x"'
allow "grep -n 'rm -rf' setup.sh"
allow 'bash /tmp/cleanup.sh'
allow 'python3 - <<EOF
import subprocess
subprocess.run(["rm", "-f", path])
EOF'
allow 'ls ~/perm/confirm'
allow 'git -C /srv/repo rm -r --cached "$f"'
allow 'git commit -m "rm dead code"'
allow "gh pr create --title t --body '- rm the old hook'"
allow 'grep -rn "rm -rf /tmp" .'
allow "sed -i 's/rm x/del x/' notes.txt"
allow "awk '/rm /{print}' notes.txt"
allow "echo \$'it\\'s' && rm -f /tmp/ok"

# Targets it can't check, and every rm in a string or heredoc another shell runs, are refused.
deny 'rm -rf "$D"'
deny 'T=$(mktemp -d); echo "$T"; rm -r "$T"'
deny 'rm -rf $(find . -name __pycache__)'
deny 'rm -rf "$(dirname "$b")"'
deny 'cd /tmp/trfix && rm -rf *'
deny 'cd /tmp/trfix && rm -f out.txt'
deny 'rm -rf out-$m'
deny 'rm -rf -- ""'
deny 'rm -rf /'
deny 'rm -rf /home'
deny 'rm -rf ~/scratch/x'
deny 'rm -f /tmp/*.log'
deny 'rm -rf "${D}"'
deny 'sudo rm -rf "$d"'
deny 'for f in a b; do rm -f "$f"; done'
deny 'find . -name x -exec rm {} \;'
deny 'ls | xargs -0 rm -f'
deny "ssh host 'rm -rf ~/scratch/k3fix && git clone -q https://example.com/r ~/scratch/k3fix'"
deny "nohup sh -c \"ssh host 'flock -w 3600 ~/lane.lock bash /tmp/check.sh; rm -f /tmp/check.sh'\" > /tmp/out 2>&1 &"
deny "nohup sh -c \"ssh host 'mkdir -p ~/s && flock -w 60 ~/l sh -c \\\"set -x; rm -rf ~/s/x\\\"'\" &"
deny 'x=`rm -f /tmp/y`'
deny 'timeout 5m rm -rf "$D"'
deny 'sudo -u root rm -rf "$D"'
deny 'env -u FOO rm -rf "$D"'
deny 'flock lockfile rm -rf "$D"'
deny 'find . -print0 | xargs -0 -I {} rm -f {}'
deny "xargs -d '\\n' rm"
deny 'ssh host rm -rf ~/scratch/x'
deny 'ssh -o BatchMode=yes host rm -f /tmp/x'
deny 'eval rm -rf /tmp/x'
deny 'eval "rm -rf /tmp/x"'
deny "sh -c 'rm -f /tmp/a'"
deny 'echo "$(rm -rf "$x")"'
deny 'for d in a b; do cd /p/$d && rm -f out.log; done'
deny 'if cd /tmp/x; then rm -f out.log; fi'
deny '2>/dev/null rm -rf "$D"'
deny 'busybox rm -rf "$D"'
deny 'r\m -rf "$D"'
deny 'rm -rf //'
deny 'rm -rf "${D:?}/.."'
deny "echo \$'it\\'s'; rm -rf \"\$D\""
deny 'cat <<\EOF | bash
rm -f /tmp/x
EOF'
deny "bash -c 'rm -rf '\"\$D\""
deny "ssh host 'rm -rf '\"\$dir\""
deny "git submodule foreach --recursive 'rm -rf build'"
deny 'git submodule foreach rm -rf build'
deny "git submodule foreach --quiet 'git clean -fdx; rm -rf \"\$sm_path/build\"'"
deny '$SUDO rm -rf "$D"'
deny "echo 'rm -rf x' | sudo sh"
deny 'trap rm\ -f\ \"\$T\" EXIT'

# A heredoc a shell reads is a script; an unquoted one no shell reads still runs its $(...).
IFS= read -r -d '' h1 <<'X'
ssh -o BatchMode=yes host <<'EOF'
rm -rf ~/scratch/x
EOF
X
deny "$h1"
IFS= read -r -d '' h2 <<'X'
sudo bash -s <<'EOF'
rm -rf "$D"
EOF
X
deny "$h2"
IFS= read -r -d '' h3 <<'X'
cat <<'EOF' | ssh host bash -s
rm -rf "$D"
EOF
X
deny "$h3"
IFS= read -r -d '' h4 <<'X'
cat > /tmp/notes.txt <<EOF
It's done: $(rm -rf "$D")
EOF
X
deny "$h4"

# An apostrophe in a heredoc inside "$(...)" doesn't hide what comes after it.
IFS= read -r -d '' c1 <<'X'
git commit -m "$(cat <<'EOF'
Don't keep stale files
EOF
)" && rm -rf "$D"
X
deny "$c1"
IFS= read -r -d '' c2 <<'X'
gh pr create --title t --body "$(cat <<'EOF'
Doesn't matter
EOF
)"
rm -rf "$T"
X
deny "$c2"
IFS= read -r -d '' c3 <<'X'
git commit -m "$(cat <<'EOF'
Don't keep stale files
EOF
)" && rm -f /tmp/ok
X
allow "$c3"

# More runners and wrappers.
deny "trap 'rm -rf \"\$T\"' EXIT"
deny 'trap "rm -rf $T" EXIT'
deny 'runuser -u build rm -rf "$D"'
deny 'coproc rm -rf "$D"'
deny '> out.log rm -rf "$D"'
deny "\$SHELL -ec 'rm -rf \"\$D\"'"
deny "script -qc 'rm -rf \"\$D\"' /dev/null"
deny "git submodule foreach 'rm -rf build'"
deny "nix-shell --run 'rm -rf build'"
deny "tmux new-session -d 'rm -rf build'"
deny 'watch -n 5 rm -f /tmp/x'
deny 'eval "$(echo rm -rf x)"'

# Text it can't follow is refused when it mentions rm.
deny "echo 'oops; rm -rf build"
deep='rm -rf /tmp/x'
for _ in 1 2 3 4 5 6 7 8 9 10; do deep="echo \$($deep)"; done
deny "$deep"

# Not refused: rm as a word, a quoted literal path, a heredoc line that starts with "- rm".
allow 'grep -rn rm .'
allow 'sudo grep -rn rm /etc'
allow "grep -c 'rm -rf' notes.txt"
allow "rm -f 'out file.txt'"
allow "echo \"it's\" && rm -f /tmp/x"
IFS= read -r -d '' c4 <<'X'
git commit -F - <<'EOF'
- rm the old hook
EOF
X
allow "$c4"
allow 'git ls-files | xargs grep -n -w rm'
allow 'find . -exec grep -l "rm" {} +'
allow 'sudo grep -c "rm -f /tmp" log'
allow 'gh issue create --title tmux --body "rm -rf the build dir"'
allow "python3 -c 'rm = 3; print(rm)'"

# A heredoc no shell reads, with a quoted delimiter, is only text: a commit or PR body, or a file.
IFS= read -r -d '' p1 <<'X'
git commit -m "$(cat <<'EOF'
Replaces `rm -rf $TMP` with a trap
chore: drop the stale cache (rm -rf .cache)
Tidy up; rm stale fixtures
build first, then rm the old artifacts
explain why find | xargs rm was replaced
rm -rf build && make
EOF
)"
X
allow "$p1"
IFS= read -r -d '' p2 <<'X'
gh pr create --title t --body "$(cat <<'EOF'
Tidy up; rm stale fixtures
EOF
)"
X
allow "$p2"
IFS= read -r -d '' p3 <<'X'
mkdir -p /tmp/r && cat > /tmp/r/run.sh <<'EOF'
#!/usr/bin/env bash
base=~/scratch/r
rm -rf "$base"
EOF
bash /tmp/r/run.sh
X
allow "$p3"
IFS= read -r -d '' p4 <<'X'
ssh host 'cat > /tmp/x.sh' <<'EOF'
rm -rf "$D"
EOF
X
allow "$p4"

r="$(ev 'rm -rf "$D"')"
names() { [[ "$1" == *'rm -rf \"$D\"'* ]]; }
scripts() { [[ "$1" == *'Write tool'* ]]; }
check "the reason names the command" names "$r"
check "the reason says to use a script file" scripts "$r"

echo
if (( fails )); then echo "$fails failed"; exit 1; fi
echo "all passed"
