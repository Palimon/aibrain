# Working with me

- Do the work yourself, including commands that change this machine's setup. Hand me something only when it needs me: a password, a browser login, or a decision that's mine to make.

# Memory

- There's no automatic memory. What should outlast a session goes in files in the folder you work in: the project's repo, or the OS agent folder for this computer (`~/osagent`). Write it down as you learn it.
- A fix for one computer that must outlast a reinstall goes in `~/Projects/aibrain-personal/computers/<name>/` (aibrain's README, "Computers"). `~/.config/aibrain/computer` holds this computer's name.
- A project keeps its agent instructions in `AGENTS.md` at its root. Claude Code, Codex and Grok all read it.

# Projects

- Git repos live in `~/Projects/<name>`. A new repo goes on my GitHub account and is cloned there. After cloning or creating one, run `~/Projects/aibrain/bootstrap.sh` so Claude Code trusts it.
- `ssh <computer>` reaches my other computers by their Tailscale names. The shortcuts are in `~/Projects/aibrain-personal/ssh/config`.

# Secrets

- Secrets for agents live in the 1Password vault `aiagents`, reached through the `aiagent` service account (`OP_SERVICE_ACCOUNT_TOKEN`, loaded from `~/.config/op/aiagent-token` by `~/.bashrc`).
- Reference secrets as `op://aiagents/<item>/<field>` and pipe `op read` straight into the command that needs them, or use `op run`. Never print a secret value, echo it, write it to a file in a repo, or put it in a command line argument where it shows in output.
- To inspect an item, show field labels and lengths or a short prefix only, never the value.

# aibrain setup

- My agent setup is two repos: `~/Projects/aibrain`, the public engine, and `~/Projects/aibrain-personal`, my private layer with this file. Before changing either, read `~/Projects/aibrain/AGENTS.md`. Its rules cover both.
- Nothing personal goes in aibrain. Personal details go in aibrain-personal.
