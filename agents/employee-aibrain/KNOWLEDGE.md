# employee-aibrain: knowledge

Facts the repo's own docs don't hold, each with its source. `AGENTS.md` and `README.md` are canon; don't copy them here. Facts about particular computers or people go in the personal layer, never here: this repo is public.

## Contents

- [Claude Code](#claude-code)
- [Testing Claude Code sessions](#testing-claude-code-sessions)
- [The privacy guard](#the-privacy-guard)

## Claude Code

- `autoMemoryEnabled` is `false` in `claude/settings.json`. With auto memory off, the agent `memory:` frontmatter field does nothing, so employees name their kit in the definition body instead. Source: code.claude.com/docs/en/sub-agents, "Enable persistent memory", read 2026-10-15.
- `ENABLE_PROMPT_CACHING_1H` and `subagentPromptCacheTtl` are unset, so each agent file's `experimental.cacheTtl` decides its cache lifetime. Setting either globally would override or raise every agent file. Source: `study/workspace/2026-10-subagent-design.md`.
- Claude Code attempts auto-compaction before a request would cross `autoCompactWindow`, judging by the coming request's size: with a 100k window it tried at 66k, 88k and 111k during one turn. Source: session-state test, 2026-10-15.

## Testing Claude Code sessions

- `claude -p` waits for background subagents and handles each completion notification as a new turn in the same process, so a turn started by a notification can be tested headless. Source: session-state end-to-end test, 2026-10-15.
- Claude Code refuses a standalone foreground `sleep` in Bash, even inside a subagent. To make a test agent wait, run `python3 -c 'import time; time.sleep(N)'`. Source: same test.
- Claude Code's own safety check refuses `rm -rf` on a relative glob after a `cd` in the same command. Give a literal absolute path, or avoid the delete (session folders are per session id anyway). Source: same day.
- A test session's hooks and settings: `--setting-sources project` leaves out `~/.claude/settings.json` (so the live hooks don't run), and `--settings <file>` supplies the test's own. Put `permissions.defaultMode: bypassPermissions` in that file, or tool calls are refused in `-p` mode. Source: same test.
- Enter in the `/model` picker can't be rebound: with `"enter": "modelPicker:thisSessionOnly"` in the `ModelPicker` context, Enter still saved the pick as the default (tested 2.1.299 in tmux, 2026-10-15). The docs say the same of the `/effort` slider. Managed settings are the fix: with `model` and `modelSettings` in `/etc/claude-code/managed-settings.json`, new sessions started on Opus 5.5 at medium even when user settings said Sonnet and xhigh, an in-session pick still switched, and the picker showed "Using Opus 5.5 (from managed settings)". Source: same tests.
- Driving an interactive session for a test: `tmux -L <socket> new-session -d ... "env -i HOME=$HOME USER=$USER PATH=$PATH TERM=tmux-256color claude"`. Without `env -i`, the new session inherits the calling session's `CLAUDE_CODE_SESSION_ID` and other variables and shows its name. The first start may ask "Make auto mode your default permission mode?"; answer No. Source: same tests.
- Background jobs run inside a long-lived `claude bg-spare` process. Leaving or `/exit`ing a job's view doesn't restart it, so settings read at startup, such as `autoCompactWindow`, never reach a running job; `/autocompact <tokens>` sets the window in the running session. Source: a background job started before the change kept its 1m window after `/exit`, while a fresh session got 150k (2026-10-15).
- `/autocompact <tokens>` saves into `~/.claude/settings.json` as `modelSettings.<model>.autoCompactWindow`, so it shows in aibrain's `git status`; bootstrap's reset of `modelSettings` puts it back. Source: 2026-10-15.
- Claude Code's own helper agents (next-prompt suggestions, job summaries, the compaction summarizer) fire `SubagentStop` but not `SubagentStart`. In a session with a main agent (`--agent`, as background jobs run with `claude`) they carry that agent's type, not an empty one, and their `agent_transcript_path` never exists. A real subagent has a transcript at its stop, so the session-state hook logs only stops whose transcript or handback report exists. Source: raw hook input captured in a tmux session with `--agent claude`, 2026-10-15.
- `tailscale status` can list a computer as offline while SSH to it works. Try SSH before deciding a computer is down. Source: observed 2026-10-15.

## The privacy guard

- `claude/hooks/privacy-guard.py` reads one shell command line at a time. A Bash command naming this repo that has `git` and then `--no-verify` on one line is refused even when the line is documentation inside a heredoc, so write such text with the Edit tool. Its first version matched `core.hooksPath` anywhere and refused a commit of this kit; it now refuses only setting, unsetting or overriding it. Source: 2026-10-15.
- A fine-grained GitHub token without the Secrets permission gets `HTTP 403: Resource not accessible by personal access token` from `gh secret set` (on `actions/secrets/public-key`). Bootstrap's copy of the denylist to the `AIBRAIN_DENYLIST` secret needs Secrets and Variables write access on the token. Source: 2026-10-15.
