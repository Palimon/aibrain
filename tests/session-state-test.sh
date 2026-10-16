#!/usr/bin/env bash
# Unit tests for claude/hooks/session-state.py: feed it hook events and check what it decides.
# Runs in a throwaway folder; no Claude Code session or network needed.
# Usage: tests/session-state-test.sh
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/claude/hooks/session-state.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export AIBRAIN_SESSION_STATE="$W/state" AIBRAIN_COMPACT_HARD_CAP=500000
S=sess1; D="$W/state/$S"; TR="$W/transcript.jsonl"
fails=0

ctx() { # ctx <tokens>: make the transcript's last request this big
  printf '{"type":"assistant","message":{"usage":{"input_tokens":0,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0}}}\n' "$1" > "$TR"
}
ev() { # ev <Event> [extra json fields]: run the hook, print its stdout
  local extra="${2:-}"
  printf '{"session_id":"%s","transcript_path":"%s"%s}' "$S" "$TR" "${extra:+,$extra}" |
    python3 -I "$HOOK" "$1"
}
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
blocks() { [[ "$1" == *'"decision": "block"'* ]]; }
asks() { [[ "$1" == *additionalContext* ]]; }
tool() { ev PostToolUse "\"tool_name\":\"$1\",\"tool_input\":${2:-{\}}" ; }
write_state() { echo "# state" > "$D/state.md"; tool Write "{\"file_path\":\"$D/state.md\"}" >/dev/null; }
reset() { rm -rf "$W/state"; ctx 50000; }

# 1. Busy turn: compaction blocked.
reset; ev UserPromptSubmit '"prompt":"first prompt, verbatim"' >/dev/null; tool Read >/dev/null
check "blocked during a turn" blocks "$(ev PreCompact '"trigger":"auto"')"

# 2. Orchestrating session, state.md missing: Stop asks; ignored ask leaves compaction blocked.
reset; ev SubagentStart '"agent_id":"a1","agent_type":"general-purpose"'; tool Read >/dev/null
check "Stop asks for state.md" asks "$(ev Stop '"last_assistant_message":"reply one"')"
check "ignored ask: Stop ends turn" test -z "$(ev Stop '"stop_hook_active":true,"last_assistant_message":"reply two"')"
check "ignored ask: compaction still blocked" blocks "$(ev PreCompact '"trigger":"auto"')"

# 3. State written as the last step: Stop passes, compaction allowed at the next turn.
write_state
check "fresh state: Stop passes" test -z "$(ev Stop '"last_assistant_message":"reply three"')"
check "fresh state at a break: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"

# 4. Fix 1: state written early, more work after it: stale again.
tool Bash >/dev/null
check "work after state.md: Stop asks again" asks "$(ev Stop '"last_assistant_message":"reply four"')"

# 5. Fix 3: a chat-only turn needs no update, and its reply is logged.
write_state; ev Stop '"last_assistant_message":"reply five"' >/dev/null
check "chat turn: Stop passes" test -z "$(ev Stop '"last_assistant_message":"a pure-chat reply"')"
check "replies logged verbatim" grep -q "a pure-chat reply" "$D/replies.md"

# 6. Fix 4: small session never asked, then a jump past the soft cap: still blocked (no state.md).
reset; ctx 50000; tool Read >/dev/null
check "small session: Stop passes" test -z "$(ev Stop '"last_assistant_message":"x"')"
ctx 160000
check "jump past soft cap without state.md: blocked" blocks "$(ev PreCompact '"trigger":"auto"')"

# 7. Fix 5: near the hard cap, tool calls ask for an update; at the hard cap it's allowed mid-turn.
reset; ctx 460000
check "near hard cap: tool call asks" asks "$(tool Bash)"
check "near hard cap: doesn't ask again right away" test -z "$(tool Bash)"
ctx 486000
check "near hard cap: asks again after 25k more" asks "$(tool Bash)"
write_state
check "near hard cap, state fresh: no ask" test -z "$(tool Write "{\"file_path\":\"$D/state.md\"}")"
ctx 510000; tool Bash >/dev/null
check "hard cap: allowed mid-turn" test -z "$(ev PreCompact '"trigger":"auto"')"

# 8. Fix 6: full subagent reports, and SubagentHandback reports.
reset
long="$(printf 'line %s of the report\n' $(seq 1 400))"
ev SubagentStop "\"agent_id\":\"a2\",\"agent_type\":\"employee-x\",\"agent_transcript_path\":\"$TR\",\"last_assistant_message\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$long")" >/dev/null
check "full report kept" test "$(wc -l < "$D/agents/a2.md")" -ge 400
ev PostToolUse '"agent_id":"a3","tool_name":"SubagentHandback","tool_input":{"message":"handback report"}' >/dev/null
ev SubagentStop '"agent_id":"a3","agent_type":"employee-x","last_assistant_message":"bye"' >/dev/null
check "handback report kept" grep -q "handback report" "$D/agents/a3.md"
check "finished list points at reports" grep -q "full: agents/a3.md" "$D/finished.log"
ev SubagentStop '"agent_id":"h1","agent_type":"claude","agent_transcript_path":"/nonexistent/h1.jsonl","last_assistant_message":"ok, now lets move on"' >/dev/null
check "helper agents (no transcript) not logged" bash -c "! test -e '$D/agents/h1.md' && ! grep -q h1 '$D/finished.log'"

# 9. Subagent tool calls don't make the main session busy.
reset; ev SubagentStart '"agent_id":"a4","agent_type":"general-purpose"'; tool Read >/dev/null; write_state
ev Stop '"last_assistant_message":"waiting"' >/dev/null
ev PostToolUse '"agent_id":"a4","tool_name":"Bash","tool_input":{}' >/dev/null
check "subagent tools ignored: allowed at the break" test -z "$(ev PreCompact '"trigger":"auto"')"

# 10. Fix 7: a crash blocks compaction below the hard cap.
reset
check "bad input: blocked" blocks "$(echo 'not json' | python3 -I "$HOOK" PreCompact)"

# 11. Injection after compaction: prompts, state, tasks, replies; long logs cut to the budget.
reset; ev UserPromptSubmit '"prompt":"first prompt, verbatim"' >/dev/null
big="$(head -c 60000 /dev/zero | tr '\0' 'p')"
ev UserPromptSubmit "\"prompt\":\"$big\"" >/dev/null
ev UserPromptSubmit '"prompt":"latest prompt"' >/dev/null
for i in $(seq 1 30); do ev Stop "\"last_assistant_message\":\"reply $i $(head -c 2000 /dev/zero | tr '\0' 'r')\"" >/dev/null; done
write_state
out="$(ev SessionStart '"source":"compact"')"
check "injects the first prompt" grep -q "first prompt, verbatim" <<<"$out"
check "injects the latest prompt" grep -q "latest prompt" <<<"$out"
check "cuts the oversized prompt" grep -q "cut for length" <<<"$out"
check "injects state.md" grep -q "# state" <<<"$out"
check "injects the newest reply" grep -q "reply 30 " <<<"$out"
check "drops old replies past the budget" grep -q "older entries not shown" <<<"$out"
check "injection stays under ~25k tokens" test "${#out}" -lt 100000

# 12. Privacy: the state folder and its files are readable by the user only.
reset; ev UserPromptSubmit '"prompt":"secret pasted here"' >/dev/null
check "state folder private" test "$(stat -c %a "$W/state")" = 700
check "session folder private" test "$(stat -c %a "$D")" = 700
check "prompt log private" test "$(stat -c %a "$D/prompts.md")" = 600

# 13. Retention: old sessions are pruned at a new session's first prompt; recent ones stay.
reset; mkdir -p "$W/state/old" "$W/state/recent"; echo x > "$W/state/old/prompts.md"; echo x > "$W/state/recent/prompts.md"
touch -d '40 days ago' "$W/state/old/prompts.md" "$W/state/old"
AIBRAIN_SESSION_STATE_DAYS=30 ev UserPromptSubmit '"prompt":"first prompt of a new session"' >/dev/null
check "old session pruned" test ! -e "$W/state/old"
check "recent session kept" test -e "$W/state/recent/prompts.md"
check "current session kept" test -e "$D/prompts.md"

echo; [[ $fails -eq 0 ]] && echo "ALL PASSED" || echo "$fails FAILED"
exit $((fails > 0))
