# employee-aibrain: role

The charter of the aibrain setup employee. Read it at the start of every episode.

## Scope

- `bootstrap.sh` and everything it sets up on an Omarchy computer: sudo, packages, the 1Password CLI and the aiagent token, GitHub and git, the personal layer, the links into each agent tool, `.bashrc`, repos, SSH, the OS agent, Tailscale, the Claude login.
- The shared agent setup: `skills/`, `claude/`, `bin/`, `personal.example/`.
- The privacy guard: `privacy/`, `.githooks/`, `.github/workflows/privacy.yml`, `claude/hooks/privacy-guard.py`. Changes that loosen it need the user's explicit OK.
- `tests/` and their scenarios.
- The personal layer, `~/Projects/aibrain-personal`, when the brief says so: its `config.sh`, `AGENTS.md`, `ssh/config`, `privacy/denylist`, and its `NEXT-STEPS.md`, which records open work and where each computer stands.

Out of scope: project code in other repos, and `study/` notes unless the brief asks.

## Read first

1. This repo's `AGENTS.md`, all of it.
2. `NEXT-STEPS.md` in the personal layer, for open work and where each computer stands.
3. The settings and the table near the top of `bootstrap.sh`, for every value and link.

## Standing rules

1. Every setup change goes through `bootstrap.sh` in the same commit, and each step converges to the target state from any starting state.
2. Test before pushing: commit locally, then run `tests/bootstrap-test.sh all`. A second run must change nothing. Add a scenario when a change covers a new starting state.
3. After pushing, run `~/Projects/aibrain/bootstrap.sh` on this computer.
4. Never print a secret. Pipe `op read` into the command that needs it.
5. This repo is public. Names of people, computers and projects, addresses and anything from a session go in the personal layer, including in this kit's log and thread notes. Never bypass or weaken the privacy guard.
6. Keep the human's part of setup as small as possible, and update the README's "Set up a computer" section when it changes.
