#!/usr/bin/env bash
# Unit tests for claude/hooks/agent-cache.py: feed it PreToolUse events with made-up subagent
# transcripts and check what it allows. Runs in a throwaway folder; no Claude Code session needed.
# Usage: tests/agent-cache-test.sh
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/claude/hooks/agent-cache.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export AIBRAIN_SESSION_STATE="$W/state"
S=sess1; TR="$W/proj/$S.jsonl"; SUB="$W/proj/$S/subagents"
mkdir -p "$SUB"; : > "$TR"
fails=0

ago() { date -u -d "@$(( $(date +%s) - $1 ))" +%Y-%m-%dT%H:%M:%S.000Z; }
agent() { # agent <id> <seconds since its last request> <context tokens> <5m|1h> [type] [last entry]
  local id="$1" idle="$2" ctx="$3" ttl="$4" type="${5:-contractor-sonnet}" last="${6:-result}"
  local w5=0 w1=0; [[ $ttl == 1h ]] && w1=500 || w5=500
  local sent; sent="$(ago "$idle")"; local wrote; wrote="$(ago $(( idle > 10 ? idle - 10 : 0 )))"
  {
    printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"brief"}}\n' "$sent"
    printf '{"type":"assistant","timestamp":"%s","message":{"id":"m1","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":500,"cache_read_input_tokens":%s,"output_tokens":100,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
      "$wrote" "$(( ctx - 602 ))" "$w5" "$w1"
    if [[ $last == tool ]]; then
      printf '{"type":"assistant","timestamp":"%s","message":{"id":"m1","content":[{"type":"tool_use","name":"Bash"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":500,"cache_read_input_tokens":%s,"output_tokens":100,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
        "$wrote" "$(( ctx - 602 ))" "$w5" "$w1"
    fi
  } > "$SUB/agent-$id.jsonl"
  printf '{"agentType":"%s","name":"%s"}\n' "$type" "${7:-}" > "$SUB/agent-$id.meta.json"
}
ev() { # ev <tool> <tool_input json> [extra json fields]: run the hook, print its stdout
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s%s}' \
    "$S" "$TR" "$1" "$2" "${3:+,$3}" | python3 -I "$HOOK"
}
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
denies() { [[ "$1" == *'"permissionDecision": "deny"'* ]]; }
allows() { [[ -z "$1" ]]; }
send() { ev SendMessage "{\"to\":\"$1\",\"message\":\"next step\"}"; }

# Bash: only a subagent on a 5-minute cache is held to 240 seconds.
agent a5 10 40000 5m; agent a1h 10 40000 1h employee-aibrain
check "main session: 10-minute Bash allowed" allows "$(ev Bash '{"command":"make","timeout":600000}')"
check "5m subagent: 10-minute Bash denied" denies "$(ev Bash '{"command":"make","timeout":600000}' '"agent_id":"a5"')"
r="$(ev Bash '{"command":"make","timeout":600000}' '"agent_id":"a5"')"
check "the reason says to run it detached" test "${r/nohup/}" != "$r"
check "5m subagent: 240 seconds allowed" allows "$(ev Bash '{"command":"make","timeout":240000}' '"agent_id":"a5"')"
check "5m subagent: no timeout allowed" allows "$(ev Bash '{"command":"make"}' '"agent_id":"a5"')"
check "5m subagent: background command allowed" allows "$(ev Bash '{"command":"make","timeout":600000,"run_in_background":true}' '"agent_id":"a5"')"
check "1h subagent: 10-minute Bash allowed" allows "$(ev Bash '{"command":"make","timeout":600000}' '"agent_id":"a1h"')"
check "subagent without a transcript counts as 5m" denies "$(ev Bash '{"command":"make","timeout":600000}' '"agent_id":"nosuch"')"

# SendMessage: a cold or oversized continue is held once, then goes through.
agent warm 180 40000 5m
check "warm 5m agent: continue allowed" allows "$(send warm)"
agent cold 600 40000 5m
r="$(send cold)"
check "cold 5m agent: continue held" denies "$r"
check "the reason gives minutes and size" test "${r/10 minutes ago/}" != "$r" -a "${r/40k tokens/}" != "$r"
check "cold 5m agent: second send goes through" allows "$(send cold)"
check "cold 5m agent: a third send is held again" denies "$(send cold)"
agent emp 1800 60000 1h employee-aibrain
check "1h agent idle 30 minutes: allowed" allows "$(send emp)"
agent empcold 4000 60000 1h employee-aibrain
check "1h agent idle 67 minutes: held" denies "$(send empcold)"
agent big 200 160000 5m
r="$(send big)"
check "warm agent past 150k: held" denies "$r"
check "the reason names the 150k line" test "${r/past 150k/}" != "$r"
agent busy 600 40000 5m contractor-sonnet tool
check "agent inside a tool call: allowed" allows "$(send busy)"
agent recent 600 40000 5m  # a request sent 10 minutes ago that is still writing its answer
printf '{"type":"assistant","timestamp":"%s","message":{"id":"m1","content":[{"type":"text","text":"more"}]}}\n' \
  "$(ago 30)" >> "$SUB/agent-recent.jsonl"
check "agent that wrote 30 seconds ago: allowed" allows "$(send recent)"
agent byname 600 40000 5m contractor-opus result reviewer
check "a name from the agent's metadata resolves" denies "$(send reviewer)"
check "main: allowed" allows "$(send main)"
check "unknown agent: allowed" allows "$(send someone-else)"
agent refd 600 40000 5m
check "an id with a [ref] suffix resolves" denies "$(send 'refd [3fa9c1]')"

# Errors never stand in the way.
check "garbage input: allowed" allows "$(printf 'not json' | python3 -I "$HOOK")"
check "garbage input: exit 0" bash -c "printf 'not json' | python3 -I '$HOOK'"
printf 'not json\n' > "$SUB/agent-broken.jsonl"
check "broken transcript: allowed" allows "$(send broken)"

echo
[[ $fails == 0 ]] && echo "All agent-cache checks passed." || echo "$fails agent-cache check(s) failed."
exit $(( fails > 0 ))
