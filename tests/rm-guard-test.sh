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

# Targets it can't check, and every rm inside a string or heredoc, are refused.
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
deny 'mkdir -p /tmp/r && cat > /tmp/r/run.sh <<'"'EOF'"'
#!/usr/bin/env bash
base=~/scratch/r
rm -rf "$base"
EOF
bash /tmp/r/run.sh'

r="$(ev 'rm -rf "$D"')"
names() { [[ "$1" == *'rm -rf \"$D\"'* ]]; }
scripts() { [[ "$1" == *'Write tool'* ]]; }
check "the reason names the command" names "$r"
check "the reason says to use a script file" scripts "$r"

echo
if (( fails )); then echo "$fails failed"; exit 1; fi
echo "all passed"
