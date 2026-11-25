#!/usr/bin/env bash
# Unit tests for claude/hooks/op-budget.py: feed it PreToolUse events, some running made-up scripts,
# and check what it refuses. Runs in a throwaway folder; never calls op.
# Usage: tests/op-budget-test.sh
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/claude/hooks/op-budget.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
command -v cygpath >/dev/null && W="$(cygpath -m "$W")"
fails=0

ev() { # ev <tool> <command>: run the hook on that command, print its stdout
  jq -nc --arg t "$1" --arg c "$2" --arg w "$W" '{hook_event_name: "PreToolUse", cwd: $w, tool_name: $t, tool_input: {command: $c}}' |
    python3 -I "$HOOK"
}
check() { # check <deny|allow> <name> <tool> <command>
  local out; out="$(ev "$3" "$4")"
  if [[ $1 == deny && $out == *'"permissionDecision": "deny"'* ]] || [[ $1 == allow && -z $out ]]; then
    echo "ok   $2"
  else
    echo "FAIL $2 (wanted $1): ${out:-allowed}"; fails=$((fails + 1))
  fi
}

cat > "$W/once.sh" <<'EOF'
#!/bin/bash
# reads one item per run
tok=$(OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.config/op/t) op read 'op://v/Some Item/credential')
curl -fsS -H "Authorization: Bearer $tok" https://example.com/api
EOF
cat > "$W/poll.sh" <<'EOF'
#!/bin/bash
while :; do
  t=$(op read op://v/item/credential)
  curl -fsS -H "Authorization: Bearer $t" https://example.com/status || true
  sleep 120
done
EOF
cat > "$W/poll-for.sh" <<'EOF'
for i in $(seq 1 100); do
  op item get thing --vault v >/dev/null && break
  sleep 60
done
EOF
cat > "$W/poll-nested.sh" <<'EOF'
#!/bin/bash
until false; do
  bash "$(dirname "$0")/once.sh"
  sleep 300
done
EOF
cat > "$W/fixed.sh" <<'EOF'
#!/bin/bash
for item in alpha beta gamma; do
  op read "op://v/$item/credential" > "/run/x/$item"
done
EOF
cat > "$W/poll.py" <<'EOF'
import subprocess, time
while True:
    subprocess.run(["op", "read", "op://v/i/f"], check=False)
    time.sleep(60)
EOF
cat > "$W/healthz.sh" <<'EOF'
while true; do curl -fsS https://example.com/healthz; sleep 30; done
EOF

check deny  "inline while loop with op read"        Bash    'while true; do op read op://v/i/f; sleep 60; done'
check deny  "inline for loop over seq"              Bash    'for i in $(seq 10); do op item list --vault v; done'
check deny  "token assignment before op in until"   Bash    'until OP_SERVICE_ACCOUNT_TOKEN=$(cat ~/.config/op/t) op read op://v/i/f; do sleep 30; done'
check deny  "op inside a timeout sh -c loop"        Bash    "timeout 230 sh -c 'until op whoami >/dev/null; do sleep 10; done'"
check deny  "watch op"                              Bash    'watch -n 60 op service-account ratelimit'
check deny  "xargs op"                              Bash    'seq 5 | xargs -I{} op read op://v/i{}/f'
check deny  "inline loop runs a script that reads"  Bash    'for h in a b c; do ./once.sh "$h"; done'
check deny  "script with a while poll"              Bash    'bash poll.sh'
check deny  "script with a for loop that sleeps"    Bash    "nohup $W/poll-for.sh > out 2>&1 &"
check deny  "script polls a script that reads"      Bash    './poll-nested.sh'
check deny  "python script that polls"              Bash    'python3 poll.py'
check deny  "Monitor calling op"                    Monitor 'op service-account ratelimit'
check deny  "Monitor running a script that reads"   Monitor 'bash once.sh | grep --line-buffered ok'
check allow "one read, then a loop without op"      Bash    'op read op://v/i/f > t; for i in 1 2 3; do curl -H @t https://example.com; done'
check allow "grep for op read in a loop"            Bash    "for f in *.sh; do grep -c 'op read' \"\$f\"; done"
check allow "commit message naming op"              Bash    'git commit -m "while polling, never call op read in a loop"'
check allow "script that reads once"                Bash    'bash once.sh'
check allow "script that reads a fixed list once"   Bash    "$W/fixed.sh"
check allow "op run once in the background"         Bash    'op run --env-file .env -- ./harness.sh'
check allow "Monitor polling a health endpoint"     Monitor 'bash healthz.sh'
check allow "Monitor tailing a log"                 Monitor 'tail -f app.log | grep --line-buffered ERROR'
check allow "python edit fed by a here-document"     Bash    $'python3 - <<\'EOF\'\nfor l in lines:\n    run("op read x")\nwhile True: pass\nEOF'
check deny  "shell loop fed by a here-document"     Bash    $'bash <<\'EOF\'\nwhile :; do op read op://v/i/f; sleep 9; done\nEOF'
printf 'while true; do\n  op read op://v/i/f\n  sleep 60\ndone\n' > "$W/NOTES.md"
check allow "a text file is not a script"           Bash    'for i in 1 2; do cat ./NOTES.md; done; bash -n ./NOTES.md'
cat > "$W/each-host.sh" <<'EOF'
#!/bin/bash
while IFS=$'\t' read -r h _; do
  op item get "host-$h" --vault v > /dev/null || echo "missing $h"
done < hosts.tsv
EOF
check allow "script reading items for each input line" Bash  './each-host.sh'
check allow "syntax check of a polling script"      Bash    'bash -n poll.sh'
check allow "grep pattern with op alternatives"     Bash    "for d in a b; do grep -rlE 'op read|op run' \"\$d\"; done"
check allow "reading a polling script"              Bash    'cat poll.sh; sed -n 1,5p poll.py'

if (( fails )); then echo "$fails failed"; exit 1; fi
echo "all passed"
