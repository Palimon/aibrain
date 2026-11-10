#!/usr/bin/env bash
# Unit tests for claude/hooks/session-state.py: feed it hook events and check what it decides.
# Runs in a throwaway folder; no Claude Code session or network needed.
# Usage: tests/session-state-test.sh
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/claude/hooks/session-state.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
# On Windows, the C:/ form, so Python can read the paths these tests put in JSON, like the Windows paths Claude Code sends
command -v cygpath >/dev/null && W="$(cygpath -m "$W")"
export AIBRAIN_SESSION_STATE="$W/state"; unset AIBRAIN_COMPACT_HARD_CAP  # the default hard cap, 200k
S=sess1; D="$W/state/$S"; TR="$W/transcript.jsonl"
fails=0

ctx() { # ctx <tokens>: make the transcript's last request this big
  printf '{"type":"assistant","message":{"model":"model-a","usage":{"input_tokens":0,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0}}}\n' "$1" > "$TR"
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
sent() { # sent: Claude Code sent a request whose reply isn't on disk yet, as at most proactive compactions
  echo '{"type":"api-request","querySource":"repl_main_thread"}' >> "$TR"
}
refused() { # refused <tokens> <window>: the API's refusal, as Claude Code writes it once its recovery failed
  printf '{"type":"assistant","isApiErrorMessage":true,"error":"invalid_request","apiErrorStatus":400,"message":{"model":"<synthetic>","content":[{"type":"text","text":"Prompt is too long"}],"usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"errorDetails":"400 {\\"type\\":\\"error\\",\\"error\\":{\\"type\\":\\"invalid_request_error\\",\\"message\\":\\"prompt is too long: %s tokens > %s maximum\\"}}"}\n' "$1" "$2" >> "$TR"
}
refused_here() { # refused_here: Claude Code's own refusal before sending, which names no numbers
  echo '{"type":"assistant","isApiErrorMessage":true,"error":"invalid_request","message":{"model":"<synthetic>","content":[{"type":"text","text":"Prompt is too long"}],"usage":{"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' >> "$TR"
}
tool() { ev PostToolUse "\"tool_name\":\"$1\",\"tool_input\":${2:-{\}}" ; }
write_state() { echo "# state" > "$D/state.md"; tool Write "{\"file_path\":\"$D/state.md\"}" >/dev/null; }
reset() { rm -rf "$W/state"; ctx 50000; }

# 1. Busy turn: compaction blocked.
reset; ev UserPromptSubmit '"prompt":"first prompt, verbatim"' >/dev/null; tool Read >/dev/null
check "blocked during a turn" blocks "$(ev PreCompact '"trigger":"auto"')"

# 2. Orchestrating session, state.md missing: Stop asks; ignored ask leaves compaction blocked.
reset; ev SubagentStart '"agent_id":"a1","agent_type":"general-purpose"'; tool Read >/dev/null
check "Stop asks for state.md" asks "$(ev Stop '"last_assistant_message":"reply one"')"
check "ignored ask: Stop asks again" asks "$(ev Stop '"stop_hook_active":true,"last_assistant_message":"reply two"')"
check "later asks say the file is still older" grep -q "still older" <<<"$(ev Stop '"stop_hook_active":true,"last_assistant_message":"reply two"')"
check "three asks ignored: Stop ends turn" test -z "$(ev Stop '"stop_hook_active":true,"last_assistant_message":"reply two"')"
check "ignored ask: compaction still blocked" blocks "$(ev PreCompact '"trigger":"auto"')"
reset; ev SubagentStart '"agent_id":"a1","agent_type":"general-purpose"'; tool Read >/dev/null
ev Stop '"last_assistant_message":"asked once"' >/dev/null
ev UserPromptSubmit '"prompt":"a new turn after an interrupted one"' >/dev/null; tool Read >/dev/null
check "a new turn's first ask starts over" bash -c '! grep -q "still older" <<<"$1"' _ "$(ev Stop '"last_assistant_message":"x"')"

# 3. State written as the last step: Stop passes, compaction allowed at the next turn.
write_state
check "fresh state: Stop passes" test -z "$(ev Stop '"last_assistant_message":"reply three"')"
check "fresh state at a break: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"
ev UserPromptSubmit '"prompt":"next"' >/dev/null
ev PostToolUseFailure '"tool_name":"Bash","tool_input":{},"error":"Exit code 1"' >/dev/null
check "a failed tool call makes the turn busy" blocks "$(ev PreCompact '"trigger":"auto"')"

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
reset; ctx 145000
check "50k under the hard cap: no ask yet" test -z "$(tool Bash)"
ctx 160000
check "near hard cap: tool call asks" asks "$(tool Bash)"
check "near hard cap: doesn't ask again right away" test -z "$(tool Bash)"
ctx 186000
check "near hard cap: asks again after 25k more" asks "$(tool Bash)"
check "the ask names the hard cap" grep -q "At 200000" <<<"$(ctx 211000; tool Bash)"
write_state
check "near hard cap, state fresh: no ask" test -z "$(tool Write "{\"file_path\":\"$D/state.md\"}")"
ctx 195000; tool Bash >/dev/null
check "just under the hard cap: blocked mid-turn" blocks "$(ev PreCompact '"trigger":"auto"')"
sent
check "a request whose reply isn't on disk yet: still blocked" blocks "$(ev PreCompact '"trigger":"auto"')"
ctx 200000; tool Bash >/dev/null
check "hard cap: allowed mid-turn" test -z "$(ev PreCompact '"trigger":"auto"')"
ctx 40000; tool Bash >/dev/null; ctx 155000
check "near hard cap after a compaction: asks again" asks "$(tool Bash)"
AIBRAIN_COMPACT_HARD_CAP=500000 ctx 210000
check "the hard cap can be set" blocks "$(AIBRAIN_COMPACT_HARD_CAP=500000 ev PreCompact '"trigger":"auto"')"

# 7b. A too-long refusal ends the turn: Claude Code's own, before sending, once the context
# passes the window it assumes for the model (no Stop or StopFailure follows it), or the API's
# after a failed recovery (StopFailure follows). Compaction is allowed until a request succeeds.
reset; ev UserPromptSubmit '"prompt":"go on"' >/dev/null; ctx 178000; tool Read >/dev/null
check "under the hard cap, mid-turn: blocked" blocks "$(ev PreCompact '"trigger":"auto"')"
refused_here
check "after Claude Code's own refusal: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"
check "the refusal is logged with the last context size" grep -q "refusal is the last reply, ctx=178000" "$D/events.log"
ev UserPromptSubmit '"prompt":"hi"' >/dev/null; sent
check "the next turn, refusal still last: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"
echo '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","message":{"model":"<synthetic>","content":[{"type":"text","text":"Rate limited"}]}}' >> "$TR"
check "another API error after it: still allowed" test -z "$(ev PreCompact '"trigger":"auto"')"
ctx 150000; tool Read >/dev/null
check "a request that succeeds ends it" blocks "$(ev PreCompact '"trigger":"auto"')"
reset; ctx 150000; tool Read >/dev/null; sent; refused 320000 300000
check "after the API's refusal: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"
check "StopFailure says nothing" test -z "$(ev StopFailure '"error":"invalid_request","error_details":"Prompt is too long"')"
check "StopFailure: the turn is over" test -e "$D/idle"
check "StopFailure leaves the agent list alone" test ! -e "$D/tasks.md"
check "StopFailure is logged" grep -q "turn ended by an error: invalid_request" "$D/events.log"
reset; echo '{"type":"user","message":{"content":"a paste too big to answer"}}' > "$TR"; refused_here
check "a refusal with no request before it: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"

# 7c. StopFailure is a break like Stop: allowed once state.md is current, and it ends Stop's asks.
reset; ev SubagentStart '"agent_id":"a1","agent_type":"general-purpose"'; tool Read >/dev/null
ev Stop '"last_assistant_message":"asked once"' >/dev/null
ev StopFailure '"error":"server_error"' >/dev/null
check "after StopFailure, stale state.md: blocked" blocks "$(ev PreCompact '"trigger":"auto"')"
check "StopFailure ends the turn's asks" test ! -e "$D/stop-asks"
write_state; ev StopFailure '"error":"server_error"' >/dev/null
check "after StopFailure, current state.md: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"

# 7d. A hook failure while a refusal is the last reply doesn't block the compaction.
reset; ctx 165000; tool Read >/dev/null; refused_here; rm -f "$D/events.log"; mkdir -p "$D/events.log"
check "failure after a refusal: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"
check "failure after a refusal: logged" test -s "$D/errors.log"
reset; ctx 205000; tool Read >/dev/null; rm -f "$D/events.log"; mkdir -p "$D/events.log"
check "failure at the hard cap: allowed" test -z "$(ev PreCompact '"trigger":"auto"')"
reset; ctx 195000; tool Read >/dev/null; rm -f "$D/events.log"; mkdir -p "$D/events.log"
check "failure under the hard cap: blocked" blocks "$(ev PreCompact '"trigger":"auto"')"

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
ev PostToolUseFailure '"agent_id":"a4","tool_name":"Bash","tool_input":{},"error":"Exit code 1"' >/dev/null
check "subagent failed tools ignored: allowed at the break" test -z "$(ev PreCompact '"trigger":"auto"')"
reset; tool Read >/dev/null; ev StopFailure '"agent_id":"a4","error":"rate_limit"' >/dev/null
check "subagent StopFailure: the main turn is still running" test ! -e "$D/idle"

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
private() { # private <path> <mode>: only this user can read it. Windows has no modes: no access for other users.
  if command -v icacls >/dev/null; then
    ! icacls "$(cygpath -w "$1")" | grep -qiE 'Everyone|BUILTIN\\Users|Authenticated Users'
  else
    test "$(stat -c %a "$1")" = "$2"
  fi
}
check "state folder private" private "$W/state" 700
check "session folder private" private "$D" 700
check "prompt log private" private "$D/prompts.md" 600

# 13. Retention: old sessions are pruned at a new session's first prompt; recent ones stay.
reset; mkdir -p "$W/state/old" "$W/state/recent"; echo x > "$W/state/old/prompts.md"; echo x > "$W/state/recent/prompts.md"
touch -d '40 days ago' "$W/state/old/prompts.md" "$W/state/old"
AIBRAIN_SESSION_STATE_DAYS=30 ev UserPromptSubmit '"prompt":"first prompt of a new session"' >/dev/null
check "old session pruned" test ! -e "$W/state/old"
check "recent session kept" test -e "$W/state/recent/prompts.md"
check "current session kept" test -e "$D/prompts.md"

echo; [[ $fails -eq 0 ]] && echo "ALL PASSED" || echo "$fails FAILED"
exit $((fails > 0))
