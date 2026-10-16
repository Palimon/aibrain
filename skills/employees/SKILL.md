---
name: employees
description: "Rules for briefing, continuing and retiring employee subagents: the domain employees with a kit (employee-<domain>) and the general ones (employee-sonnet, employee-opus, employee-fable). Load before spawning an employee, before sending one a follow-up, and when picking up a project's open employee threads after a session ended."
---

# Employees

An employee is a subagent with a 1-hour cache, for work with pauses in it: a back-and-forth with you, or a job it starts and waits for. Choose an employee or a contractor by how you'll work with the agent, never by how long the work might take; the `contractors` skill says why. There are two kinds:

- **General employees**, `employee-sonnet`, `employee-opus` and `employee-fable` in aibrain's `claude/agents/`, have no kit. Pick and brief them like the contractor on the same model (the `contractors` skill), and continue them by the rules below.
- **Domain employees**, `employee-<domain>`, are experts for one project whose knowledge outlives each instance. Most of this skill is about them.

An employee waiting on a long job starts a background waiter and stops. You get a notice that it's waiting on its own background work, which isn't its report, and Claude Code wakes it when the waiter ends. That needs a session that stays open, interactive or a background job: `claude -p` exits when its turn ends, and the employee never wakes.

A domain employee is made of three things, all in that project's repo:

- **The definition**, `.claude/agents/employee-<domain>.md`: model, effort, a 1-hour cache lifetime, and the instance protocol.
- **The kit**, `agents/employee-<domain>/`: `ROLE.md` (charter and standing rules), `KNOWLEDGE.md` (curated facts with sources), `LOG.md` (one entry per episode), and `threads/<thread>.md` (one note per open thread).
- **The thread notes**, which say where each open piece of work stands, so any new instance can pick it up.

An instance is one agent started from the definition. It lasts one episode, from its brief to its final message, and is disposable. Everything worth keeping goes into the kit.

## What goes to a domain employee

- Judgment in its domain that benefits from what earlier episodes learned.
- Not clerk work: reruns of a known command, landings, copies, checks that need no domain judgment, or anything expected to take three requests or fewer when no instance is warm. Do those yourself or give them to a contractor with the steps pasted. An employee's startup and kit read are cached at the 1-hour write price (2x input, against 1.25x for a contractor), and the kit grows with every episode.
- A verifier for an employee's result is a contractor given the kit paths to read, not a second instance.

## Briefing a fresh instance

Spawn it by name from a session in its project. The brief carries:

1. The task and the acceptance check.
2. The thread name. New thread: say so. Existing thread: the instance reads its note.
3. The branch to commit on, if the work changes code.
4. Whether it may spawn contractors.
5. The thread's standing directives, verbatim, if there are any.

The instance reads its own kit; don't paste kit content into the brief.

## Continuing or starting fresh

When an instance stops, decide in the same turn: send it everything queued for it in one message, or close it. Don't hold work back to batch it.

You can't see how much time has passed, so a hook (`claude/hooks/agent-cache.py`) checks each continue. It holds the message once if the instance's cache has gone cold or its context is past 150k, and tells you how long it has been idle and how big it is. Decide by the rules below, then start fresh or send the message again.

- **Warm** (stopped under about 55 minutes ago): continue it while its context is under about 150k tokens. Past 150k, continue only for a short follow-up (a few requests); otherwise start fresh from the kit and the thread note. The 150k line keeps instances in the range where the model works well, not only where the cache pays.
- **Cold** (over about 55 minutes): start fresh. A cold continue re-writes nearly the whole context at the cache-write price, and the fresh instance restarts small.
- **Every continue** pastes the thread's standing directives again. Directives from the original brief get lost across repeated resumes.
- The context size at a stop is the `subagent_tokens` figure in its stop notification.

## After a session ends

Old instance ids can't be reached from a new session. Rebuild threads, not instances: read `agents/employee-*/threads/*.md`, check any running job a note lists, and brief a fresh instance per open thread, telling it to check `git status` in its worktree first.

## Adding an employee

1. Copy an existing definition, such as aibrain's `.claude/agents/employee-aibrain.md`, and change the name, description, model, effort and paths. Keep `experimental: cacheTtl: 1h` and `background: true` (a waiter it starts keeps running only in a background agent).
2. Create the kit folder with `ROLE.md`, `KNOWLEDGE.md`, `LOG.md` and `threads/.gitkeep`.
3. Keep `KNOWLEDGE.md` to facts the repo's own docs don't hold. Point to the docs for the rest.
4. Never rename or delete a definition while an instance of it may be continued: a continue then resumes it as a general-purpose agent with a cold cache.

## Why these numbers

The derivations are in aibrain's `study/workspace/2026-10-subagent-design.md`. Cache lifetime is set per definition with `experimental.cacheTtl`; leave the global `subagentPromptCacheTtl` setting unset, because it overrides every agent file. On usage credits a definition's `1h` is ignored and subagents get 5 minutes.
