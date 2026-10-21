# aibrain

A setup for AI agent tools on [Omarchy](https://omarchy.org), the same on every computer you own, and on Ubuntu for a computer without Omarchy, such as a headless server. It isn't tied to one tool: today it configures Claude Code, Codex and Grok, and adding another tool means adding a few links. One script, `bootstrap.sh`, brings a computer from any state to the full setup, and running it again changes nothing.

What it gives you:

- **One set of instructions and skills** for every agent tool, linked from a repo, so a change reaches every tool and every computer.
- **Secrets through a 1Password service account** limited to one vault. Agents read keys with `op read` and never see more than that vault.
- **Long Claude Code sessions that keep their memory.** Hooks compact a session only at a natural break and keep every prompt, reply and subagent report on disk (see [Long sessions](#long-sessions)).
- **Opus at medium effort as the fixed default,** with per-task model picks that never stick (see [Model and effort](#model-and-effort)).
- **Subagents in two kinds:** contractors that work until done, on a 5-minute cache, and employees for work with pauses, on a 1-hour cache, some with a kit on disk; one type per model, with the effort set per spawn; the research behind each choice is in `study/` (see [Subagents](#subagents)).
- **Your computers joined up:** GitHub, SSH with one key, Tailscale, and an OS agent on a hotkey.
- **A privacy guard** that keeps personal details out of this public repo (see [Privacy guard](#privacy-guard)).

## Two repos

| Repo | Folder | Holds |
|---|---|---|
| aibrain, this one, public | `~/Projects/aibrain` | The engine: `bootstrap.sh`, tool settings and hooks, skills, scripts, tests, research, and `personal.example/` |
| Your personal layer, private | `~/Projects/aibrain-personal` | What's yours: `config.sh`, your instructions for every agent, SSH shortcuts, the privacy denylist, your open work |

`bootstrap.sh` keeps both up to date and links the agent tools to them. See [Your personal layer](#your-personal-layer).

## Set up a computer

This works on any Omarchy computer, freshly installed or already in use, and on Ubuntu (see [On Ubuntu](#on-ubuntu)). Running it again later is safe. It brings the computer up to date and changes nothing that's already right.

### Before the first computer

1. **A vault for agents.** In 1Password, create a vault named `aiagents` and a service account with read and write access to it and nothing else (Developer > Service Accounts). Keep the service account's token in an item in your own vault, so you can copy it on each new computer.
2. **Items the script reads**, in `aiagents`, each an API Credential item with the value in its credential field:
   - "GitHub Agent": a fine-grained GitHub token for your account with access to all repositories (Contents, Administration, Secrets and Variables read and write). The script warns two weeks before it expires.
   - "ssh fleet key": an SSH Key item, the key every computer uses for your servers and for each other.
   - "Tailscale auth key", optional: a Reusable key from the Tailscale admin console (Settings > Keys), so computers join your tailnet without a browser login. It lasts at most 90 days.
3. **Your personal layer,** optional for the first run: a private repo named `aibrain-personal` on your GitHub account, with the contents of `personal.example/` filled in. Without one, the first run copies the template to `~/Projects/aibrain-personal` for you to fill in and push.

### On each computer

1. Open the service account's token item in 1Password in the browser.
2. Open [`bootstrap.sh`](bootstrap.sh) on GitHub and click **Copy raw file**.
3. Open a terminal (Super+Return) and type:

       bash <(wl-paste)

Answer what it asks. Depending on what the computer already has, that's some of:

1. **Your password**, for the last time. The script makes sudo passwordless, so agents can change the system without asking.
2. **Light or full.** Light sets up the agent tools. Full also clones every repo on your GitHub account into `~/Projects`. The answer is saved, so it's only asked once. To switch a computer later, run `AIBRAIN_SETUP=full ~/Projects/aibrain/bootstrap.sh`.
3. **The aiagent token.** Copy it from the 1Password tab, paste it, and press Enter. The terminal doesn't show what you paste.
4. **New computer or existing?** For one you're setting up again after a reinstall, answer existing and pick it from the list; it gets its settings back. For a new one, give it a name. It's asked once (see "Computers").
5. **The Tailscale login.** The terminal shows a login.tailscale.com link. Open it and sign in. This is skipped when the vault has a "Tailscale auth key" item.
6. **The Claude login.** A browser page opens. Sign in with your claude.ai account.

It ends with "aibrain setup complete." Open a new terminal and start your agent, for example `claude`, or press Ctrl+Super+Shift+A for the OS agent. Codex asks you to log in the first time you run `codex`.

### On Ubuntu

The same script runs on Ubuntu; 24.04 is the version the tests cover. The differences:

- **Start it over SSH** or on the computer's console, since a server has no clipboard: `bash <(curl -fsSL <raw URL of bootstrap.sh>)`. The questions are the same.
- **Packages come from apt.** Ubuntu's own repos supply the basics Omarchy ships with (curl, gpg, git, jq, Python), and the vendors' apt repos supply the 1Password CLI, mise and Tailscale. Codex comes through mise; Omarchy installs it itself.
- **There's no desktop,** so the Omarchy pieces are left out: the Hyprland keys, Taildrop receiving, the bar widget and the web app. A `.bashrc` block puts mise's tools and `~/.local/bin` on the PATH, which Omarchy does by itself.
- **The SSH server** is Ubuntu's `ssh.service`, or `ssh.socket` when that starts it, as on a fresh 24.04. Nothing sets up a firewall.

For a server, give the computer `HEADLESS=1`, and `CODEX_ONLY=1` when Codex is its only agent tool (see "Computers").

An agent can run it too, as `~/Projects/aibrain/bootstrap.sh`. Without a terminal it can't ask for anything, so it needs `OP_SERVICE_ACCOUNT_TOKEN` set and the 1Password CLI already installed. It sets up light unless the computer has a saved choice or `AIBRAIN_SETUP` is set, and `AIBRAIN_COMPUTER=<name>` tells it which computer it's on.

## Your personal layer

`~/Projects/aibrain-personal` holds everything about you, so this repo can stay public. `personal.example/` is its template:

| Path | What it is |
|---|---|
| `config.sh` | Your values for `bootstrap.sh` on every computer: git identity, the identity for commits to this repo, vault and item names, which repos to clone. Every setting and its default is listed in the template. |
| `computers/<name>/` | What differs on one computer: settings in `config.sh`, and steps of your own in `setup.sh`. See "Computers" below. |
| `setup.sh` | Optional: steps of your own that `bootstrap.sh` runs at the end, on every computer |
| `AGENTS.md` | Your instructions for every agent, linked as `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` and `~/.grok/AGENTS.md` |
| `ssh/config` | SSH shortcuts to your computers and servers, included at the top of `~/.ssh/config` |
| `privacy/denylist` | Names, addresses and anything else of yours that must never reach this repo |
| `skills/`, `claude/agents/`, `bin/` | Optional skills, Claude Code agents and scripts of your own, linked like this repo's. One there wins over one here with the same name. |
| `NEXT-STEPS.md` | Your open work on the setup |

The script finds the layer's repo in this order: `AIBRAIN_PERSONAL_REPO` when set (a URL or a path, or `none` for a plain folder), the existing checkout's own remote, then `aibrain-personal` on the GitHub account the script logs in as. It keeps the checkout up to date the same way as this repo's.

### Computers

Every computer has a folder in the personal layer, named after it, for what differs on that computer alone. The script adds the folder for a new computer, commits it and pushes it, so every run applies it again, and so does the first run after a reinstall:

- `computers/<name>/config.sh` sets settings for that computer on top of `config.sh`. Its first line says what the computer is (hardware and the date it was added). Any setting can go there. These usually do: `TS_SHARE_LAN` on the computer that shares your LAN with the tailnet, `TS_ACCEPT_ROUTES=0` on the other computers on that LAN (below), `OS_AGENT_DIRS` on one that keeps the OS agent's memory on another disk, `HYPR_IGNORE_KEY_UNKNOWN` on one whose keyboard needs it, and on a server, `HEADLESS` and `CODEX_ONLY` (below).
- `computers/<name>/setup.sh` holds steps that no setting covers, such as a kernel module option or a package only that computer needs. The layer's own `setup.sh` does the same for every computer. Both run at the end of each `bootstrap.sh` run, with `AIBRAIN`, `PERSONAL`, `COMPUTER` and `BACKUP` set, so like the script, each step must change nothing on a second run. `personal.example/computers/README.md` has examples.

The script saves the computer's name in `~/.config/aibrain/computer` and asks only when that file is missing, as on a fresh install:
- **New or existing?** "Existing" is a computer set up again after a reinstall: pick it from the list of your computers, and it gets its settings back. "New" asks for a name (the hostname by default; lowercase letters, digits and dashes) and adds its folder. The computer's Tailscale name is a good choice.
- `AIBRAIN_COMPUTER=<name>` answers without asking, with an existing name or a new one.
- Without a terminal and without a name, the script uses the hostname, saves nothing, adds no folder, and warns, so a later run in a terminal still asks.

Two settings shape a computer that isn't a desktop:

- `HEADLESS=1`: the computer has no desktop. The script leaves out the Hyprland keys (the OS agent's hotkey and `HYPR_IGNORE_KEY_UNKNOWN`), Taildrop receiving, the bar widget and the Tailscale web app. On Ubuntu these are left out anyway, since they're Omarchy's; the setting records that the computer is a server.
- `CODEX_ONLY=1`: Codex is the only agent tool. The script doesn't install Claude Code, its managed settings, its hook checks, its login or its folder trust, and removes a Claude Code that mise installed and the managed settings file. Off Omarchy, it installs Codex through mise once; a version pinned later with `mise use -g codex@<version>` stays. The links for every tool stay, so other tools keep the instructions and skills.

A computer accepts the routes that other computers share with the tailnet, unless it shares a LAN itself (`TS_SHARE_LAN`). On a LAN that another computer shares, set `TS_ACCEPT_ROUTES=0`. Otherwise, on Linux, the shared route to that LAN wins over the computer's own, so its traffic to the LAN, replies included, goes into the tailnet, and computers on the LAN can't reach it, not even over SSH. The setting applies from the first join on.

When Tailscale isn't set up yet, the computer joins under its name. To get a reinstalled computer's old name back in Tailscale, remove the old machine in the admin console before that run.

When an agent fixes something on one computer, the fix goes in that computer's folder: as a setting if the engine has one, otherwise as a step in its `setup.sh`. A fix that would help other people belongs in this repo as a setting that's off by default, like `HYPR_IGNORE_KEY_UNKNOWN`.

## Privacy guard

This repo is public, so nothing personal may enter it, and a guard checks every change:

- `privacy/scan.py` flags email addresses, tokens and private keys, home folders with a user name, tailnet names, and private or Tailscale IP addresses, plus every entry in your layer's `privacy/denylist`. `privacy/allow` lists the few generic matches that are fine to publish, such as noreply addresses; it can't loosen the denylist. If the personal layer exists but its denylist is missing, every scan fails.
- Git hooks in `.githooks/`, which the script turns on in your checkout (`core.hooksPath`), run it on each commit (files, file names, identity, message) and each push (every commit, tag and file sent, which catches anything committed with `--no-verify`).
- `.github/workflows/privacy.yml` runs it on GitHub for every push, with the denylist from the repo's `AIBRAIN_DENYLIST` secret, which the script keeps in step with your layer. Its logs name the rule that matched, never the text.
- A Claude Code hook, `claude/hooks/privacy-guard.py`, refuses git commands that would skip the hooks in this repo.
- Commits here carry your GitHub login and its noreply address, not your own email, unless `config.sh` sets `PUBLIC_GIT_NAME` and `PUBLIC_GIT_EMAIL`. Edit from a checkout, not in GitHub's web editor: GitHub records a web edit under its own committer address, which the scan rejects, and taking the commit back out of the history means a force-push.

To check by hand: `python3 -I privacy/scan.py tree` for the files, `python3 -I privacy/scan.py history` for every commit.

## What's in the repo

| Path | What it is | Linked to |
|---|---|---|
| `bootstrap.sh` | The setup script | Nothing; run it |
| `skills/` | Skills, one folder each | `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, `~/.pi/agent/skills`, `~/.hermes/skills` (the folders Omarchy uses for its own skills) |
| `claude/` | Claude Code's own config | `~/.claude/settings.json`, `~/.claude/keybindings.json` |
| `claude/agents/` | Claude Code subagent definitions for every project: the contractors and the general employees (see [Subagents](#subagents)) | `~/.claude/agents`, one link per file |
| `claude/managed-settings.json` | Claude Code's default model and effort, Opus at medium | Copied to `/etc/claude-code/managed-settings.json` |
| `claude/hooks/` | Claude Code hooks: `session-state.py` (see [Long sessions](#long-sessions)), `agent-cache.py` (see [Subagents](#subagents)), `rm-guard.py` (see [Background sessions and rm](#background-sessions-and-rm)) and `privacy-guard.py` (see [Privacy guard](#privacy-guard)) | Run from the repo by `claude/settings.json` |
| `bin/` | Helper scripts | `~/.local/bin` |
| `privacy/`, `.githooks/`, `.github/workflows/` | The privacy guard | `.githooks/` through `core.hooksPath` |
| `personal.example/` | The template for your personal layer | Copied once, when you have none |
| `study/` | Research notes, one folder per topic | Nothing |
| `.claude/agents/employee-aibrain.md`, `agents/employee-aibrain/` | The aibrain setup employee: its definition and its kit (see `skills/employees/`) | Nothing; Claude Code reads project agents from the repo |
| `tests/` | Tests for the script and the hooks | Nothing |

Because these are links, editing a file in either place changes the same file. When a tool saves its own settings, the change shows in `git status` here. Commit it if every computer should get it, except model and effort picks (see [Model and effort](#model-and-effort)).

## Model and effort

Every new Claude Code session starts on Opus at medium effort. That default lives in `claude/managed-settings.json`, which the script copies to `/etc/claude-code/managed-settings.json`. Claude Code ranks managed settings above everything its pickers save.

To use another model or effort for a task, pick it with `/model` or `/effort` as usual. The pick applies to that session, and the next session starts on Opus at medium again. The pickers still write the pick into `claude/settings.json` (Claude Code doesn't let Enter be remapped to "this session only"), so it can show in `git status`. It's never a setup change: the script puts the committed values back instead of stashing them, and nothing needs committing.

To change the default itself, edit `claude/managed-settings.json` and run the script.

## Long sessions

Claude Code main sessions compact at about 150k tokens, but only at a natural break. Hooks in `claude/settings.json` (all in `claude/hooks/session-state.py`) do this:

- Compaction happens only between turns, after a wait for you or for an agent, and only while the session's state file is newer than its last tool call. Past 500k it's allowed anywhere; from 450k, every tool call asks the session to update its state file first.
- Every prompt you type, every answer you give to a question, every reply that ends a turn, and every subagent's full report is saved verbatim.
- In a session that runs subagents or holds over 100k tokens, a turn that used tools can't end until the state file (goal, decisions, next step, files to read first) is updated after the last tool call. If the session ignores that, compaction stays blocked.
- The agents and jobs still running at each stop are recorded.
- After a compaction, the prompts, the state file, the agent list and the most recent replies are put back into the context, so the summary isn't the only memory.
- If the hook fails, compaction waits. A manual `/compact` isn't held back.

The files are in `~/.local/state/aibrain/sessions/<session id>/`, readable by you only, because the prompt log keeps whatever you paste. A session's folder is deleted when it's older than Claude Code keeps its transcripts (`cleanupPeriodDays`, 30 days unless you set it). Every bootstrap run makes the folder private again and checks that the hook runs on that computer. A session that was already running when `settings.json` changed gets the hooks at once but keeps its old compaction window (about 967k on Fable and Opus) until it's restarted. A background job doesn't restart when you leave or `/exit` its view, because it runs in a long-lived Claude Code process; give it the new window with `/autocompact 150k`. That command also saves the window into `claude/settings.json` under `modelSettings`; the next bootstrap run puts it back, or discard it with `git checkout claude/settings.json`.

To change the limits: the soft cap is `autoCompactWindow` and the idle threshold is `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS` in `claude/settings.json`; the hard cap and the other thresholds are constants at the top of the hook. `tests/session-state-test.sh` checks the hook's decisions after a change. The design and its numbers are in `study/workspace/2026-10-subagent-design.md`.

## Subagents

The research, the cost numbers and every decision so far are in `study/workspace/2026-10-subagent-design.md`. What's in place:

- **Contractor or employee** is chosen by how the session will work with the agent, never by how long the work might take: agents estimate durations in human hours, often far off. A cache stays warm as long as an agent keeps making requests, so what matters is whether the agent will stop and be picked up again after a pause.
- **Contractors** work until they're done and report, with no kit and a 5-minute cache. There's one type per model, in `claude/agents/`: `contractor-haiku`, only for tiny jobs with nothing to decide, and `contractor-sonnet`, neither of which can spawn agents; then `contractor-opus` and `contractor-fable`, which hand wide reading to Haiku or Sonnet gatherers to keep their own context for judgment, and spawn anything else only when the brief allows. The session passes the effort on each spawn, so the Sonnet, Opus and Fable types do the work of the nine model-and-effort types this design started from. `skills/contractors/` tells a session which to pick, which type and effort suit a task, what a brief carries, and when to continue an agent or start a fresh one.
- **Employees** have a 1-hour cache, for work with pauses in it: a back-and-forth with the session, or a job they start and wait for. A waiting employee starts a background waiter and stops, and Claude Code wakes it when the job ends. The general ones are `employee-sonnet`, `employee-opus` and `employee-fable` in `claude/agents/`. A project can also have domain employees, with a definition in its `.claude/agents/employee-<domain>.md` and a kit in `agents/employee-<domain>/`: a charter, curated facts, a log of every episode, and a note per open thread. An instance lasts one task; the kit is what carries over. `skills/employees/` tells a session how to brief, continue or retire them. `employee-aibrain` in this repo is the example.
- **`claude/hooks/agent-cache.py`** keeps either kind from re-writing its cache by accident. A subagent on a 5-minute cache can't block for more than 240 seconds in one call, so it runs a longer command detached and checks on it. A message that would continue an agent whose cache has gone cold, or whose context is past 150k tokens, is held once with the facts: how long it has been idle, its cache lifetime, its context size. Sending again goes through.

## Background sessions and rm

Even in bypassPermissions mode, Claude Code asks before an `rm` whose target it can't check up front: a variable, a `$(...)`, a glob, an empty or root path, a relative path after `cd`, or an `rm` that another shell runs (`sh -c`, `ssh`, `eval`, `trap` and the like). In the terminal the request counts down for two minutes. In a background session it goes to your phone and waits until someone answers, and the agent waits with it. `claude/hooks/rm-guard.py` refuses those commands in background sessions before Claude Code can ask, and tells the agent how to rewrite them: give `rm` a literal path or a quoted `"${VAR:?}"` target, or put the commands in a script file and run it with `bash`. It also reads as a script a heredoc or here-string a shell reads (`bash -eo pipefail <<EOF`, `cat <<EOF | sh`), and what a `$(cat <<EOF)` or `<(echo ...)` prints for a shell to run; a `$(...)` that builds a shell's script any other way is refused when it mentions `rm`. A quoted string or heredoc no shell runs, such as a commit message or a grep pattern, is only text to it, apart from the `$(...)` in it that the shell runs, and text it can't follow (a quote or paren that never closes) is refused when it mentions `rm`. It's stricter than Claude Code's check, so now and then it refuses a command that would have run without a question; the agent rewrites it and carries on. `tests/rm-guard-test.sh` checks it after a change.

## What else the script sets up

- Passwordless sudo for your user, in `/etc/sudoers.d/zz-aibrain`.
- The 1Password CLI, from Omarchy's package repo, or on Ubuntu from 1Password's apt repo.
- Python, which the Claude Code hooks run on, a private `~/.local/state/aibrain/sessions` folder for them, and a check that the session-state hook runs (see [Long sessions](#long-sessions)).
- Claude Code and the GitHub CLI, through mise. A Codex-only computer gets no Claude Code, and off Omarchy it gets Codex through mise.
- The aiagent token in `~/.config/op/aiagent-token`, and a block in `~/.bashrc` that loads it in every shell, including the agents' shells.
- The GitHub CLI logged in with the token stored in the vault, and git using it for github.com.
- git's name and email from `config.sh`, and in this repo the privacy hooks and the public identity.
- On a full setup, every repo on your GitHub account that isn't archived or empty, cloned into `~/Projects/<name>`. A folder that's already there is left alone. Repos in `SKIP_REPOS` are skipped.
- The "ssh fleet key" from the vault as `~/.ssh/aibrain_fleet`, trusted for logins to this computer too, and your layer's SSH shortcuts.
- An SSH server that takes key logins only. ufw keeps it closed to the LAN, and your other computers reach it over Tailscale.
- The OS agent: Ctrl+Super+Shift+A opens Claude Code in bypass mode in the OS agent's folder: the first folder in `OS_AGENT_DIRS` that exists, otherwise `~/osagent`. The folder is the agent's memory for that computer, and a new one starts with a short `AGENTS.md`.
- Claude Code's trust for the OS agent folder and every repo in `~/Projects`, so it doesn't ask before the first session in each.
- Tailscale, set up the way Omarchy's own installer does it. The computer joins your tailnet with routes accepted, you can run `tailscale` without sudo, Taildrop files land in `~/Downloads`, the bar gets a Tailscale widget, and the launcher gets the admin console as a web app. A computer without a desktop gets the first two. On Ubuntu the package comes from Tailscale's apt repo. A computer with `TS_SHARE_LAN` set, in its `computers/<name>/config.sh`, shares that LAN with the tailnet instead of accepting routes, and one with `TS_ACCEPT_ROUTES=0` doesn't accept them either (see "Computers"). When it's first set, approve the route in the admin console: Machines, then the computer, then Edit route settings.
- The Claude Code login.

What it does with what's already there:

- **Files it replaces** are copied to `~/.local/state/aibrain/` first.
- **Edits to either repo that aren't committed** go into a git stash. Get them back with `git -C ~/Projects/aibrain stash pop` (or `aibrain-personal`). Claude Code's session worktrees in `.claude/worktrees/` aren't edits: the script lists that folder in each checkout's `.git/info/exclude`, so they're never stashed.
- **Local commits** stay. The script rebases them onto the latest `main` and reminds you to push them.
- **A folder that isn't a checkout of the right repo** at `~/Projects/aibrain` or `~/Projects/aibrain-personal` is moved to `~/.local/state/aibrain/` and cloned fresh.
- **A token that doesn't work**, saved or pasted, gets asked for again.

## Adding a tool

Put the tool's own config files in a folder named after it, then add lines to the table near the top of `bootstrap.sh`: its instructions file to `INSTRUCTION_FILES`, its skill folder to `SKILL_DIRS`, and its config files to `TOOL_FILES`. Run the script to link them.

## Adding a secret

API keys and other secrets go in the `aiagents` vault, never in a repo. To add one:

1. In 1Password on the web, open the vault and create an **API Credential** item. Name it after the service and its use, such as "DeepSeek Agent". Paste the secret into the credential field. If the key expires, fill in the expiry date too.
2. Tell an agent the item's name and what it's for. The agent connects it to whatever needs it.

Every agent on every computer can read the item right away, so there's nothing to copy between computers.

## If the aiagent token is lost or revoked

In 1Password on the web, go to Developer > Service Accounts and create a new service account with read and write access to the vault. Save its token where you keep the old one. Then run `~/Projects/aibrain/bootstrap.sh` on each computer. It notices the old token no longer works and asks for the new one.

If GitHub rejects the token, put a new GitHub token in the "GitHub Agent" item and run `~/Projects/aibrain/bootstrap.sh`.

## Changing the setup

Any change to the setup goes into `bootstrap.sh` in the same commit, so every computer ends up the same. `AGENTS.md` holds the full rules for agents. `tests/bootstrap-test.sh` tests a change in throwaway homes, `tests/session-state-test.sh` tests the session-state hook, `tests/agent-cache-test.sh` tests the agent-cache hook, and `tests/privacy-test.sh` tests the privacy guard.

## Unsupported keyboard reports

Some keyboards send KEY_UNKNOWN reports (XKB code 248), which can stick in Hyprland's pressed-key list and turn into NUL characters in apps such as ChatGPT when focus changes. With `HYPR_IGNORE_KEY_UNKNOWN=1` in the `config.sh` of the computer with that keyboard (`computers/<name>/config.sh`), the script adds a Hyprland binding that consumes these reports before they reach that list. Normal typing is unaffected. It doesn't clear a key that is already stuck.

## License

MIT, in `LICENSE`: use it freely, and keep the copyright notice. Skills from other projects keep their own notices, in `THIRD_PARTY_NOTICES.md`.
