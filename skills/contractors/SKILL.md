---
name: contractors
description: "Rules for picking, briefing and continuing contractor subagents (contractor-sonnet, contractor-opus, contractor-fable): which type and effort, what the brief carries, and when to continue one or start fresh. Load before spawning a contractor or sending one a follow-up."
---

# Contractors

A contractor is a subagent for one task or a short chain. It has no kit and no thread note, and its cache lasts 5 minutes. What it learned reaches you only through its final message. The other kind of subagent is an employee, a long-running expert for one project (the `employees` skill).

## Do it yourself or spawn

- Do it yourself when it takes a few tool calls, or when it needs what's in your context. A spawn pays a startup and a brief.
- Spawn when the work would fill your context with reading you won't need afterwards (searches, logs, many files), when independent pieces can run at once, or when another model suits the work better.
- Put independent spawns in one message, so they run in parallel.

## Type and effort

The type sets the model. Pass `effort` on every spawn: it overrides the type's default and stays in effect when you continue the agent.

| Type | Model | Spawns agents | Default effort |
|---|---|---|---|
| `contractor-sonnet` | Sonnet | never | medium |
| `contractor-opus` | Opus | only if the brief allows | medium |
| `contractor-fable` | Fable | only if the brief allows | high |

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
- **Later**, a continue re-writes its whole context at the cache-write price (1.25 times input). A fresh contractor with one consolidated brief pays its startup instead and starts small. Prefer it unless the old context is small or the state lives in the agent.
- **Don't ping a contractor to keep it warm.** Each ping is a turn for you as well, a read of your whole context, so pings pay only for gaps of a few minutes.
- **Every continue** repeats the standing directives. Directives from the first brief get lost across repeated resumes.
- A contractor that waits on a long job runs it detached and ends with WAITING, naming the result file. Check that file yourself, and continue the contractor or start a fresh one only when there's work for it.

## Checking a result

A check of a contractor's result is done by a fresh contractor that didn't do the work, given the acceptance check and the paths. Use another model when the result matters: Opus checks Sonnet's judgment calls, and Sonnet with a checklist can check Opus's mechanical claims.

## Why these numbers

The derivations are in aibrain's `study/workspace/2026-10-subagent-design.md`. The definitions are in aibrain's `claude/agents/`, which `bootstrap.sh` links into `~/.claude/agents/`. Each sets `experimental: cacheTtl: 5m` explicitly, so `ENABLE_PROMPT_CACHING_1H` can't raise it. Leave the global `subagentPromptCacheTtl` setting unset, because it overrides every agent file.
