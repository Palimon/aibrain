# Your personal layer

This folder is the template for `~/Projects/aibrain-personal`, the private half of an aibrain setup. The public repo, `~/Projects/aibrain`, holds the engine and nothing about you. This layer holds what's yours:

| Path | What it is | Used by |
|---|---|---|
| `config.sh` | Your values for `bootstrap.sh` on every computer: git identity, which repos to clone | `bootstrap.sh` reads it on every run |
| `computers/<name>/` | What differs on one computer: `config.sh` with settings for it alone, `setup.sh` with steps no setting covers. See `computers/README.md` | `bootstrap.sh`, on that computer |
| `setup.sh` | Optional: steps of your own for every computer, which must change nothing on a second run | `bootstrap.sh` runs it at the end |
| `AGENTS.md` | Your instructions for every agent | Linked as `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` and `~/.grok/AGENTS.md` |
| `ssh/config` | SSH shortcuts to your computers and servers | An `Include` at the top of `~/.ssh/config` |
| `privacy/denylist` | Names, addresses and anything else of yours that must never reach the public repo | The privacy guard (`privacy/scan.py` in aibrain) |
| `skills/`, `bin/` | Optional: your own skills and scripts. One here wins over aibrain's with the same name | Linked like aibrain's |
| `NEXT-STEPS.md` | Your open work on the setup | You and your agents |

Keep it in a private repo named `aibrain-personal` on your GitHub account. `bootstrap.sh` finds it there by that name and clones it on every new computer. A first run without one copies this template to `~/Projects/aibrain-personal` for you to fill in.
