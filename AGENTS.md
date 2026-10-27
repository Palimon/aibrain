# aibrain: rules for agents

These rules apply to work on this repo and on the personal layer that goes with it (`~/Projects/aibrain-personal`; README, "Your personal layer").

## What goes where

- This repo is public and holds the engine: `bootstrap.sh`, the settings and hooks for each tool, skills, scripts, tests, research notes, and `personal.example/`. Agent tools get it through symlinks that `bootstrap.sh` makes; the table near its top lists every link.
- The personal layer is private and holds what belongs to one person: `config.sh` (the values `bootstrap.sh` reads), `computers/<name>/` (what differs on one computer; README, "Computers"), the global instructions for every agent (`AGENTS.md`, linked as each tool's global file), `ssh/config`, `privacy/denylist`, and `NEXT-STEPS.md`, the open work.
- Keep the shared parts tool-neutral, so switching or adding tools only means adding links. Anything one tool needs goes in that tool's folder.
- Edit setup files in the repos. Because of the links, a tool writing its own config (Claude Code saving a `/model` choice, for example) changes the repo copy, and the change shows in `git status`.

## Privacy

- Nothing personal goes in this repo: no names of people, computers or projects, no email or IP addresses, tailnet names, paths under a home folder, account details, or anything from a session's history. Put such details in the personal layer, or write them generically ("my workstation", "a project of mine", `~/` paths, `example.com`, 192.0.2.x).
- The privacy guard enforces it. `privacy/scan.py` checks generic patterns and the personal layer's `privacy/denylist`. The git hooks in `.githooks/` run it on every commit and push, `.github/workflows/privacy.yml` runs it on GitHub, and `claude/hooks/privacy-guard.py` refuses git commands that would skip the hooks.
- When the scan stops a commit, remove the detail. Never bypass the hooks (`--no-verify`, `core.hooksPath`), and never loosen `privacy/scan.py`, `privacy/allow`, the hooks or the workflow to get a commit through. Changes that loosen the guard need the user's explicit OK.
- When something new turns out to be personal, add it to the personal layer's `privacy/denylist`.

## Agent skills

### Issue tracker

Specs and implementation tickets use GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default category and state roles. See `docs/agents/triage-labels.md`; `docs/agents/labels.json` defines their names, colors and descriptions. Bootstrap synchronizes them.

### Domain docs

One root glossary and architecture decision records in `docs/decisions/`, created as needed. See `docs/agents/domain.md`.

## Changing the setup

- `bootstrap.sh` must bring any Omarchy machine to the same setup from any starting state, and a second run must change nothing.
- Every change to the setup goes through `bootstrap.sh` in the same commit. That covers tools, packages, auth, shell config, git config, links, MCP servers, plugins, and anything else outside the repos the setup relies on. Make each step converge to the target state, rather than skip when something already exists.
- A value that differs from person to person is a setting: a default in `bootstrap.sh`, set in the personal layer's `config.sh`, and listed in `personal.example/config.sh`. When it differs from computer to computer, it's set in `computers/<name>/config.sh` instead, and `personal.example/computers/README.md` shows it.
- A fix for one computer goes in the personal layer's `computers/<name>/`, never only on the computer itself, so it comes back after a reinstall. `~/.config/aibrain/computer` holds the computer's name; without that file, the name is the hostname. Use a setting in its `config.sh` when the engine has one, and otherwise add a step to its `setup.sh` that changes nothing on a second run. When the fix would help other people too, add it to `bootstrap.sh` as a setting that's off by default, and turn it on for that computer.
- If the human steps change, update the README's "Set up a computer" section. Keep the human's part as small as possible. Anything a script can do goes in the script.
- Test a bootstrap change before pushing it: commit it locally, then run `tests/bootstrap-test.sh all`. It runs the script twice in throwaway homes and checks that the second run changes nothing. Add a scenario there when a change covers a new starting state. When writing a test by hand, point `HOME` and every `XDG_*_HOME` variable into the throwaway home (`XDG_CONFIG_HOME` alone still sends git and gh config to the real home), set `DBUS_SESSION_BUS_ADDRESS=disabled:` so gh can't reach the real keyring, and set `AIBRAIN_REPO` and `AIBRAIN_PERSONAL_REPO` to local checkouts. Run the test from a checkout whose `main` holds the commit under test: from another branch, its second run fetches `main` and reports a false difference.
- After changing the privacy guard, run `tests/privacy-test.sh`.
- After changing `claude/hooks/agent-cache.py`, which keeps subagents from re-writing their cache by accident (README, "Subagents"), run `tests/agent-cache-test.sh`.
- Claude Code's session-state hooks are `claude/hooks/session-state.py` (README, "Long sessions"). After changing them, run `tests/session-state-test.sh`. The live hooks fire in every Claude Code session on the machine, test sessions included, so an end-to-end test starts `claude` with `--setting-sources project` and its own `--settings` file.
- The default model and effort, Opus at medium, is `claude/managed-settings.json` (README, "Model and effort"). Model and effort values that Claude Code's pickers write into `claude/settings.json` (`model`, `modelSettings`) are per-task picks: never commit them, never ask the user about them, and discard them.
- Commit and push setup changes, in whichever of the two repos they belong, so the next bootstrap run on any machine picks them up. Then run `~/Projects/aibrain/bootstrap.sh` on this machine, so it has the change too.
- Open work is in the personal layer's `NEXT-STEPS.md`. Update it as items get done or come up.
