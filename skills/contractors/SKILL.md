---
name: contractors
description: "Rules for picking, briefing and continuing contractor subagents (contractor-sonnet, contractor-opus, contractor-fable) and general employees (employee-sonnet, employee-opus, employee-fable): contractor or employee, which type and effort, what the brief carries, and when to continue one or start fresh. Load before spawning either or sending one a follow-up."
---

# Contractors

A contractor is a subagent for one task, or a few steps you send it one at a time. It has no kit and no thread note, and its cache lasts 5 minutes. What it learned reaches you only through its final message. The other kind of subagent is an employee, with a 1-hour cache for work with pauses in it. Some employees also carry a kit for one project's domain (the `employees` skill).

## Contractor or employee

Choose by how you'll work with the agent, never by how long the work might take. Agents tend to estimate in human hours, so a guess of two days can mean twenty minutes. How you'll work with it is your own plan, which you know when you spawn it.

- **Contractor (5-minute cache):** it works until it's done and reports, and you don't plan to come back to it. That includes watching a job by checking on it every few minutes: each check is a request, so the cache stays warm however long it runs.
- **Employee (1-hour cache):** it stops and gets picked up again after a pause. Use one for a back-and-forth (it reports, you or the user think, you send the next step), or for a job it starts and waits for without checking on it. A continue after a pause of 5 to 55 minutes then costs a read of its context instead of a re-write: on Opus at 60k, about $0.01 instead of $0.30. The 1-hour cache makes every token it writes cost 60% more, which the first such pause pays back.

The general employees, `employee-sonnet`, `employee-opus` and `employee-fable`, take the same picks and briefs as the contractors below. When the work is in a domain that has its own employee with a kit (`agents/employee-<domain>/`), use that one instead (the `employees` skill).

A cache goes cold by accident in two ways, and a hook handles both (`claude/hooks/agent-cache.py`):

- **One call blocks too long.** A subagent on a 5-minute cache can't set a Bash timeout over 240 seconds. It runs a longer command detached and checks on it.
- **You continue an agent after a pause.** The hook holds the message once if the agent's cache has gone cold or its context is past 150k, and tells you how long it has been idle and how big it is. Send the message again to continue anyway.

## Do it yourself or spawn

- Do it yourself when it takes a few tool calls, or when it needs what's in your context. A spawn pays a startup and a brief.
- Spawn when the work would fill your context with reading you won't need afterwards (searches, logs, many files), when independent pieces can run at once, or when another model suits the work better.
- Put independent spawns in one message, so they run in parallel.

## Type and effort

The type sets the model and the cache. Pass `effort` on every spawn: it overrides the type's default and stays in effect when you continue the agent.

| Type | Model | Spawns agents | Default effort |
|---|---|---|---|
| `contractor-sonnet` | Sonnet | never | medium |
| `contractor-opus` | Opus | only if the brief allows | medium |
| `contractor-fable` | Fable | only if the brief allows | high |
| `employee-sonnet`, `employee-opus`, `employee-fable` | as named | as for the contractor on that model | as for the contractor on that model |

| Pick | For |
|---|---|
| Sonnet, low | Mechanical work the brief fully specifies, with a checkable result: greps, inventories, format conversions, pattern edits with tests. |
| Sonnet, medium | Reading that needs care: read across many files and report, extract or summarize, land a verified branch, implement an exact spec with tests. |
| Sonnet, high | Careful reading or checking where a miss is costly but the design is settled: audits against a checklist, migrations to a precise spec, repairing test suites. |
| Sonnet, xhigh | Rare: a long mechanical chain to an exact spec, after high failed once. If judgment is what's missing, use Opus instead. |
| Opus, low | Quick judgment on small input: triage, ranking, choosing between stated options, checking one claim, dense material Sonnet misreads. |
| Opus, medium | Code and judgment that must be right first time: debugging an unknown cause in one component, implementing from a loose brief, designing one component, reviewing a diff for subtle errors. |
| Opus, high | Open-ended judgment: architecture, security review, intermittent or cross-service failures, synthesis across sources you haven't read, specs other agents build from. |
| Opus, xhigh | Problems at the reasoning ceiling where a wrong answer is expensive: subtle correctness or concurrency bugs, proofs, or after high fell short. |
| Fable, high | The hardest judgment or synthesis, after Opus at xhigh was wrong, or for a spec others build from. Fable costs 2.5 times Opus per token. When the work needs your own context, fork instead. |

There's no Haiku type: Sonnet at low effort covers that work. The built-in Explore agent is still fine for a read-only search.

## The brief

A fresh contractor knows only its brief and the working directory's instruction files. The brief carries:

1. The goal, and why it matters.
2. The scope: where to work, and what's out of bounds.
3. What you already know that it would otherwise rediscover. Give paths to read rather than pasting files.
4. The acceptance check: what makes the result right, and the command that shows it.
5. What to return, and how long. A long result goes in a file the report names.
6. Whether it may commit, push, or spawn agents (Opus and Fable only).
7. The user's standing directives that apply, verbatim.

## Continuing or starting fresh

Start a fresh contractor by default. Continue one only when what you need lives in it: its checkout, uncommitted changes, a running process, or reading that would take long to repeat.

- **Within 5 minutes** of its last request, a continue reads its context from the cache.
- **Later**, a continue re-writes its context at the cache-write price (1.25 times input), all but a start that other agents may keep cached. A fresh contractor with one consolidated brief pays its startup instead and starts small. Prefer it unless the old context is small or the state lives in the agent. You can't see how much time has passed, so the hook tells you: when it holds a message, decide from the facts it gives, then spawn fresh or send again.
- **Don't ping a contractor to keep it warm.** Each ping is a turn for you as well, a read of your whole context, so pings pay only for gaps of a few minutes.
- **Every continue** repeats the standing directives. Directives from the first brief get lost across repeated resumes.
- A contractor that waits on a long job checks on it itself for up to about an hour, because a check costs only a read of its own context and wakes no one. Past that it ends with WAITING, naming the output and status files. Check those yourself, and continue the contractor or start a fresh one only when there's work for it.

## Checking a result

A check of a contractor's result is done by a fresh contractor that didn't do the work, given the acceptance check and the paths. Use another model when the result matters: Opus checks Sonnet's judgment calls, and Sonnet with a checklist can check Opus's mechanical claims.

## Why these numbers

The derivations are in aibrain's `study/workspace/2026-10-subagent-design.md`. The definitions are in aibrain's `claude/agents/`, which `bootstrap.sh` links into `~/.claude/agents/`. Each sets `experimental: cacheTtl: 5m` explicitly, so `ENABLE_PROMPT_CACHING_1H` can't raise it. Leave the global `subagentPromptCacheTtl` setting unset, because it overrides every agent file.
