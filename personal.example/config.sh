# Your values for aibrain's bootstrap.sh, which sources this file on every run. Anything left out keeps
# the default shown. This file stays private: it's in your personal layer, never in the public repo.

# git's global name and email. Left alone when empty.
GIT_NAME=""
GIT_EMAIL=""

# The name and email on your commits to the public aibrain repo. Empty: your GitHub login and its
# noreply address (<id>+<login>@users.noreply.github.com), which keep your email out of its history.
#PUBLIC_GIT_NAME=""
#PUBLIC_GIT_EMAIL=""

# The 1Password vault the aiagent service account opens, and the item names bootstrap.sh reads there.
#OP_VAULT=aiagents
#GH_ITEM_NAME="GitHub Agent"
#SSH_KEY_ITEM_NAME="ssh fleet key"
#TS_KEY_ITEM="Tailscale auth key"

# A full setup clones every repo of this GitHub account into ~/Projects, except SKIP_REPOS.
# Empty: the account bootstrap.sh logs in as.
#GH_OWNER=""
#SKIP_REPOS=(old-repo)

# Subnet routers: a machine listed here shares its LAN with your tailnet. <Tailscale machine name>:<LAN>
#TS_ROUTERS=("my-desktop:192.0.2.0/24")

# The OS agent's folder (Ctrl+Super+Shift+A): the first of these that exists, else ~/osagent.
#OS_AGENT_DIRS=(/srv/osagent)

# 1: Hyprland ignores unsupported key reports (README, "Unsupported keyboard reports").
#HYPR_IGNORE_KEY_UNKNOWN=1

# A small repo of GH_OWNER's that tests/bootstrap-test.sh full clones.
#TEST_REPO=""

# Where the public repo comes from, if you use a fork.
#ENGINE_REPO=https://github.com/Palimon/aibrain.git
