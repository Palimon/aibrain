# Subagent design: employees, contractors and the cache

Discussion of 2026-10-11. It reviews an earlier, unpublished set of subagent rules (the "SI") against what others do and what Claude Code 2.1.296 supports. In short, the SI had nine contractor types, one per model and effort; employees, long-running domain experts with kits of curated knowledge; warm continuation of an instance up to about 300k tokens, with dollar thresholds for continuing versus starting fresh; and agents that wait by polling in 240-second steps. Its Claude Code facts were last probed on 2.1.284.

## Learnings

General goal: keep agents smart, not only cheap. A cache saving counts only when the warm agent does work as good as a fresh one would.

1. **Reduce agent count.** The nine contractor types exist because the Agent tool had no per-call effort on 2.1.284. One type per model (Sonnet with `omitClaudeMd` and no Agent tool, Opus, Fable) may be enough now. *Done 2026-10-16:* `contractor-sonnet` (no Agent tool), `contractor-opus` and `contractor-fable` in `claude/agents/`, linked into `~/.claude/agents/`, with `skills/contractors/` mapping the nine old model-and-effort slots onto them. `omitClaudeMd` was dropped: the global instructions file now carries the secret-handling rules and is about 1k tokens, so leaving it out would save about $0.0025 per Sonnet spawn. Tested on 2.1.300 from a fresh `claude -p` session, with the definitions symlinked into `~/.claude/agents/` (symlinks aren't documented, but they load): `contractor-sonnet` with `effort: low` ran claude-sonnet-5-5 at low and had no Agent tool; `contractor-opus` with `effort: high` ran claude-opus-5-5 at high, over its medium default; `contractor-fable` with no effort ran claude-fable-5-1 at its default high. Each wrote its startup at 5m only (11.1k, 12.2k and 12.6k tokens), none at 1h.
2. **Possibly let effort be set per spawn.** The subagents docs say the Agent tool's `effort` parameter "overrides the `effort` field and stays in effect when the subagent is resumed." *Done 2026-10-16:* the contractors skill tells the session to pass `effort` on every spawn.
3. **Check whether to keep 5-minute (contractor) agents alive with ~4.8-minute timers or drop and restart.** First-pass numbers are below. Pings are not free in quality either: each one adds a turn to the agent's context. Employees on the 1-hour cache don't need this. *2026-10-16:* the contractors skill says not to ping; a contractor that waits checks on its job itself, and work with pauses goes to an employee.
4. **Possibly lower the context threshold.** The SI continues a warm instance up to about 300k tokens. Matt Pocock's "smart zone" is about 100k (talk) to 150k (phase-boundaries doc). The SI's arithmetic prices dollars only, not the drop in quality at long context. *Decided 2026-10-15 for employees:* continue a warm instance under about 150k; past that only for a short follow-up. A cold instance always starts fresh. *Decided 2026-10-15 for main sessions (orchestrators):* soft cap 150k, compacting only at natural breaks, hard cap 500k; see "Orchestrator lifetime" below. Research the same day found no sign that orchestrators tolerate longer contexts than workers, so 150k stands for them too.
5. **Set cache lifetime per agent type:** employees `1h`, contractors `5m`. Syntax and precedence below. *Done for employees 2026-10-15, for contractors 2026-10-16.*
6. **Define employees.** None existed here yet; the SI's employees had kits of 12k-18k words each. *Done 2026-10-15:* `employee-aibrain`, defined in `.claude/agents/` with its kit in `agents/employee-aibrain/`, and the orchestrator rules in `skills/employees/`. Other projects define theirs the same way in their own repos. The kit loads through the definition body, because `memory:` does nothing with auto memory off.

## Working assumption

Subscription usage weighs tokens exactly like API list prices. Anthropic publishes no plan quotas, but its costs page says warm history is re-read "at the cached token rate" and that a miss "reprocesses your full context." So the SI's dollar arithmetic stands in for shares of the 5-hour and weekly limits.

Prices used (API list, per million tokens):

| Model | Input | Output | Cache read | 5m write (1.25x) | 1h write (2x) |
|---|---|---|---|---|---|
| Sonnet 5.5 | $2 | $10 | $0.20 | $2.50 | $4 |
| Opus 5.5 | $4 | $20 | $0.20 | $5 | $8 |
| Fable 5.1 | $10 | $50 | $0.25 | $12.50 | $20 |

## The employee idea has two halves

- **A. Expertise lives on disk; the instance is disposable.** Kit plus one thread note per open thread. This is common under other names: Yegge's Gas Town workers have "persistent identity but ephemeral sessions" with state in Beads and git hooks; Huntley's Ralph loop restarts every pass and the agent maintains its own AGENT.md; pstack's Orchestrate store and Pocock's "context pointers" do the same; Anthropic ships the agent `memory` field the employees use. poteto's "bots" (own identity and computer, permanent teammates that direct coding agents) are the always-on version.
- **B. Keep an instance warm and continue it because the cache is hot,** with dollar thresholds for continue versus fresh. Nobody else found does this. Most go the other way.

Evidence from a long unattended run under the SI (Opus employees at API prices): cold wakes made up most of its cache-write cost, and short employee episodes (three requests or fewer) cost about 33 times what contractors would have. Half B saves money only with discipline.

## What others do

**pstack** (poteto's Cursor plugin, closest match):
- `setup-pstack` maps a model to each role, with a budget dial that moves every role's effort. Defaults are xhigh everywhere; no cost model.
- The Orchestrate playbook matches the SI's employee and orchestrator rules: one writer per state file, recovery by rebuilding work rather than agents, "never resume an agent to check on it," and a brief template (goal, scope, context, acceptance, verify, timebox, forbidden, report, standing orders).
- "Fresh subagents by default." Resume only when the needed state lives in the agent: its checkout, uncommitted changes, or a running process.
- Verifiers run on a different model family from the worker.

**Matt Pocock:**
- `ask-matt/PHASE-BOUNDARIES.md` ranks "continue" first when the next phase needs this one as a primary source. It agrees with warm continuation at the session level.
- `chief-of-staff` (in progress) says "All work should be done in subagents," the opposite of the SI's do-it-yourself rule for small work.
- `implement-spec` gives each ticket its own worktree and uses a merger subagent.
- No model or effort selection anywhere in the repo.

## How each would likely judge employees

These are extrapolations from published positions, not their comments.

- **Yegge:** closest relative; would want more of it (mailboxes, handoffs, a watcher for stuck agents). Doesn't care about cost.
- **Pocock:** likes kits and thread notes; objects to continuing past the smart zone.
- **poteto:** yes to the kit, no to warm continuation; brief a fresh agent with the thread note.
- **Huntley:** half A is Ralph; rejects half B and multi-agent setups.
- **Dex Horthy:** "subagents are about context control, not role-play"; wary of named experts, would compact into the note and restart earlier.
- **Anthropic / Boris Cherny:** they built the pieces (subagent cache TTL, hooks, agent memory) but use them simply; would flag dependence on behavior that changes between releases.
- **Theo:** optimizing tokens when his limit is attention.
- **DHH:** "make it simpler."
- **Willison, Hashimoto, Karpathy:** solving a scale problem they avoid.

## Cache facts (Claude Code 2.1.296)

- **The cache never changes what the model sees.** It is a byte-for-byte prefix match, so a hit and a miss give the model identical input. It changes cost and latency only.
- **Default lifetimes:**

  | Requests | Subscription, within plan | Usage credits or API key |
  |---|---|---|
  | Main conversation | 1 hour | 5 minutes |
  | Subagents, workflows, forks, teammates | 5 minutes | 5 minutes |

- **Per-definition lifetime** (v2.1.248+), inside `experimental`, not top level:

  ```yaml
  experimental:
    cacheTtl: 1h
  ```

- **Precedence**, first match wins: `FORCE_PROMPT_CACHING_5M=1`; the `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL` env var; the `subagentPromptCacheTtl` setting; the agent file's `experimental.cacheTtl`; `ENABLE_PROMPT_CACHING_1H=1`; the default. So leave the global subagent setting unset (the SI set it to `1h`, which would override every agent file), and write `cacheTtl: 5m` explicitly on contractors so `ENABLE_PROMPT_CACHING_1H` can't raise them.
- **Exceptions:** a file's `1h` is ignored while the subscription draws on usage credits. Forks and untyped agents get the default 5 minutes. Whether a resumed subagent keeps its definition's `cacheTtl` is undocumented, but it held in the 2026-10-15 test below.
- **Subscription usage:** subagent requests draw on plan usage, and `/usage` on Pro and Max flags cache misses once they reach 10% of recent usage. Anthropic's Thariq Shihipar (2026-04-30): "A high prompt cache hit rate decreases costs and helps us create more generous rate limits for our subscription plans."

## poteto's "dropped directives"

"Interrupt-chained resumes silently drop directives" is about reliability, not the cache. When an agent is interrupted and resumed repeatedly, instructions from the original brief or earlier resumes get lost, and the agent reports "done" against its latest instruction only. Her fix: put every directive into one fresh brief, or paste the standing orders verbatim on every resume. For employees: they continue only after a clean stop, which avoids the worst case, but the original brief slides further back with every continue. Paste the thread's standing directives into every SendMessage continue.

## Keeping 5-minute contractors warm: first-pass numbers

The case: a contractor on the 5m lifetime that will be continued (the SI's "dependent chain where you judge between steps"), with a gap before the next message that may pass 5 minutes. Starting points for learning 3, not conclusions.

Three options:
- **Ping every ~4.8 minutes.** Each ping is a resumed turn: one cache read of the contractor's context, plus a few output tokens and a small tail written to its context.
- **Let it go cold, then continue.** One re-write of its whole context at the 5m write price (1.25x input).
- **Drop it and start a fresh contractor** with a consolidated brief. Pays startup (about 20k for a Sonnet contractor, per the SI) plus any re-reading, but resets the context small, which also serves the "keep agents smart" goal.

Ping versus cold continue: both scale with context size, so the break-even is the ratio of the 5m write price to the read price, at any context size:

| Model | 5m write / read | Pings that equal one cold re-write | Gap that equals |
|---|---|---|---|
| Sonnet 5.5 | $2.50 / $0.20 | 12.5 | about 60 minutes |
| Opus 5.5 | $5 / $0.20 | 25 | about 2 hours |
| Fable 5.1 | $12.50 / $0.25 | 50 | about 4 hours |

The catch is who sends the ping. In Claude Code a ping is a SendMessage from the orchestrator, so unless the orchestrator is already mid-turn, each ping also wakes the orchestrator: one cache read of its context ($0.06 for an Opus orchestrator at 300k). Example: a Sonnet contractor at 60k costs $0.012 per ping and $0.15 to re-write cold. With a $0.06 orchestrator wake per ping, pinging breaks even after about 2 pings, roughly 10 minutes. So orchestrator-driven pings pay only for short gaps, for large contractors, or when the orchestrator is awake anyway.

A cheaper variant: the contractor keeps itself warm. Run it in the background and have it poll an inbox file in steps under the TTL (the SI's existing rule is 240 seconds), while the orchestrator writes the next instruction to that file. Each poll costs only the contractor's own cache read, so the table's break-evens apply without the orchestrator term.

Timing: the cache lifetime runs from the **start** of a request, and generation time counts against it. A 4.8-minute timer must count from the start of the contractor's last request, which leaves 12 seconds of margin. The SI's 240-second step leaves 60. In transcripts measured for the SI, no request after a gap of 60-300 seconds was cold, and about 70% after gaps of 300-360 seconds were.

## Cache lifetime, measured (2026-10-15)

The 1-hour TTL costs 0.75x input more on every token written; a 5-minute TTL with keep-alives costs one read of the whole context per 4.5 idle minutes. So 1h wins when, per idle hour in gaps of 5-55 minutes, a session writes less than about 1.8x its context (Sonnet), 0.9x (Opus) or 0.45x (Fable), with ideal keep-alives. A keep-alive in Claude Code is a real turn (output tokens plus a tail that stays in the context), which moves those figures about 25% toward 1h. A 1h keep-alive every ~50 minutes always beats going cold: one re-write equals 40 reads on Opus, 80 on Fable.

Replay (`sims/ttl_sim.py`, `sims/orch_sim.py`) of a sample of real transcripts over 1 MB under both policies: main sessions cost about 10% less on 1h than on 5m with Claude Code pings; subagents cost about 35% less on 5m (they rarely idle). For Fable orchestrator sessions alone, the cache cost of 5m with no keep-alive was about 2.1 times that of 1h with no keep-alive; 5m with 4.5-minute pings came out about 35% under 1h, and 1h with 55-minute pings about 28% under. The replay picks ping-or-cold with hindsight, which favours 5m.

A modelled 36-hour Fable xhigh orchestrator (250k average context, 90k tokens written per hour, waits of 5-30 minutes) gave the same order: 5m no keep-alive $392 total; 5m with ideal `max_tokens: 0` keep-alives $200 (Claude Code can't send these; Anthropic's caching guide recommends them for Fable); 5m with keep-alive turns about $225; 1h $210; 1h with a ~50-minute ping $210. Decision: orchestrators stay on 1h (the subscription default for main sessions).

For subagents, the TTL should match how the agent waits: one that polls every 4 minutes keeps a 5m cache warm for free, so 1h is pure overhead; one that stops with WAITING and is continued later needs 1h. *Decided 2026-10-16:* see "Contractor or employee: by how the session works with it".

## Contractor or employee: by how the session works with it (2026-10-16)

The question: how does an orchestrator know whether a subagent will run long or short? Agents estimate in human hours (a "48 hours" job done in 20 minutes), so an orchestrator choosing by an estimate would pick the longest-lived type every time.

**Run length doesn't set the cache lifetime.** Every request reads the cache and restarts its clock, so an agent working nonstop keeps even a 5-minute cache warm for hours. A cache goes cold only when the agent's context sits idle past its lifetime and is then needed again: one call that blocks too long, or a continue after a pause. Both are facts at the moment they happen, so nothing needs a forecast.

**Decision (the owner's proposal, refined): choose by interaction style,** which is the orchestrator's own plan when it spawns the agent.

- **Contractor, 5m:** works until done and reports; or watches a job by checking every few minutes, since each check refreshes the cache.
- **Employee, 1h:** stops and is picked up again after a pause: a back-and-forth through the user, or a job it starts and waits for without checking. A continue after 5-55 minutes then costs a read instead of a re-write. At 60k context: Opus $0.012 against $0.30, Sonnet $0.012 against $0.15, Fable $0.015 against $0.75. The 1h premium (0.75x input on every token written: $0.18, $0.09 and $0.45 at 60k) is paid back by the first such pause.
- **General employees** `employee-sonnet`, `employee-opus` and `employee-fable` (1h, no kit, `background: true`, effort per spawn) were added so the rule applies to any work. The domain employees are employees that also carry a kit.

**A hook replaces the model's sense of time:** `claude/hooks/agent-cache.py`, PreToolUse on Bash and SendMessage, tested by `tests/agent-cache-test.sh`.

- **Bash:** a timeout over 240 seconds from a subagent whose transcript shows 5m cache writes is denied, with a detach-and-check recipe. A command that reaches its timeout moves to the background instead of being killed (tools-reference, "Timeout and output limits"), so the timeout bounds every blocking call. The hook doesn't rewrite the timeout with `updatedInput`, because a rewrite has to come with "allow", which skips the permission flow.
- **SendMessage:** a message to a stopped subagent of this session whose cache is cold, or whose context is past 150k, is denied once with the facts; a second send within 10 minutes goes through. Cold means idle longer than the lifetime less 30 seconds, counted from when its last request was sent: the transcript entry before that request's first block. The lifetime comes from the transcript's own cache writes, so it is right even where Claude Code overrides the agent file. PreToolUse `additionalContext` arrives with the tool result, after the send, so a hold has to be a deny. Run on this session's transcripts, it would have held the continue I had just sent the claude-code-guide agent, which was at 191k.
- The orchestrator can't see time passing between turns, which is why the continue rule ("within 5 minutes", "under about 55 minutes") needs the hook to supply the facts.

**Waiting without checking, tested 2026-10-16 on 2.1.300:**

- **A background subagent that ends its turn with a `run_in_background` waiter still running is woken when the waiter ends.** Test A, a general-purpose Sonnet agent in a background job: it started `sleep 400` detached at 15:07:22, started the waiter (`until [ -e DIR/status ]; do sleep 30; done`) and ended its turn. The waiter ended at 15:14:03; the agent's next request went out 2 seconds later, read the files and sent its report.
- **The orchestrator hears about it twice.** When the agent stops with its waiter live, the orchestrator gets a notice that it "is waiting on its own background work" and will report when that finishes; then the real report arrives. So each waiting employee wakes the orchestrator once in between, which costs one short turn.
- **On a 5m cache the wake re-writes the context.** Test A's wake request, 6.6 minutes after its last one, wrote all 29,896 tokens and read none. That's the cost an employee's 1h cache saves.
- **`claude -p` doesn't wait for it.** `-p` exits when the main turn ends, which ends its background agents. In one run it killed the waiter. In another, the waiter ended but the wake notice reached the agent 71 seconds late, after the main session's blocking Bash call returned. The session then ended its turn and exited before the agent ran. So waiting employees need a session that stays open: interactive, or a background job.
- **1h wake, end to end:** being tested with `employee-sonnet` in an interactive session; the result goes here.

## Orchestrator lifetime (v1, completed 2026-10-15)

Orchestrator tuning v1 is a completed work unit (2026-10-15). It covers the main session's cache lifetime (1h, above), the soft cap at 150k at natural breaks, the 500k hard cap, the session-state hooks, the managed Opus-at-medium default, and the research below confirming 150k. Left for a later version: a keep-alive for waits over an hour, idle compaction in background sessions (untested), the caveman inflow trial, and the recall-by-length probe in "Open tests".

Fable's default auto-compact point is about 967k tokens, so an unmanaged 36-hour orchestrator averages about 480k and costs about $282. Capping at 150k averages 107k and costs about $206 ($195-219 depending on summary size), with about 36 compactions; 200k costs about the same, 120k more. Compaction is risky during activity: it can drop details and direction mid-task. So:

- **Soft cap 150k, natural breaks only.** `autoCompactWindow: 150000` makes Claude Code attempt compaction; a `PreCompact` hook blocks every attempt during a turn and allows it at the first request of a turn (which follows a wait), or after 54 idle minutes (`CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS=150000`). A long turn can overshoot 150k.
- **Hard cap 500k.** Past it the hook allows compaction anywhere.
- **Hooks, not model judgment, keep the memory** (`claude/hooks/session-state.py`, files in `~/.local/state/aibrain/sessions/<session id>/`):
  - Verbatim logs: `UserPromptSubmit` logs every prompt; `PostToolUse` on `AskUserQuestion` logs the answers; `Stop` logs every reply that ends a turn (`last_assistant_message`); `SubagentStop` (or `PostToolUse` on `SubagentHandback`) saves each subagent's full report.
  - `Stop` writes the agents and jobs still running (its `background_tasks` input).
  - `state.md` (goal, decisions with why, next step, read-first paths, open questions) is the only model-written file. It counts as current only if it's newer than the last tool call that wasn't a write to it.
  - `Stop` won't let a turn end while `state.md` is stale, once the session runs subagents or holds over 100k tokens. It asks once; if the model ignores it, the turn ends but compaction stays blocked.
  - `PreCompact` allows compaction only when the session is between turns **and** `state.md` is current, or past the 500k hard cap. From 450k, `PostToolUse` asks for a `state.md` update on every tool call while it's stale, so the hard-cap compaction finds it current.
  - `SessionStart` (source `compact`) injects the prompts (about 12k tokens, older long ones cut to a stub and a path), `state.md`, the agent list and the most recent replies (about 6k tokens), labelled as more reliable than the summary.
  - The files are private (`umask 077`; bootstrap re-applies it to older files) because prompts can hold pasted secrets, and a session's folder is deleted once older than Claude Code's transcript retention (`cleanupPeriodDays`, default 30). Bootstrap dry-runs the hook on every computer and warns if it fails.
  - Subagent events (they carry `agent_id`) record reports and change nothing else. A hook error blocks compaction below the hard cap. A manual `/compact` isn't held back.
  - What hooks can't guarantee: that the model's `state.md` is good, only that it was rewritten after the last work. Everything said and reported is kept verbatim regardless.
- **One session, not a chain of fresh ones.** Background subagents and commands keep running through a compaction; a new session couldn't receive their notifications or continue them, and the model can't `/clear` itself.

Tested 2026-10-15 on Sonnet with a 100k window: compaction attempts during a turn were blocked; a turn started by a background subagent's notification, after two idle minutes while the subagent ran tools, was allowed to compact (135k down to about 20k); afterwards the model quoted the first prompt verbatim (diff-checked against the log) and recited its state file. Version 2 (same day) closed seven gaps found by review: a state update made early in a turn, an ignored update request, chat-only turns, a jump past the soft cap with no state file, the hard cap, truncated subagent reports, and hook errors failing open. `tests/session-state-test.sh` (26 checks) covers each; an isolated end-to-end run (`--setting-sources project`) repeated the notification-started compaction, and afterwards the model recalled the first prompt verbatim, a phrase from its own earlier reply, and the subagent's report.

### Is 150k right for an orchestrator? (research 2026-10-15)

Question: do orchestrators lose less to a growing context than coders and planners, so they could run longer? Nothing measured says so, and their work is the kind that degrades first. 150k stands.

- **Claude 5.x by length.** One source breaks current Claude scores down by length: GraphWalks BFS, a multi-hop graph task, run by Google for every model on its Gemini 4 Argon card (2026-10-13). Opus 5.5 scores 90.6% up to 128k and 66.8% from 256k to 1M; Fable 5.1 91.4% and 65.0% (Argon 99.7%/84.2%, GPT-6 Astra 98.7%/71.8%). Context Arena's 8-needle MRCR for Opus 5 (August data) gives 0.91 at 128k, 0.66 at 256k and 0.43 at 512k. Nothing measures 200k, so Claude's drop lies somewhere between 128k and 256k. Anthropic publishes no length curves for 5.x; its docs say "accuracy and recall degrade" as tokens grow and name no threshold. Single-needle retrieval stays near-perfect to 1M; telling similar items apart, multi-hop reasoning and keeping to rules fall first.
- **An orchestrator's work is the kind that falls first.** It tells similar reports apart (MRCR's task), combines decisions made many turns apart (multi-hop), and keeps standing rules while the latest request pulls the other way. HANDBOOK.md (2026-07-28) found strict compliance with 8-79k-token policy documents at 36% at best (Fable 5), and the failures are an orchestrator's: a fresh request overrides a standing rule, a check runs and its result is ignored, the final report claims compliance. In multi-agent systems 67.7% of failures traced to the orchestrator ("Recognize Your Orchestrator", May 2026; GPT-4o orchestrator, runs of at most 20 steps).
- **An orchestrator's context isn't mostly conversation.** Measured on a sample of real main sessions over 300k (`sims/context_composition.py`, chars/4 up to the first compaction): the orchestrators among them (5 or more spawns) hold 29% tool results, 23% tool calls, 23% user text (including injected skills and pastes), 20% subagent notices, 3% agent results and 2% their own text; the other sessions hold 54% tool results. So an orchestrator carries fewer raw tool dumps than a coder, but most of the rest is reports and decisions it must reason across.
- **Compaction hurts too, but the hooks already apply the measured fix.** Compactors kept 17% of user side-constraints on average, and an inbox agent deleted mail without approval in 30 of 100 sessions after compaction against none before ("Lost in Context Compaction", 2026-07-31). Claude Code's `/compact` on Sonnet 4.6 kept 53% of safety rules after one round and 10% after five ("The Compaction Cliff", 2026-08-24). Both papers' fix is to keep constraints outside the summary and re-attach them verbatim (over 90% kept; 96% over five rounds). CliffCompaction (2026-09-22) adds: never compact a compaction. `session-state.py` re-injects prompts, replies and the agent list from disk at every compaction, so they are never summarized twice. What can still be lost is what the model left out of `state.md` and the summary.
- **Against a tight cap.** "How Fast Do Agents Rot?" (2026-08-31; 9 models, 10,664 trajectories) found success decays with the number of dependent steps, not context length, and that bounding the context made the decay steeper. Its bounding drops history without keeping state, so it warns against truncation rather than against compaction with a state file. Practitioners split: Pocock keeps about 100k whatever the window; Horthy takes 1M-window models to 300-400k "when it feels right" (opinion, no data). Claude Code 2.1.296 lets subagents compact earlier than the main session, with no figure for the main session.
- **Conclusion.** 150k sits at the last length where Claude 5.x measures well, the orchestrator's work is what degrades first, and 200k would cost about the same, so nothing argues for raising it. The 500k hard cap is a safety ceiling for a turn that never ends: past about 250k, Opus 5.5's multi-hop score is down about 24 points. To settle it with our own data: a probe on Opus 5.5 at 150k, 250k and 400k that plants decisions across many turns and asks questions combining several of them (in "Open tests").

**Rejected: rewriting the context with caveman.** Claude Code has no operation on the context except compaction and `/rewind`. A model rewriting a 160k conversation in caveman style would write about 120k output tokens (about $6 on Fable, plus $2.40 to re-cache and 25-40 minutes) to free about 40k, which regrows in about 30 minutes; it loses detail like a summary does; and caveman's own research says compressing the user's prompts makes answers worse. Caveman's useful ideas act on what enters the context: tool output compressed on arrival with originals kept (33% fewer input tokens per session on its benchmark), terse agent-to-agent text, compressed instruction files, and a proxy keep-alive. A trial on subagent workloads is planned.

## Open tests

- ~~Spawn a throwaway agent with `cacheTtl: 1h`, continue it once, and check both runs' transcripts for `ephemeral_1h_input_tokens`.~~ Done 2026-10-15 on 2.1.299: `employee-aibrain`, spawned from a `claude -p` session and continued once with SendMessage, wrote every cache entry at 1h (16,532, 2,222, then 281 tokens on the continue, with 18,754 read). Its startup was 16.5k tokens.
- Re-probe the Claude Code facts the SI relied on, last checked on 2.1.284.
- Idle compaction in a background (unattended) session: the docs say it needs an interactive terminal session.
- The `AskUserQuestion` answer format that `PostToolUse` receives (the hook falls back to raw JSON).
- Orchestrator recall by length: plant decisions across many turns of a real orchestrator transcript, pad it to 150k, 250k and 400k, and ask Opus 5.5 questions that combine several of them. Only if 150k is questioned again.
- The SI says subagents drop to 5 minutes on usage credits even with `subagentPromptCacheTtl`; current docs rank that setting above the credits rule. Re-probe if the global setting is ever used again.

## Sources

- https://code.claude.com/docs/en/prompt-caching
- https://code.claude.com/docs/en/costs
- https://code.claude.com/docs/en/sub-agents
- https://code.claude.com/docs/en/hooks, /context-window, /settings-reference (autoCompactWindow, idleCompaction), /model-config (default auto-compact thresholds), read 2026-10-15
- https://github.com/JuliusBrussee/caveman (README, docs/technical/engine.md, architecture.md, context-recovery.md, cache-planner.md; read 2026-10-15)
- https://claude.dev/blog/lessons-from-building-claude-code-prompt-caching-is-everything/ (Thariq Shihipar, 2026-04-30)
- https://github.com/cursor/plugins/tree/main/pstack (`skills/poteto-mode/SKILL.md`, `playbooks/orchestrate.md`, `skills/setup-pstack/SKILL.md`; read at commit 11713c6, 2026-10-11)
- https://github.com/mattpocock/skills (`skills/engineering/ask-matt/PHASE-BOUNDARIES.md`, `skills/in-progress/chief-of-staff/SKILL.md`; read at commit 49dd158, 2026-10-09)
- https://github.com/steveyegge/gastown
- https://api.fxtwitter.com/poteto/status/2093799767440871583 (poteto on bots, 2026-08-29)
- Context length research, 2026-10-15: Gemini 4 Argon model card (https://deepmind.google/models/model-cards/gemini-4-argon/, GraphWalks table) and its evaluation methodology PDF; https://platform.claude.com/docs/en/build-with-claude/context-windows and /compaction; Context Arena MRCR figures for Opus 5 as cited in github.com/melodic-software/claude-code-plugins/pull/6659; arXiv 2607.25398 (HANDBOOK.md), 2606.01351 (Recognize Your Orchestrator), 2608.11242 (Lost in Context Compaction), 2608.22752 (The Compaction Cliff), 2609.26779 (CliffCompaction), 2609.01660 (How Fast Do Agents Rot?); Horthy in The Pragmatic Engineer (2026-07-15); Claude Code changelog 2.1.296
- The SI: an earlier, unpublished rule set, summarized at the top.
