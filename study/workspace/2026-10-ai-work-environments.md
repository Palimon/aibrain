# AI work environments, October 2026

Research from 2026-10-11 on how well-known developers set up their environments for working with AI agents. Covers DHH, Lex Fridman and his guests, Theo Browne, Matt Pocock, poteto (Lauren Tan), Andrej Karpathy, Simon Willison, Boris Cherny and the Claude Code team, Mitchell Hashimoto, Armin Ronacher, Peter Steinberger, Geoffrey Huntley, Dex Horthy, Steve Yegge, Harper Reed, Thorsten Ball and Kent Beck.

Most positions here are under a year old. DHH went from "I don't let it drive my code" (July 2025) to "writing code by hand is now an exceptional state" (September 2026). Karpathy went from about 80% manual coding to 80% agent coding in December 2025. Treat anything from before late 2025 as history.

## Where they agree

1. **Agents need a way to check their own work.** Tests, type checks, linters, and a command that launches the app and captures a screenshot. Cherny says this gives 2-3x the quality. Huntley calls it "back pressure." poteto builds a verification CLI for each project. Theo says only 10-15% of his tokens go to writing code and the rest to verifying it.
2. **Recurring mistakes become structure.** poteto's order for where a fix goes: the codebase itself, then lint or CI, then rules, then skills, then human review. Hashimoto turns each agent mistake into an AGENTS.md entry or a script. Cherny's team adds a line to its shared CLAUDE.md.
3. **Decide before delegating.** Spec, then plan, then implement, in some form (Harper Reed, HumanLayer, Pocock's day shift and night shift, Claude Code plan mode). Specs got lighter in 2026. HumanLayer found models reliably follow only about 150-200 instructions, and Birgitta Böckeler found Spec Kit's markdown harder to review than code.
4. **Fresh context beats long sessions.** Pocock treats the first ~100K tokens as the "smart zone" and clears instead of compacting. HumanLayer targets 40-60% context use. Amp replaced compaction with handoff. Ralph restarts every loop. Durable state lives in files.
5. **Terminal plus CLIs over IDEs and MCP.** DHH runs Claude Code and Codex in Herdr and uses Neovim mostly as a file browser. Cherny uninstalled his IDE. Willison, Ronacher, Steinberger, DHH and Anthropic's guide prefer CLI tools to MCP servers. Karpathy is the exception and keeps a large IDE open to read code.
6. **One model builds, another reviews.** DHH builds with Claude and reviews with Codex at xHigh. Lex plans and reviews with Fable and implements with Opus 5. Pocock implements with Sonnet and reviews with Opus in a fresh context.
7. **Unattended agents run isolated with narrow credentials.** VMs (DHH), containers (Pocock's Sandcastle), remote machines (Theo, Steinberger). Willison gives agents staging credentials with hard budget caps. Harper Reed (2026-09-22) had an agent in a VM reach another workstation through SSH keys he had forwarded into it.

## Where they disagree

| Question | More aggressive | More conservative |
|---|---|---|
| Agents at once | Cherny 10+, DHH ~16 across mini PCs, Theo 10-12, Yegge's Gas Town 10+ | Hashimoto 1, Karpathy says swarms are premature, poteto starts at 1-5, Huntley calls multi-agent "unnecessary" |
| Read the code? | Steinberger: "I ship code I don't read." Yegge vibe-codes fully | Karpathy, Hashimoto, Willison, Ronacher, Beck read it. HumanLayer stopped for six months: "it did not end well" |
| Parallel isolation | Git worktrees (Cherny: "single biggest productivity unlock"; Theo, Pocock) | One shared checkout (Steinberger), fresh clones in /tmp (Willison) |
| Permissions | Skip permissions inside isolation (Willison, Ronacher, Steinberger) | Allowlist plus sandbox (Cherny; Omarchy 4.0.1 moved from full bypass to auto-review) |
| Local or remote | Karpathy: agents belong on your machine with your data | Thorsten Ball: "no one cares about the local dev environment anymore." Pocock and Theo moving to remote machines |
| Instruction file size | Steinberger ~800 lines | Anthropic says prune hard; HumanLayer's instruction budget |

DHH and Steinberger take a middle position on reading code: they read database-layer code closely and skim UI code.

## Warnings almost everyone gives

- **Review speed is the limit.** Willison and Ronacher say so directly, and Theo loses track past about 6 concurrent tasks.
- **Burnout and skill loss.** DHH: "This is not sustainable at all ... you can break your brain." Willison warns about "AI mania" and $1,000/day spend. Karpathy notices his hand-coding getting worse. Hashimoto keeps hand-coding the parts he enjoys on purpose.

## Named workflow patterns

- **Ralph loop (Huntley).** `while :; do cat PROMPT.md | claude-code; done`, one task per loop, tests and type checks reject bad output. Anthropic shipped an official `ralph-wiggum` plugin in late 2025. Needs a sandbox, fast deterministic checks and spend caps.
- **Research, Plan, Implement (HumanLayer).** Revised in March 2026 to six stages (questions, research, design, structure, plan, implement) with under ~40 instructions per stage. Mandatory code review is back.
- **Beads and Gas Town (Yegge).** Beads is a dependency-graph issue tracker for agents and can be adopted alone. Gas Town orchestrates 10+ agents with tmux, worktrees and Dolt. Maggie Appleton's critique: it burns "thousands of dollars a month" and design becomes the bottleneck.
- **Augmented coding (Kent Beck).** TDD from a `plan.md`, never mix structural and behavioral changes in one commit, watch for agents disabling tests.
- **Day shift / night shift (Pocock).** Human grilling session, then a PRD, then vertical-slice tickets tagged AFK or human-in-the-loop. An unattended loop implements the AFK tickets overnight, then a human does QA.
- **Trust before parallelism (poteto).** Start with 1-5 supervised conversations and scale only once verification, skills and codebase are ready.

## Applied to my setup

- Omarchy 4.0.4 already ships most of DHH's stack: Herdr, Claude Code and Codex through mise, lazygit, opencode, the agent picker, and the omarchy and diagnose-crash skills.
- The 1Password service account limited to one vault matches Willison's advice on narrow credentials.
- `OP_SERVICE_ACCOUNT_TOKEN` loads above `.bashrc`'s interactive check, so any shell that sources `.bashrc` can read the `aiagents` vault. Fine for supervised sessions. A sandbox for unattended agents shouldn't inherit it.

Starting point: 1-3 supervised agents, Claude builds and Codex reviews, keep CLAUDE.md short and push fixes into per-project lint and tests, choose a sandbox before running anything unattended.

Open decisions, in order: parallelism and isolation; permissions and sandboxing; local or remote machines; the plan and verify loop per project; how to keep my own skills sharp.

## Source caveats

Theo's material is mostly from secondhand video summaries because YouTube pages didn't load. Some X posts came through mirrors. Some claims are vendors describing their own products (Amp, HumanLayer), and CodeRabbit and Greptile sponsor Theo. Model names are quoted as the sources wrote them.

## Sources

DHH
- https://lexfridman.com/dhh-david-heinemeier-hansson-transcript/ (Jul 2025)
- https://world.hey.com/dhh/promoting-ai-agents-3ee04945 (Jan 2026)
- https://world.hey.com/dhh/clankers-with-claws-9f86fa71 (Feb 2026)
- https://newsletter.pragmaticengineer.com/p/dhhs-new-way-of-writing-code (Apr 2026)
- https://lexfridman.com/dhh-2-transcript/ (Aug 2026)
- https://world.hey.com/dhh/over-my-dead-pencil-fb0f3647 (Sep 2026)
- https://world.hey.com/dhh/basecamp-becomes-agent-accessible-3ae6b949
- https://github.com/basecamp/omarchy/releases/tag/v4.0.0

Lex Fridman and guests
- https://lexfridman.com/ai-sota-2026-transcript/ (Feb 2026)
- https://lexfridman.com/peter-steinberger-transcript/ (Feb 2026)
- https://lexfridman.com/theprimeagen-transcript/ (Mar 2025)

Theo Browne
- https://www.youtube.com/feeds/videos.xml?channel_id=UCbRP3c757lWg9M-U7TyEkXA
- https://github.com/pingdotgg/t3code
- https://finance.biggo.com/podcast/c7c3cb2193d150d2 (secondhand, May 2026)
- https://finance.biggo.com/news/1e4bc1739e6c1fa0 (secondhand, Aug 2026)
- https://sozai.app/transcript/claude-sub-watch-this/ (Oct 2026)

Matt Pocock
- https://github.com/mattpocock/skills
- https://raw.githubusercontent.com/mattpocock/sandcastle/main/README.md
- https://ai.engineer/talks/-QFHIoCo-Ko-ai-coding-workflow (Apr 2026)
- https://newsletter.pragmaticengineer.com/p/ai-skills-with-matt-pocock (Sep 2026)
- https://github.com/mattpocock/evalite

poteto
- https://api.fxtwitter.com/poteto/status/2102050467505430555 (Sep 2026)
- https://api.fxtwitter.com/poteto/status/2093799767440871583 (Aug 2026)
- https://github.com/poteto/verification-skill-example (Jul 2026)
- https://github.com/cursor/plugins/tree/main/pstack

Karpathy
- https://karpathy.bearblog.dev/year-in-review-2025/ (Dec 2025)
- https://x.com/karpathy/status/2015883857489522876 (Jan 2026)
- https://karpathy.bearblog.dev/sequoia-ascent-2026/ (Apr 2026)
- https://www.latent.space/p/s3 (Jun 2025)

Simon Willison
- https://simonwillison.net/2025/Sep/30/designing-agentic-loops/
- https://simonwillison.net/2025/Oct/5/parallel-coding-agents/
- https://simonwillison.net/2025/Oct/22/living-dangerously-with-claude/
- https://simonwillison.net/guides/agentic-engineering-patterns/
- https://simonwillison.net/2026/sep/27/2026-in-llms-so-far/

Claude Code team
- https://x.com/bcherny/status/2007179832300581177 (Jan 2026)
- https://engineeredintelligence.substack.com/p/how-the-claude-code-team-works (secondhand, Mar 2026)
- https://code.claude.com/docs/en/best-practices

Hashimoto, Ronacher, Steinberger
- https://mitchellh.com/writing/non-trivial-vibing (Oct 2025)
- https://mitchellh.com/writing/my-ai-adoption-journey (Feb 2026)
- https://lucumr.pocoo.org/2025/6/12/agentic-coding/
- https://lucumr.pocoo.org/2025/12/22/a-year-of-vibes/
- https://lucumr.pocoo.org/2026/5/24/pi-oss/
- https://steipete.me/posts/just-talk-to-it (Oct 2025)
- https://steipete.me/posts/2025/shipping-at-inference-speed (Dec 2025)

Workflow patterns
- https://ghuntley.com/ralph (Jul 2025), https://ghuntley.com/loop (Jan 2026), https://ghuntley.com/slop (Jul 2026)
- https://github.com/humanlayer/advanced-context-engineering-for-coding-agents
- https://github.com/steveyegge/beads
- https://harper.blog/2026/09/22/break-away
- https://ampcode.com/news/handoff
- https://ampcode.com/notes/what-i-want-to-tell-you-about-orbs (Aug 2026)
