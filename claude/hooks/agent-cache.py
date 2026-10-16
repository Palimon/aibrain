#!/usr/bin/env python3
"""Claude Code PreToolUse hook that keeps subagents from re-writing their cache by accident.

A prompt cache stays warm while an agent keeps making requests, however long it runs. It goes
cold only when the agent's context sits unused for longer than its lifetime (5 minutes, or an
hour for an agent file with `cacheTtl: 1h`) and is then needed again, and the next request
re-writes the context at the cache-write price, all of it past any start (Claude Code's system
prompt and tools) that other agents happen to keep cached. That happens in two ways, and this hook
handles both from the transcripts, so nobody has to guess how long anything will take:

  Bash         A subagent on a 5-minute cache may not block for longer than 240 seconds in one
               call. The call is denied, and the reason says to run the command detached and
               check on it in shorter calls.
  SendMessage  A message that would continue a stopped subagent whose cache has gone cold, or
               whose context is past 150k tokens, is denied once, with the facts: minutes idle,
               cache lifetime, context size. Sending to the same agent again within 10 minutes
               goes through, so the sender still decides.

The cache lifetime is read from the agent's own transcript (which lifetime its last cache write
used), so it is right even when Claude Code overrides the agent file. Wired in
claude/settings.json; tested by tests/agent-cache-test.sh. On any error it allows the call.
"""
import glob, json, os, sys, time
from datetime import datetime

os.umask(0o077)

MAX_BLOCK_5M = 240        # seconds one call may block for a subagent on a 5-minute cache
MARGIN = 30               # seconds kept in hand: the cache clock runs from a request's start
BIG_CONTEXT = 150000      # past this, continue an agent only for a short follow-up
RESEND_WINDOW = 600       # seconds in which a second send to the same agent goes through
RUNNING_WINDOW = 120      # an agent that wrote to its transcript this recently may be running
ROOT = os.environ.get("AIBRAIN_SESSION_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "aibrain", "sessions")


def seconds(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()


def read_agent(path):
    """Facts from a subagent transcript: its last request's start time and context size, its
    cache lifetime in seconds, its last entry's time and whether that entry is a tool call."""
    last = {"start": None, "context": 0, "ttl": 300, "last_ts": None, "in_tool": False}
    prev_ts, cur_id = None, None
    with open(path) as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            ts = e.get("timestamp")
            msg = e.get("message") if isinstance(e.get("message"), dict) else {}
            if e.get("type") == "assistant" and msg.get("usage"):
                if msg.get("id") != cur_id:  # a new request; the entry before it is when it was sent
                    cur_id = msg.get("id")
                    last["start"] = prev_ts or ts
                u = msg["usage"]
                last["context"] = sum(u.get(k) or 0 for k in (
                    "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
                    "output_tokens"))
                cc = u.get("cache_creation") or {}
                if cc.get("ephemeral_1h_input_tokens"):
                    last["ttl"] = 3600
                elif cc.get("ephemeral_5m_input_tokens"):
                    last["ttl"] = 300
            if ts:
                prev_ts = ts
                last["last_ts"] = ts
                content = msg.get("content")
                last["in_tool"] = e.get("type") == "assistant" and isinstance(content, list) and \
                    any(isinstance(c, dict) and c.get("type") == "tool_use" for c in content)
    return last


def agent_transcript(data, agent):
    """The transcript of a subagent of this session, by agent id or by name; None if not one."""
    tp = data.get("transcript_path") or ""
    folder = os.path.join(os.path.splitext(tp)[0], "subagents")
    if not tp or not os.path.isdir(folder) or not agent:
        return None
    path = os.path.join(folder, f"agent-{agent}.jsonl")
    if os.path.isfile(path):
        return path
    named = []
    for meta in glob.glob(os.path.join(folder, "agent-*.meta.json")):
        try:
            m = json.load(open(meta))
        except (OSError, ValueError):
            continue
        if m.get("name") == agent:
            named.append(meta[:-len(".meta.json")] + ".jsonl")
    named = [n for n in named if os.path.isfile(n)]
    return max(named, key=os.path.getmtime) if named else None


def agent_type(path):
    try:
        return json.load(open(path[:-len(".jsonl")] + ".meta.json")).get("agentType") or "agent"
    except (OSError, ValueError):
        return "agent"


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny",
                                             "permissionDecisionReason": reason}}))


def ago(secs):
    mins = max(1, round(secs / 60))
    if mins < 90:
        return f"{mins} minute{'s' if mins > 1 else ''} ago"
    return f"{round(mins / 60)} hours ago"


def lifetime(ttl):
    return "an hour" if ttl >= 3600 else "5 minutes"


def check_bash(data):
    aid, ti = data.get("agent_id"), data.get("tool_input") or {}
    if not aid or ti.get("run_in_background"):
        return  # the main session keeps an hour-long cache; a background command doesn't block
    timeout = ti.get("timeout")
    if not isinstance(timeout, (int, float)) or timeout <= MAX_BLOCK_5M * 1000:
        return
    path = agent_transcript(data, aid)
    facts = read_agent(path) if path else {"ttl": 300, "context": 0}
    if facts["ttl"] >= 3600:
        return  # Bash's own limit (10 minutes) keeps an hour-long cache warm
    size = f" (up to about {round(facts['context'] / 1000)}k tokens)" if facts["context"] else ""
    deny(f"Your cache lasts 5 minutes, so a call that blocks for longer than {MAX_BLOCK_5M} "
         f"seconds makes your next request re-write your context{size}. Start the command "
         "detached, with its output and exit status going to files, for example "
         "`nohup sh -c 'CMD; echo $? > DIR/status' > DIR/out 2>&1 &`, then check on it in calls "
         f"of {MAX_BLOCK_5M} seconds or less, such as "
         "`timeout 230 sh -c 'until [ -e DIR/status ]; do sleep 10; done'` with the Bash "
         f"timeout set to {MAX_BLOCK_5M * 1000}.")


def check_send(data):
    to = ((data.get("tool_input") or {}).get("to") or "").strip()
    if " [" in to:
        to = to.split(" [", 1)[0]
    if not to or to == "main":
        return
    path = agent_transcript(data, to)
    if not path:
        return  # not a subagent of this session: another session, a teammate, or unknown
    facts = read_agent(path)
    if not facts["start"] or not facts["last_ts"]:
        return
    now = time.time()
    if facts["in_tool"] or now - seconds(facts["last_ts"]) < RUNNING_WINDOW:
        return  # it may still be running, and a message to a running agent just queues
    idle = now - seconds(facts["start"])
    cold = idle > facts["ttl"] - MARGIN
    big = facts["context"] >= BIG_CONTEXT
    if not cold and not big:
        return
    # A second send to the same agent within the window goes through: the sender has the facts.
    folder = os.path.join(ROOT, data.get("session_id") or "unknown")
    os.makedirs(folder, exist_ok=True)
    held_path = os.path.join(folder, "held-continues.json")
    try:
        held = json.load(open(held_path))
    except (OSError, ValueError):
        held = {}
    held = {k: v for k, v in held.items() if now - v < RESEND_WINDOW}
    if to in held:
        del held[to]
        json.dump(held, open(held_path, "w"))
        return
    held[to] = now
    json.dump(held, open(held_path, "w"))
    kind, k = agent_type(path), round(facts["context"] / 1000)
    if cold:
        why = (f"{to} ({kind}) last made a request {ago(idle)} and its cache lasts "
               f"{lifetime(facts['ttl'])}, so it has gone cold: this message would make it re-write "
               f"its context, up to about {k}k tokens, at the cache-write price.")
    else:
        why = (f"{to} ({kind}) is still warm, but its context is about {k}k tokens, past "
               f"{BIG_CONTEXT // 1000}k, where a continue suits only a short follow-up.")
    deny(why + " Unless what you need lives in that agent (its checkout, uncommitted changes, "
         "a running process, or reading that would take long to repeat), start a fresh agent "
         "with one consolidated brief instead; for an employee, a fresh instance that reads its "
         "kit and thread note. To continue this one anyway, send the message again.")


def main():
    data = json.load(sys.stdin)
    tool = data.get("tool_name")
    if tool == "Bash":
        check_bash(data)
    elif tool == "SendMessage":
        check_send(data)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # never stand in the way of a tool call because this hook broke
