#!/usr/bin/env python3
"""Claude Code hooks that keep a main session's working state on disk and compact it only at
natural breaks. One script, one hook event per call: session-state.py <Event>.

Files, per session, in ~/.local/state/aibrain/sessions/<session id>/ (all but state.md written
by hooks, verbatim):
  prompts.md       every prompt the user typed, and every AskUserQuestion answer
  replies.md       every final reply of the session's turns
  agents/<id>.md   every subagent's full final report
  tasks.md         agents and jobs running at the last stop, and recently finished ones
  state.md         goal, decisions, next step, read-first list: written by the model, which the
                   Stop hook makes do it before a turn that did work can end
Bookkeeping, also in that folder: events.log (each decision), errors.log, idle, last-work,
orchestrating, near-cap-asked, stop-asks.

The rule every compaction path goes through: compaction happens only between turns (after Stop,
before the next tool call) and only while state.md is newer than the last tool call, except
past the hard cap, where it is allowed anywhere. autoCompactWindow in settings.json is the soft
cap that makes Claude Code attempt it. Near the hard cap, a tool call made while state.md is
stale asks for an update.
A turn ends with Stop, or with StopFailure when an API error ended it; either is a break. A
tool call counts as work whether it succeeds (PostToolUse) or fails (PostToolUseFailure).
When the context outgrows the window Claude Code assumes for the model (200k for a model newer
than the Claude Code build), the request is refused as too long and the turn ends; Claude
Code's own refusal, made before sending, fires neither Stop nor StopFailure. While that refusal
is the last thing the model got back, compaction is allowed anywhere, so the next turn compacts
instead of being refused again.
After a compaction, the files above are injected into the new context.
Subagent events carry agent_id: they record the subagent's report and change nothing else.
On an error the hook blocks compaction below the hard cap, unless a refusal is the last reply,
and otherwise does nothing.
Everything it writes is private to the user (the prompts can hold pasted secrets). A session's
folder is deleted once it's older than Claude Code's own transcript retention (cleanupPeriodDays,
default 30 days), checked when a session gets its first prompt.
"""
import json, os, shutil, sys, time, traceback

os.umask(0o077)

HARD_CAP = int(os.environ.get("AIBRAIN_COMPACT_HARD_CAP", "200000"))
NEAR_CAP_BELOW = 50000           # this far under the hard cap, tool calls ask for a state.md update...
NEAR_CAP_REPEAT = 25000          # ...once, then again after each 25k tokens of growth
STOP_ASKS = 3                    # times Stop asks for a state.md update before the turn may end
STATE_REQUIRED_AT = 100000       # context size that makes state.md required without subagents
PROMPT_BUDGET = 48000            # characters of prompts injected after compaction (~12k tokens)
REPLY_BUDGET = 24000             # characters of recent replies injected (~6k tokens)
ROOT = os.environ.get("AIBRAIN_SESSION_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "aibrain", "sessions")
SEP = "\n<!-- entry -->\n"
TOO_LONG = ("prompt is too long", "input is too long", "exceed context limit")
STATE_WRITERS = {"Write", "Edit", "MultiEdit"}

event = sys.argv[1] if len(sys.argv) > 1 else ""
now = time.strftime("%Y-%m-%d %H:%M:%S")
data, d = {}, ROOT


def p(name):
    return os.path.join(d, name)


def log(msg, name="events.log"):
    with open(p(name), "a") as f:
        f.write(f"{now} {event} {msg}\n")


def touch(name):
    open(p(name), "w").close()


def drop(name):
    try:
        os.remove(p(name))
    except FileNotFoundError:
        pass


def exists(name):
    return os.path.exists(p(name))


def mtime(name):
    try:
        return os.path.getmtime(p(name))
    except OSError:
        return None


def append(name, text):
    with open(p(name), "a") as f:
        f.write(text)


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason}))


def read_transcript():
    """From the main transcript's tail: ctx, the context size of the last request the API
    answered, and refused, whether a too-long refusal came after that answer."""
    t = {"ctx": 0, "refused": False}
    try:
        with open(data.get("transcript_path") or "", "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 2_000_000))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return t
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if not isinstance(e, dict) or e.get("type") != "assistant":
            continue
        if e.get("isApiErrorMessage"):  # other API errors leave an earlier refusal standing
            if any(s in line.lower() for s in TOO_LONG):
                t["refused"] = True
            continue
        msg = e.get("message")
        u = msg.get("usage") if isinstance(msg, dict) else None
        if isinstance(u, dict):
            t.update(refused=False, ctx=sum(
                u.get(k) or 0 for k in
                ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")))
    return t


def number(name):
    try:
        return int(open(p(name)).read())
    except (OSError, ValueError):
        return 0


def stale():
    """state.md is missing, or older than the last tool call that wasn't a write to it."""
    s, w = mtime("state.md"), mtime("last-work")
    return s is None or (w is not None and s < w)


def one_line(text, n=200):
    text = " ".join((text or "").split())
    return text if len(text) <= n else text[:n - 1] + "…"


def entries(name):
    try:
        return [e for e in open(p(name)).read().split(SEP) if e.strip()]
    except OSError:
        return []


def budgeted(name, budget, stubs):
    """Newest entries in full while they fit; older ones as 300-character stubs if stubs."""
    kept, used, dropped = [], 0, 0
    for e in reversed(entries(name)):
        if used + len(e) > budget and stubs:
            e = e[:300] + f"\n[…cut for length; full text in {p(name)}]\n"
        if used + len(e) > budget:
            dropped += 1
            continue
        kept.append(e)
        used += len(e)
    text = "".join(reversed(kept))
    if dropped:
        text = f"[{dropped} older entries not shown; all of them are in {p(name)}]\n" + text
    return text


def write_tasks():
    rows = data.get("background_tasks") or []
    out = [f"# Agents and jobs\n\nWritten by a hook at {now}.\n\n## Running at the last stop\n"]
    if rows:
        out.append("| type | id | status | agent | what |\n|---|---|---|---|---|")
        for t in rows:
            what = one_line(t.get("description") or t.get("command") or t.get("name") or "")
            out.append(f"| {t.get('type', '')} | {t.get('id', '')} | {t.get('status', '')} | "
                       f"{t.get('agent_type', '')} | {what.replace('|', '/')} |")
    else:
        out.append("Nothing running.")
    try:
        done = open(p("finished.log")).read().splitlines()[-15:]
    except OSError:
        done = []
    out.append("\n## Recently finished (newest last; full reports in agents/)\n")
    out.append("\n".join(done) if done else "None yet.")
    with open(p("tasks.md.tmp"), "w") as f:
        f.write("\n".join(out) + "\n")
    os.replace(p("tasks.md.tmp"), p("tasks.md"))


def same_path(a, b):
    return bool(a) and os.path.realpath(os.path.expanduser(a)) == os.path.realpath(b)


def state_spec():
    return (
        f"Before this turn ends, update {p('state.md')} with the Write or Edit tool (create it if "
        "missing; edit sections in place), as the turn's last step: compaction stays blocked "
        "while it is older than your last tool call. Keep it under about 4k tokens, with these "
        "sections: Goal and done-when; Decisions, each with why; Next step; Read first after a "
        "reset (paths); Open questions. Hooks already keep verbatim copies of every user prompt "
        f"({p('prompts.md')}), every reply you end a turn with ({p('replies.md')}), every "
        f"subagent's report ({p('agents')}/) and the running agents ({p('tasks.md')}), so don't "
        "copy those. After a compaction you get this file, the prompts, your recent replies and "
        "the agent list: write what you would need to carry on if you remembered nothing else.")


def retention_days():
    if os.environ.get("AIBRAIN_SESSION_STATE_DAYS"):
        return int(os.environ["AIBRAIN_SESSION_STATE_DAYS"])
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    try:
        return int(json.load(open(os.path.join(cfg, "settings.json"))).get("cleanupPeriodDays", 30))
    except (OSError, ValueError, TypeError):
        return 30


def prune():
    """Delete session folders untouched for longer than Claude Code keeps transcripts."""
    cutoff = time.time() - retention_days() * 86400
    for name in os.listdir(ROOT):
        folder = os.path.join(ROOT, name)
        if folder == d or not os.path.isdir(folder):
            continue
        newest = max((os.path.getmtime(os.path.join(r, f)) for r, _, fs in os.walk(folder)
                      for f in fs), default=os.path.getmtime(folder))
        if newest < cutoff:
            shutil.rmtree(folder, ignore_errors=True)


def main():
    global d
    sid = data.get("session_id") or "unknown"
    d = os.path.join(ROOT, sid)
    os.makedirs(os.path.join(d, "agents"), exist_ok=True)
    os.chmod(ROOT, 0o700)
    aid = data.get("agent_id")

    # --- Subagent reports: the only subagent events this hook records.
    if event == "SubagentStart":
        if data.get("agent_type"):  # an empty type is one of Claude Code's own helper agents
            touch("orchestrating")
        return
    if event == "SubagentStop":
        report = p(f"agents/{aid}.md")
        # Claude Code's own helpers (prompt suggestions, job summaries, the compaction summary)
        # also stop here, carrying the main session's agent type in a background job, but they
        # never write a transcript or hand back a report.
        if os.path.exists(report) or os.path.exists(data.get("agent_transcript_path") or ""):
            msg = data.get("last_assistant_message") or ""
            if os.path.exists(report):  # delivered through SubagentHandback; msg is closing text
                if msg.strip():
                    append(f"agents/{aid}.md", f"\n\n(closing text)\n{msg}\n")
                first = open(report).read()
            else:
                with open(report, "w") as f:
                    f.write(msg + "\n")
                first = msg
            append("finished.log", f"- {now} {data.get('agent_type')} {aid}: {one_line(first)} "
                                   f"(full: agents/{aid}.md)\n")
        return
    if aid:
        if event == "PostToolUse" and data.get("tool_name") == "SubagentHandback":
            with open(p(f"agents/{aid}.md"), "w") as f:
                f.write(((data.get("tool_input") or {}).get("message") or "") + "\n")
        return  # nothing else a subagent does changes the main session's state

    # --- Main session.
    if event == "UserPromptSubmit":
        if not exists("prompts.md"):
            prune()  # once per session, at its first prompt
        append("prompts.md", f"{SEP}## {now}\n\n{data.get('prompt', '')}\n")
        drop("stop-asks")  # each turn gets its own asks, even after one that ended without Stop

    elif event == "PostToolUse":
        drop("idle")
        tool, ti = data.get("tool_name"), data.get("tool_input") or {}
        wrote_state = tool in STATE_WRITERS and same_path(ti.get("file_path"), p("state.md"))
        if not wrote_state:
            touch("last-work")
        if tool == "AskUserQuestion":
            resp = data.get("tool_response")
            answers = resp.get("answers") if isinstance(resp, dict) else None
            body = "\n".join(f"- {q}: {a}" for q, a in answers.items()) \
                if isinstance(answers, dict) else json.dumps(resp)[:4000]
            append("prompts.md", f"{SEP}## {now} (answers to a question)\n\n{body}\n")
        if not wrote_state and stale():
            t = read_transcript()
            ctx, last_ask = t["ctx"], number("near-cap-asked")
            if last_ask > ctx:  # a compaction since the last ask
                last_ask = 0
            if ctx >= HARD_CAP - NEAR_CAP_BELOW and ctx >= last_ask + NEAR_CAP_REPEAT:
                with open(p("near-cap-asked"), "w") as f:
                    f.write(str(ctx))
                log(f"near the hard cap ({ctx}); asking for a state.md update")
                print(json.dumps({"hookSpecificOutput": {
                    "hookEventName": "PostToolUse",
                    "additionalContext": f"The context is at {ctx} tokens. At {HARD_CAP} Claude "
                    "Code compacts even in the middle of a turn. Update your state file now, "
                    "then carry on. " + state_spec()}}))

    elif event == "PostToolUseFailure":  # a failed tool call is work too
        drop("idle")
        touch("last-work")

    elif event == "PreCompact":
        t, idle, st = read_transcript(), exists("idle"), stale()
        ctx = t["ctx"]
        if t["refused"]:
            log(f"allow: a too-long refusal is the last reply, ctx={ctx} idle={idle} stale={st}")
        elif ctx >= HARD_CAP:
            log(f"allow at the hard cap, ctx={ctx} idle={idle} stale={st}")
        elif idle and not st:
            log(f"allow at a natural break, ctx={ctx}")
        else:
            why = "a turn is running" if not idle else "state.md is older than the last work"
            log(f"block: {why}, ctx={ctx}")
            block(f"Compaction waits: {why}.")

    elif event == "Stop":
        write_tasks()
        reply = data.get("last_assistant_message") or ""
        if reply.strip():
            append("replies.md", f"{SEP}## {now}\n\n{reply}\n")
        needed = exists("orchestrating") or read_transcript()["ctx"] >= STATE_REQUIRED_AT
        asked = number("stop-asks")
        if needed and stale() and asked < STOP_ASKS:
            with open(p("stop-asks"), "w") as f:
                f.write(str(asked + 1))
            log(f"asking for a state.md update ({asked + 1} of {STOP_ASKS})")
            again = (f"{p('state.md')} is still older than your last tool call, so compaction "
                     "stays blocked. Write it with the Write or Edit tool, not through Bash, and "
                     "make no other tool call after it. ") if asked else ""
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop",
                                                     "additionalContext": again + state_spec()}}))
            return  # the turn continues; it isn't a break yet
        drop("stop-asks")
        if needed and stale():
            log("state.md still stale after asking; compaction stays blocked")
        touch("idle")

    elif event == "StopFailure":  # an API error ended the turn: a break, with no reply to keep
        drop("stop-asks")  # and no task list to write
        log(f"turn ended by an error: {one_line(str(data.get('error') or ''), 120)}")
        touch("idle")

    elif event == "SessionStart" and data.get("source") == "compact":
        log("injecting state")
        parts = ["This conversation was just compacted. The sections below come from files kept "
                 "on disk outside the conversation, written verbatim by hooks except your own "
                 "state file. Trust them over the summary above where they differ."]
        prompts = budgeted("prompts.md", PROMPT_BUDGET, stubs=True)
        if prompts:
            parts.append(f"## Every user prompt in this session ({p('prompts.md')})\n{prompts}")
        for name, title in (("state.md", "Your state file"), ("tasks.md", "Agents and jobs")):
            if exists(name):
                parts.append(f"## {title} ({p(name)})\n\n" + open(p(name)).read())
        replies = budgeted("replies.md", REPLY_BUDGET, stubs=False)
        if replies:
            parts.append(f"## Your most recent replies, newest last ({p('replies.md')})\n{replies}")
        print("\n\n".join(parts))


try:
    data = json.load(sys.stdin)
    main()
except Exception:
    try:
        os.makedirs(d, exist_ok=True)
        log(traceback.format_exc().replace("\n", " | "), "errors.log")
    except Exception:
        pass
    if event == "PreCompact":
        try:
            t = read_transcript()
            wait = not t["refused"] and t["ctx"] < HARD_CAP
        except Exception:
            wait = True
        if wait:
            block("The session-state hook failed, so compaction waits for the hard cap.")
sys.exit(0)
