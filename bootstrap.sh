#!/bin/bash
# aibrain bootstrap: brings any Omarchy machine to the same AI agent setup,
# whatever state it starts in. Re-running it changes nothing. It also runs on Ubuntu (24.04 is tested),
# for a computer without Omarchy, such as a headless server.
#
# Two repos make the setup. This one, at ~/Projects/aibrain, is public and holds nothing personal.
# Your personal layer, at ~/Projects/aibrain-personal, holds config.sh (the values below), your
# instructions for every agent, SSH shortcuts and the privacy denylist, and in computers/<name>/ what
# differs on one computer. Agent tools get their setup from both through symlinks, listed in the table
# below.
#
# Run it from ~/Projects/aibrain/bootstrap.sh, or before anything is cloned, from
# the clipboard: bash <(wl-paste). Either way, once the checkout matches
# origin/main it re-runs the checkout's copy, so a run always applies the current setup.
#
# Anyone can run it: a person in a terminal, or an agent with no terminal.
# Without a terminal it needs OP_SERVICE_ACCOUNT_TOKEN set (or a valid
# ~/.config/op/aiagent-token) and 1password-cli already installed.
#
# Every change to the aibrain setup goes in this script. See AGENTS.md.
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap
set -euo pipefail
script_path="$(readlink -f "$0" 2>/dev/null || true)"
cd "$HOME"   # mise reads config from the working directory, so start somewhere predictable

AIBRAIN="$HOME/Projects/aibrain"
PERSONAL="$HOME/Projects/aibrain-personal"
TOKEN_FILE="$HOME/.config/op/aiagent-token"
SETUP_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/aibrain/setup"   # light or full, chosen on the first run
OS_AGENT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/aibrain/os-agent-dir"   # read by bin/aibrain-agent
COMPUTER_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/aibrain/computer"   # this computer's name in the personal layer

# --- Settings. These are the defaults. The personal layer's config.sh sets your own for every computer,
# and computers/<name>/config.sh sets them for one computer, on top (personal.example lists them all).
defaults() {
  ENGINE_REPO=https://github.com/Palimon/aibrain.git   # where this repo comes from; a fork sets its own
  OP_VAULT=aiagents               # the 1Password vault the aiagent service account opens
  GH_ITEM_NAME="GitHub Agent"     # items in that vault
  SSH_KEY_ITEM_NAME="ssh fleet key"
  TS_KEY_ITEM="Tailscale auth key"
  GIT_NAME="" GIT_EMAIL=""        # git's global name and email; left alone when empty
  PUBLIC_GIT_NAME="" PUBLIC_GIT_EMAIL=""   # on commits to this public repo; empty: your GitHub login and noreply address
  GH_OWNER=""                     # whose repos a full setup clones; empty: the GitHub login
  SKIP_REPOS=()                   # repos a full setup doesn't clone
  # Usually set for one computer:
  TS_SHARE_LAN=""                 # the LAN this computer shares with the tailnet as a subnet router, e.g. 192.0.2.0/24
  OS_AGENT_DIRS=()                # the OS agent's folder: the first of these that exists, else ~/osagent
  HYPR_IGNORE_KEY_UNKNOWN=""      # 1: Hyprland ignores unsupported key reports (README, "Unsupported keyboard reports")
  HEADLESS=""                     # 1: no desktop: no Hyprland keys, Taildrop, bar widget or web app (README, "Computers")
  CODEX_ONLY=""                   # 1: Codex is the only agent tool: no Claude Code (README, "Computers")
}
load_config() { # the defaults, then config.sh, then this computer's config.sh
  defaults
  # shellcheck source=/dev/null
  if [[ -r "$PERSONAL/config.sh" ]]; then source "$PERSONAL/config.sh"; fi
  # shellcheck source=/dev/null
  if [[ -n "$COMPUTER" && -r "$PERSONAL/computers/$COMPUTER/config.sh" ]]; then source "$PERSONAL/computers/$COMPUTER/config.sh"; fi
  REPO="${AIBRAIN_REPO:-$ENGINE_REPO}"   # AIBRAIN_REPO: only to test unpushed changes
  GH_ITEM="op://$OP_VAULT/$GH_ITEM_NAME/credential"
  SSH_KEY_ITEM="op://$OP_VAULT/$SSH_KEY_ITEM_NAME"
}
COMPUTER="${AIBRAIN_COMPUTER:-$(cat "$COMPUTER_FILE" 2>/dev/null || true)}"   # settled once the personal layer is up to date
load_config

# --- What links where. Adding a tool means adding its paths here.
# Each tool's global instructions file, all linked to the personal layer's AGENTS.md
INSTRUCTION_FILES=(
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.codex/AGENTS.md"
  "$HOME/.grok/AGENTS.md"
)
# Every skill in skills/, here and in the personal layer, is linked into each of these: the folders
# Omarchy links its own skills into
SKILL_DIRS=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.pi/agent/skills" "$HOME/.hermes/skills")
for p in "$HOME"/.hermes/profiles/*/; do [[ -d "$p" ]] && SKILL_DIRS+=("${p%/}/skills"); done
# One tool's own config: <path in the repo>:<where the tool reads it>
TOOL_FILES=(
  "claude/settings.json:$HOME/.claude/settings.json"
  "claude/keybindings.json:$HOME/.claude/keybindings.json"
)
# Every Claude Code agent definition in claude/agents/, here and in the personal layer, is linked into
# ~/.claude/agents
# Every script in bin/, here and in the personal layer, is linked into ~/.local/bin

# Run from the checkout? Then remember this copy, to skip the re-run when an update leaves it unchanged
self_sum=""
[[ "$script_path" == "$AIBRAIN/bootstrap.sh" ]] && self_sum="$(sha256sum < "$script_path")"

MISE_SHIMS="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
export PATH="$MISE_SHIMS:$HOME/.local/bin:$PATH"
export AIBRAIN_BACKUP="${AIBRAIN_BACKUP:-${XDG_STATE_HOME:-$HOME/.local/state}/aibrain/backup-$(date +%Y%m%d-%H%M%S)}"
BACKUP="$AIBRAIN_BACKUP"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33maibrain: %s\033[0m\n' "$*" >&2; }
die() { printf '\033[31maibrain: %s\033[0m\n' "$*" >&2; exit 1; }
have_tty() { (: </dev/tty) 2>/dev/null; }
saved() { # saved <path>: copy a path under $HOME into this run's backup folder, then remove it
  local rel="${1#"$HOME"/}"
  mkdir -p "$BACKUP/$(dirname "$rel")"
  cp -a "$1" "$BACKUP/$rel" && rm -rf "$1"
}
link() { # link <target> <path>: make <path> a symlink to <target>, saving whatever was there
  [[ -L "$2" && "$(readlink "$2")" == "$1" ]] && return 0
  mkdir -p "$(dirname "$2")"
  if [[ -e "$2" || -L "$2" ]]; then saved "$2"; fi
  ln -s "$1" "$2"
}
# --- Which system this is: Omarchy, or Ubuntu. Steps that differ ask DISTRO, or use pkg_missing and pkg_add.
os_id="$( (. /etc/os-release && echo "$ID") 2>/dev/null || true)"
case "$os_id" in
  omarchy) DISTRO=omarchy ;;
  ubuntu) DISTRO=ubuntu UBUNTU_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")" ;;
  *) die "This setup runs on Omarchy or Ubuntu, not \"${os_id:-an unknown system}\"." ;;
esac
pkg_missing() { # pkg_missing <package>: true when the package isn't installed
  if [[ "$DISTRO" == omarchy ]]; then
    omarchy-pkg-missing "$1"
  else
    [[ "$(dpkg-query -W -f '${db:Status-Status}' "$1" 2>/dev/null)" != installed ]]
  fi
}
apt_source() { # apt_source <package>: on Ubuntu, the vendor's apt repo and signing key for a package Ubuntu doesn't carry
  local arch key url keyring list line raw
  arch="$(dpkg --print-architecture)"
  case "$1" in
    1password-cli) key=https://downloads.1password.com/linux/keys/1password.asc url="https://downloads.1password.com/linux/debian/$arch stable main" ;;
    mise) key=https://mise.jdx.dev/gpg-key.pub url="https://mise.jdx.dev/deb stable main" ;;
    tailscale) key="https://pkgs.tailscale.com/stable/ubuntu/$UBUNTU_CODENAME.noarmor.gpg" url="https://pkgs.tailscale.com/stable/ubuntu $UBUNTU_CODENAME main" ;;
    *) return 0 ;;
  esac
  keyring="/etc/apt/keyrings/aibrain-$1.gpg" list="/etc/apt/sources.list.d/aibrain-$1.list"
  line="deb [arch=$arch signed-by=$keyring] $url"
  if [[ ! -s "$keyring" ]]; then
    raw="$(mktemp)"
    curl -fsSL "$key" -o "$raw" || die "Couldn't download the signing key for $1 from $key."
    sudo install -d -m 0755 /etc/apt/keyrings
    if grep -q -- '-----BEGIN PGP' "$raw"; then gpg --dearmor < "$raw" | sudo tee "$keyring" >/dev/null; else sudo tee "$keyring" < "$raw" >/dev/null; fi
    sudo chmod 0644 "$keyring"; rm -f "$raw"
  fi
  [[ "$(cat "$list" 2>/dev/null)" == "$line" ]] || printf '%s\n' "$line" | sudo tee "$list" >/dev/null
}
pkg_add() { # pkg_add <package>...: install the packages that are missing, from the distro's repos or a vendor's
  local p missing=()
  for p in "$@"; do if pkg_missing "$p"; then missing+=("$p"); fi; done
  ((${#missing[@]})) || return 0
  say "Installing ${missing[*]}"
  have_tty || sudo -n true 2>/dev/null || die "${missing[*]} isn't installed, and installing it needs sudo. Run this once in a terminal."
  if [[ "$DISTRO" == omarchy ]]; then
    omarchy-pkg-add "${missing[@]}"
  else
    for p in "${missing[@]}"; do apt_source "$p"; done
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >/dev/null
  fi
}
desktop() { [[ "$DISTRO" == omarchy && "$HEADLESS" != 1 ]]; }   # Hyprland and Omarchy's desktop pieces are here
prune() { # prune <dir> <prefix>...: remove broken symlinks in <dir> that point under one of the prefixes
  local dir="$1" l t p; shift
  for l in "$dir"/*; do
    [[ -L "$l" && ! -e "$l" ]] || continue
    t="$(readlink "$l")"
    for p in "$@"; do if [[ "$t" == "$p"/* ]]; then rm "$l"; break; fi; done
  done
}

# --- Passwordless sudo for this user, so agents can change the system without asking. Setting it up
# asks for the password one last time.
SUDOERS=/etc/sudoers.d/zz-aibrain
SUDOERS_LINE="$USER ALL=(ALL) NOPASSWD: ALL"
if [[ "$(sudo -n cat "$SUDOERS" 2>/dev/null)" != "$SUDOERS_LINE" ]]; then
  if have_tty || sudo -n true 2>/dev/null; then
    say "Making sudo passwordless for $USER"
    sudoers_tmp="$(mktemp)"; printf '%s\n' "$SUDOERS_LINE" > "$sudoers_tmp"
    sudo visudo -cqf "$sudoers_tmp" || die "The sudoers line didn't pass visudo's check: $SUDOERS_LINE"
    sudo install -m 0440 -o root -g root "$sudoers_tmp" "$SUDOERS"
    rm -f "$sudoers_tmp"
  else
    warn "Passwordless sudo isn't set up, and that needs your password once. Run this once in a terminal."
  fi
fi

# --- Light or full. Light sets up the agent tools. Full also clones every repo on GitHub into ~/Projects.
# Asked once in a terminal and saved. Without a terminal and no saved answer it's light, unsaved, so a
# later run in a terminal still asks. AIBRAIN_SETUP=light|full sets it without asking.
setup="${AIBRAIN_SETUP:-}"
[[ -z "$setup" || "$setup" == light || "$setup" == full ]] || die "AIBRAIN_SETUP must be light or full, not \"$setup\"."
[[ -n "$setup" ]] || setup="$(cat "$SETUP_FILE" 2>/dev/null || true)"
if [[ "$setup" != light && "$setup" != full ]]; then
  setup=""
  if have_tty; then
    until [[ "$setup" == light || "$setup" == full ]]; do
      read -rp "Light setup (agent tools only) or full (also clone every repo on GitHub into ~/Projects)? [light/full]: " setup </dev/tty
    done
  fi
fi
if [[ -n "$setup" ]]; then
  [[ "$(cat "$SETUP_FILE" 2>/dev/null)" == "$setup" ]] || { mkdir -p "$(dirname "$SETUP_FILE")"; printf '%s\n' "$setup" > "$SETUP_FILE"; }
  export AIBRAIN_SETUP="$setup"   # so the checkout's copy, run below, doesn't ask again
else
  setup=light
fi

# --- Packages: the 1Password CLI, and Python for the privacy guard and Claude Code's hooks. Omarchy has
# them in its package repo. Ubuntu also needs what Omarchy comes with, mise among it, and 1Password's
# and mise's own apt repos.
if [[ "$DISTRO" == omarchy ]]; then
  pkg_add 1password-cli python
else
  pkg_add ca-certificates curl gpg git jq python3
  pkg_add 1password-cli mise
fi

# --- gh through mise, the same way Omarchy's launchers in ~/.local/bin do it. Claude Code comes later,
# once this computer's settings are known.
say "Installing the GitHub CLI"
MISE_MINIMUM_RELEASE_AGE=0 mise use -g --quiet gh

# --- aiagent service account token, for the $OP_VAULT vault
token_ok() { [[ -n "$1" ]] && OP_SERVICE_ACCOUNT_TOKEN="$1" op vault list --format json 2>/dev/null | jq -e --arg v "$OP_VAULT" 'any(.[]; .name == $v)' >/dev/null; }
save_token() { (umask 077; printf '%s' "$1" > "$TOKEN_FILE"); }
# op refuses to run while its config folder is readable by others
mkdir -p "$(dirname "$TOKEN_FILE")" && chmod 700 "$(dirname "$TOKEN_FILE")"
token=""
[[ -s "$TOKEN_FILE" ]] && token="$(< "$TOKEN_FILE")"
if ! token_ok "$token"; then
  if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]] && token_ok "$OP_SERVICE_ACCOUNT_TOKEN"; then
    token="$OP_SERVICE_ACCOUNT_TOKEN"
  elif have_tty; then
    [[ -n "$token" ]] && warn "The saved aiagent token doesn't open the $OP_VAULT vault. Paste a new one."
    for _ in 1 2 3; do
      read -rsp "Paste the aiagent token from 1Password, then press Enter (input hidden): " token </dev/tty; echo >/dev/tty
      token_ok "$token" && break
      warn "That token doesn't open the $OP_VAULT vault. Try again."
      token=""
    done
    [[ -n "$token" ]] || die "No working aiagent token."
  else
    die "No working aiagent token. Set OP_SERVICE_ACCOUNT_TOKEN or run this in a terminal."
  fi
  save_token "$token"
fi
chmod 600 "$TOKEN_FILE"
export OP_SERVICE_ACCOUNT_TOKEN="$token"; unset token

# --- GitHub: gh logged in with the token from 1Password, git pulling and pushing through gh.
# If the item can't be read, the current login stays, so this run can still update the checkout and
# hand over to a newer copy of the script.
if gh_token="$(op read "$GH_ITEM" 2>/dev/null)" && [[ -n "$gh_token" ]]; then
  if [[ "$(gh auth token -h github.com 2>/dev/null || true)" != "$gh_token" ]]; then
    say "Logging the GitHub CLI in"
    printf '%s' "$gh_token" | gh auth login -h github.com -p https --with-token
  fi
else
  warn "Couldn't read the GitHub token from the \"$GH_ITEM_NAME\" item in 1Password. Keeping the current GitHub login."
fi
unset gh_token
# GitHub sends the token's expiry date with every API reply. Warn two weeks ahead.
if gh_reply="$(gh api -i user 2>/dev/null)"; then
  gh_expiry="$(printf '%s\n' "$gh_reply" | tr -d '\r' | awk -F': ' 'tolower($1) == "github-authentication-token-expiration" { print $2; exit }')"
  if [[ -n "$gh_expiry" ]] && gh_days=$(( ($(date -d "$gh_expiry" +%s) - $(date +%s)) / 86400 )) && (( gh_days < 14 )); then
    warn "The GitHub token expires in $gh_days day(s), on ${gh_expiry%% *}. Put a new one in the \"$GH_ITEM_NAME\" item in 1Password."
  fi
else
  warn "GitHub didn't accept the current login. If its token has expired, put a new one in the \"$GH_ITEM_NAME\" item in 1Password."
fi
unset gh_reply
gh config set -h github.com git_protocol https
# setup-git would write gh's versioned install path; point at the mise shim so gh upgrades don't break git
for host in github.com gist.github.com; do
  git config --global --replace-all "credential.https://$host.helper" ''
  git config --global --add "credential.https://$host.helper" "!$MISE_SHIMS/gh auth git-credential"
done
# --- ~/Projects/aibrain is a checkout of origin/main
fresh_clone() { # fresh_clone <dir> <repo>: clone <repo> into <dir>, saving whatever was there
  if [[ -e "$1" ]]; then
    warn "~/${1#"$HOME"/} isn't a checkout of $2. Moving it to $BACKUP and cloning fresh."
    saved "$1"
  fi
  mkdir -p "$(dirname "$1")"
  git clone -q "$2" "$1"
}
reset_picks() { # put back the committed model and effort in claude/settings.json (README, "Model and effort")
  local g=(git -C "$AIBRAIN") rc
  [[ -f "$AIBRAIN/claude/settings.json" ]] && "${g[@]}" cat-file -e HEAD:claude/settings.json 2>/dev/null || return 0
  "${g[@]}" show HEAD:claude/settings.json | python3 -I -c '
import json, sys
path = sys.argv[1]
head, cur = json.load(sys.stdin), json.load(open(path))
for key in ("model", "modelSettings"):
    if key in head: cur[key] = head[key]
    else: cur.pop(key, None)
if cur == head: sys.exit(3)  # nothing else differs: restore the committed file byte for byte
with open(path, "w") as f: json.dump(cur, f, indent=2); f.write("\n")
' "$AIBRAIN/claude/settings.json" || { rc=$?; [[ $rc == 3 ]] && "${g[@]}" checkout -q -- claude/settings.json || true; }
}
sync_checkout() { # sync_checkout <dir> <repo>: make <dir> a checkout of <repo>'s main, keeping local work
  local dir="$1" url="$2" name="~/${1#"$HOME"/}" ahead
  local g=(git -C "$dir")
  if [[ ! -d "$dir/.git" ]]; then fresh_clone "$dir" "$url"; return; fi
  "${g[@]}" remote get-url origin >/dev/null 2>&1 || "${g[@]}" remote add origin "$url"
  "${g[@]}" remote set-url origin "$url"
  "${g[@]}" fetch -q origin
  if ! "${g[@]}" merge-base HEAD origin/main >/dev/null 2>&1; then fresh_clone "$dir" "$url"; return; fi
  # Model and effort picks that Claude Code's /model and /effort pickers saved into settings.json are
  # per-task choices, not setup changes: they're put back, so they're never stashed or committed.
  [[ "$dir" != "$AIBRAIN" ]] || reset_picks
  if [[ -n "$("${g[@]}" status --porcelain)" ]]; then
    "${g[@]}" stash push -q -u -m "aibrain bootstrap $(date -Is)"
    warn "Uncommitted changes in $name are stashed. Get them back with: git -C $name stash pop"
  fi
  [[ "$("${g[@]}" symbolic-ref -q --short HEAD || true)" == main ]] || "${g[@]}" switch -q main 2>/dev/null || "${g[@]}" switch -q -c main --track origin/main
  "${g[@]}" branch -q --set-upstream-to=origin/main main
  if ! "${g[@]}" merge -q --ff-only origin/main 2>/dev/null; then
    "${g[@]}" rebase -q origin/main || { "${g[@]}" rebase --abort; die "Local commits in $name conflict with origin/main. Resolve them by hand, then re-run."; }
  fi
  ahead="$("${g[@]}" rev-list --count origin/main..HEAD)"
  (( ahead == 0 )) || warn "$name has $ahead commit(s) that aren't on GitHub. Push them so other machines get them: git -C $name push"
}
# (AIBRAIN_RERUN, not the AIBRAIN_REEXEC older copies set, so an older copy handing over still gets this step)
if [[ -z "${AIBRAIN_RERUN:-}" ]]; then
  say "Updating ~/Projects/aibrain"
  sync_checkout "$AIBRAIN" "$REPO"
  # Re-run the checkout's copy, unless it's the one already running, so the rest of the setup is always the current version
  if [[ "$self_sum" != "$(sha256sum < "$AIBRAIN/bootstrap.sh")" ]]; then
    exec env AIBRAIN_RERUN=1 bash "$AIBRAIN/bootstrap.sh"
  fi
fi

# --- ~/Projects/aibrain-personal, your personal layer. Its repo is AIBRAIN_PERSONAL_REPO when that's set
# (a URL or a path; "none" for a folder without a repo), else the checkout's own origin, else
# <your GitHub login>/aibrain-personal when that exists. With no repo, a missing folder is made from
# personal.example, to fill in and keep in a private repo of your own.
say "Updating ~/Projects/aibrain-personal"
personal_repo="${AIBRAIN_PERSONAL_REPO:-}"
if [[ -z "$personal_repo" ]]; then
  personal_repo="$(git -C "$PERSONAL" remote get-url origin 2>/dev/null || true)"
  # A checkout that points at this public repo isn't a personal layer (an old clone renamed by hand)
  [[ "$personal_repo" != "$REPO" && "$personal_repo" != "${ENGINE_REPO%.git}" ]] || personal_repo=""
  if [[ -z "$personal_repo" && ! -e "$PERSONAL/config.sh" ]] && gh_login="$(gh api user --jq .login 2>/dev/null)" &&
     gh repo view "$gh_login/aibrain-personal" >/dev/null 2>&1; then
    personal_repo="https://github.com/$gh_login/aibrain-personal.git"
  fi
fi
[[ "$personal_repo" != none ]] || personal_repo=""
if [[ -n "$personal_repo" ]]; then
  sync_checkout "$PERSONAL" "$personal_repo"
elif [[ ! -e "$PERSONAL" ]]; then
  cp -r "$AIBRAIN/personal.example" "$PERSONAL"
  warn "Made a personal layer in ~/Projects/aibrain-personal from personal.example. Fill in its config.sh, AGENTS.md and privacy/denylist, keep it in a private repo of your own, and run this again."
fi

load_config

# --- git: your name and email, and for this public repo the privacy guard's hooks (privacy/scan.py,
# through .githooks/) and an identity that keeps your email address out of its history: your GitHub
# login and noreply address unless config.sh says otherwise.
[[ -z "$GIT_NAME" ]] || git config --global user.name "$GIT_NAME"
[[ -z "$GIT_EMAIL" ]] || git config --global user.email "$GIT_EMAIL"
git -C "$AIBRAIN" config core.hooksPath .githooks
if [[ -z "$PUBLIC_GIT_NAME" || -z "$PUBLIC_GIT_EMAIL" ]] && gh_who="$(gh api user --jq '"\(.login) \(.id)"' 2>/dev/null)"; then
  PUBLIC_GIT_NAME="${PUBLIC_GIT_NAME:-${gh_who% *}}"
  PUBLIC_GIT_EMAIL="${PUBLIC_GIT_EMAIL:-${gh_who#* }+${gh_who% *}@users.noreply.github.com}"
fi
[[ -z "$PUBLIC_GIT_NAME" ]] || git -C "$AIBRAIN" config user.name "$PUBLIC_GIT_NAME"
[[ -z "$PUBLIC_GIT_EMAIL" ]] || git -C "$AIBRAIN" config user.email "$PUBLIC_GIT_EMAIL"
# The guard must run here, and what's committed must pass it
if ! (cd "$AIBRAIN" && python3 -I privacy/scan.py tree HEAD >/dev/null 2>&1); then
  warn "The privacy scan of ~/Projects/aibrain fails: personal details are committed there, or the scan can't run (for example, the personal layer has no privacy/denylist). Check: cd ~/Projects/aibrain && python3 -I privacy/scan.py tree"
fi

# --- This computer's name. Every computer has a folder in the personal layer, computers/<name>/, where
# config.sh sets settings for it alone and setup.sh runs at the end. The name is AIBRAIN_COMPUTER when
# set, else the one an earlier run saved in ~/.config/aibrain/computer. With neither, as on a fresh
# install, a run in a terminal asks whether this is a new computer or one set up again after a
# reinstall: an existing one is picked from a list, and a new one gets a name, the hostname by default.
# A name without a folder gets one, committed to the personal repo and pushed, so every computer and
# every reinstall knows it. Without a terminal the name is the hostname, unsaved and without a folder,
# so a later run in a terminal still asks.
computer_about() { # computer_about <name>: what the first line of its config.sh says about it
  local line; line="$(head -n 1 "$PERSONAL/computers/$1/config.sh" 2>/dev/null || true)"
  if [[ "$line" == "# $1: "* ]]; then echo "${line#"# $1: "}"; fi
}
host="$(uname -n)"; host="${host%%.*}"; host="${host,,}"; host="${host//[^a-z0-9-]/-}"
COMPUTER="${AIBRAIN_COMPUTER:-$(cat "$COMPUTER_FILE" 2>/dev/null || true)}" save_computer=1
if [[ -z "$COMPUTER" ]] && have_tty; then
  computers=(); for d in "$PERSONAL"/computers/*/; do [[ -d "$d" ]] && computers+=("$(basename "$d")"); done
  kind=new
  while ((${#computers[@]})); do
    read -rp "Is this a brand new computer, or one you're setting up again after a reinstall? [new/existing]: " kind </dev/tty
    [[ "$kind" != new && "$kind" != existing ]] || break
  done
  if [[ "$kind" == existing ]]; then
    echo "Your computers:" >/dev/tty
    for i in "${!computers[@]}"; do
      about="$(computer_about "${computers[i]}")"
      printf '  %d) %s%s\n' "$((i + 1))" "${computers[i]}" "${about:+  ($about)}" >/dev/tty
    done
    while :; do
      read -rp "Which one is this? [1-${#computers[@]}]: " i </dev/tty
      [[ ! "$i" =~ ^[0-9]+$ ]] || ((10#$i < 1 || 10#$i > ${#computers[@]})) || break
    done
    COMPUTER="${computers[10#$i - 1]}"
  else
    while :; do
      read -rp "A name for it, in lowercase letters, digits and dashes [$host]: " COMPUTER </dev/tty
      COMPUTER="${COMPUTER:-$host}"
      if [[ ! "$COMPUTER" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        echo "Use lowercase letters, digits and dashes." >/dev/tty
      elif [[ -d "$PERSONAL/computers/$COMPUTER" ]]; then
        echo "Another computer is already called $COMPUTER." >/dev/tty
      else
        break
      fi
    done
  fi
elif [[ -z "$COMPUTER" ]]; then
  COMPUTER="$host" save_computer=""
  warn "This computer has no name in the personal layer yet, so it gets no settings of its own. Run this once in a terminal, or with AIBRAIN_COMPUTER=<name>."
fi
[[ "$COMPUTER" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "A computer name is lowercase letters, digits and dashes, not \"$COMPUTER\"."
if [[ -n "$save_computer" && ! -d "$PERSONAL/computers/$COMPUTER" ]]; then
  say "Adding $COMPUTER to your computers in ~/Projects/aibrain-personal"
  about="$(hostnamectl --json=short 2>/dev/null |
    jq -r '[.HardwareVendor, .HardwareModel, .Chassis] | map(select(. != null and . != "")) | join(" ")' 2>/dev/null || true)"
  mkdir -p "$PERSONAL/computers/$COMPUTER"
  printf '%s\n' "# $COMPUTER: ${about:-a computer}, added $(date +%F)" \
    "# Settings for this computer alone, read after ../../config.sh. Steps of its own go in setup.sh here." \
    '# See the aibrain README, "Computers".' > "$PERSONAL/computers/$COMPUTER/config.sh"
  if [[ -e "$PERSONAL/.git" ]]; then
    git -C "$PERSONAL" add -- "computers/$COMPUTER" &&
      git -C "$PERSONAL" commit -q -m "computers/$COMPUTER: a new computer" -- "computers/$COMPUTER" &&
      git -C "$PERSONAL" push -q ||
      warn "Couldn't commit and push computers/$COMPUTER in ~/Projects/aibrain-personal. Do that there by hand, so a reinstall can find this computer."
  fi
fi
if [[ -n "$save_computer" && "$(cat "$COMPUTER_FILE" 2>/dev/null)" != "$COMPUTER" ]]; then
  mkdir -p "$(dirname "$COMPUTER_FILE")" && printf '%s\n' "$COMPUTER" > "$COMPUTER_FILE"
fi
load_config

# --- Claude Code through mise, like gh, unless this computer is Codex-only (CODEX_ONLY). Then a Claude
# Code from mise is removed, along with its managed settings below.
if [[ "$CODEX_ONLY" != 1 ]]; then
  say "Installing Claude Code"
  MISE_MINIMUM_RELEASE_AGE=0 mise use -g --quiet claude
  # Claude Code's first start migrates settings.json (it turns "opus" into "opus[1m]") and records that in
  # ~/.claude.json. Let that happen now, before settings.json links to the repo, so it stays as committed.
  claude auth status >/dev/null 2>&1 || true
elif mise ls --installed claude 2>/dev/null | grep -q .; then
  say "Removing Claude Code, since this computer is Codex-only"
  mise unuse -g --quiet claude 2>/dev/null || true   # its line in mise's config; this leaves the install
  mise uninstall --quiet --all claude && mise reshim
fi
# Codex: Omarchy installs it the first time it's started. Elsewhere it comes through mise, once; a version
# pinned later (mise use -g codex@<version>) is kept.
if [[ "$DISTRO" != omarchy ]] && ! mise which codex >/dev/null 2>&1; then
  say "Installing Codex"
  MISE_MINIMUM_RELEASE_AGE=0 mise use -g --quiet codex
fi

# --- Links from the agent tools into the repos. A skill, agent or script in the personal layer wins over
# one here with the same name.
say "Linking agent tools to ~/Projects/aibrain and ~/Projects/aibrain-personal"
instructions="$PERSONAL/AGENTS.md"
[[ -e "$instructions" ]] || instructions="$AIBRAIN/personal.example/AGENTS.md"
for f in "${INSTRUCTION_FILES[@]}"; do link "$instructions" "$f"; done
declare -A skills=() agents=() scripts=()
for root in "$AIBRAIN" "$PERSONAL"; do
  for s in "$root"/skills/*/; do [[ -d "$s" ]] && s="${s%/}" && skills[$(basename "$s")]="$s"; done
  for f in "$root"/claude/agents/*.md; do [[ -e "$f" ]] && agents[$(basename "$f")]="$f"; done
  for f in "$root"/bin/*; do [[ -e "$f" ]] && scripts[$(basename "$f")]="$f"; done
done
for d in "${SKILL_DIRS[@]}"; do
  mkdir -p "$d"
  for n in "${!skills[@]}"; do link "${skills[$n]}" "$d/$n"; done
  prune "$d" "$AIBRAIN/skills" "$PERSONAL/skills"
done
for entry in "${TOOL_FILES[@]}"; do link "$AIBRAIN/${entry%%:*}" "${entry#*:}"; done
mkdir -p "$HOME/.claude/agents"
for n in "${!agents[@]}"; do link "${agents[$n]}" "$HOME/.claude/agents/$n"; done
prune "$HOME/.claude/agents" "$AIBRAIN/claude/agents" "$PERSONAL/claude/agents"
mkdir -p "$HOME/.local/bin"
for n in "${!scripts[@]}"; do link "${scripts[$n]}" "$HOME/.local/bin/$n"; done
prune "$HOME/.local/bin" "$AIBRAIN/bin" "$PERSONAL/bin" "$HOME/.claude/bin"

# --- Claude Code's default model and effort, Opus at medium, in managed settings: the one settings file
# its /model and /effort pickers never write to and that outranks what they save. A pick still applies
# to its own session (README, "Model and effort").
MANAGED_SETTINGS=/etc/claude-code/managed-settings.json
if [[ "$CODEX_ONLY" == 1 ]]; then
  if [[ -e "$MANAGED_SETTINGS" ]]; then
    have_tty || sudo -n true 2>/dev/null || die "Removing $MANAGED_SETTINGS needs sudo. Run this once in a terminal."
    sudo rm -f "$MANAGED_SETTINGS"
  fi
elif ! cmp -s "$AIBRAIN/claude/managed-settings.json" "$MANAGED_SETTINGS"; then
  say "Setting Claude Code's default model and effort"
  have_tty || sudo -n true 2>/dev/null || die "Installing $MANAGED_SETTINGS needs sudo. Run this once in a terminal."
  sudo install -D -m 0644 "$AIBRAIN/claude/managed-settings.json" "$MANAGED_SETTINGS"
fi

# --- Claude Code's session-state hooks (claude/hooks/session-state.py, wired in claude/settings.json;
# see the README's "Long sessions"). Their folder holds prompt logs, so it's private to this user,
# including files older versions wrote. Then a dry run proves the hook works on this machine.
if [[ "$CODEX_ONLY" != 1 ]]; then
  SESSION_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/aibrain/sessions"
  mkdir -p "$SESSION_STATE"
  chmod -R go-rwx "$SESSION_STATE"
  hook_check="$(mktemp -d)"
  if ! printf '{"session_id":"bootstrap-check"}' |
       AIBRAIN_SESSION_STATE="$hook_check" python3 -I "$AIBRAIN/claude/hooks/session-state.py" Stop >/dev/null ||
     [[ ! -e "$hook_check/bootstrap-check/idle" ]]; then
    warn "Claude Code's session-state hook doesn't run here, so long sessions compact without its guard. Check: python3 -I $AIBRAIN/claude/hooks/session-state.py"
  fi
  [[ -n "$hook_check" && -d "$hook_check" ]] && rm -rf -- "$hook_check"
  # The agent-cache hook (claude/hooks/agent-cache.py, README "Subagents") allows any call it can't
  # judge, so a dry run only proves that it starts.
  if ! printf '{"tool_name":"Bash","tool_input":{}}' | python3 -I "$AIBRAIN/claude/hooks/agent-cache.py" >/dev/null; then
    warn "Claude Code's agent-cache hook doesn't run here, so subagents can re-write their cache by accident. Check: python3 -I $AIBRAIN/claude/hooks/agent-cache.py"
  fi
fi

# --- ~/.bashrc loads the aiagent token in every shell. The block must sit above
# .bashrc's interactive-shell check, because agents' shells are non-interactive.
say "Updating ~/.bashrc"
touch "$HOME/.bashrc"
block="# >>> aibrain >>>
# 1Password service account for AI agents (vault: $OP_VAULT). Managed by ~/Projects/aibrain/bootstrap.sh."'
[[ -r ~/.config/op/aiagent-token ]] && export OP_SERVICE_ACCOUNT_TOKEN="$(< ~/.config/op/aiagent-token)"'
# Omarchy puts mise's tools and ~/.local/bin on the PATH itself; elsewhere the block does, for agents' shells too
[[ "$DISTRO" == omarchy ]] || block+='
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"'
block+='
# <<< aibrain <<<'
# Take out the block and the lines older bootstraps wrote, each with the blank line before it, then put the block back after env-bootstrap
new="$(awk '
  /^# >>> aibrain >>>$/ { held = 0; skip = 1; next }
  skip { if ($0 ~ /^# <<< aibrain <<<$/) skip = 0; next }
  /aiagent-token|^# 1Password service account for AI agents/ { held = 0; next }
  /^$/ { if (held) print ""; held = 1; next }
  { if (held) print ""; held = 0; print }
  END { if (held) print "" }
' "$HOME/.bashrc" | awk -v block="$block" '
  { line[NR] = $0 }
  END {
    at = 0
    for (i = 1; i <= NR; i++) if (line[i] ~ /env-bootstrap$/) { at = i; break }
    if (at == 0) print block
    for (i = 1; i <= NR; i++) { print line[i]; if (i == at) { print ""; print block } }
  }
')"
if [[ "$new" != "$(< "$HOME/.bashrc")" ]]; then
  mkdir -p "$BACKUP" && cp -L "$HOME/.bashrc" "$BACKUP/.bashrc"
  printf '%s\n' "$new" > "$HOME/.bashrc"   # in place, so a .bashrc that's a symlink stays one
fi

# --- Full setup: every repo on the GitHub account, cloned into ~/Projects/<name>. A folder that's already
# there is left alone, since it may hold work in progress. Archived and empty repos are skipped.
# (AIBRAIN_REPOS_ONLY limits this to the named repos. The tests use it to clone one small repo.)
if [[ "$setup" == full ]]; then
  [[ -n "$GH_OWNER" ]] || GH_OWNER="$(gh api user --jq .login 2>/dev/null || true)"
  if [[ -z "$GH_OWNER" ]] || ! repos="$(gh repo list "$GH_OWNER" --limit 1000 --no-archived --json name,isEmpty --jq '.[] | select(.isEmpty | not) | .name')"; then
    warn "Couldn't list the repos on GitHub, so none were cloned."
  else
    for r in $repos; do
      [[ " ${SKIP_REPOS[*]} " != *" $r "* && ! -e "$HOME/Projects/$r" ]] || continue
      [[ -z "${AIBRAIN_REPOS_ONLY:-}" || " $AIBRAIN_REPOS_ONLY " == *" $r "* ]] || continue
      say "Cloning $r into ~/Projects"
      git clone -q "https://github.com/$GH_OWNER/$r.git" "$HOME/Projects/$r" || warn "Couldn't clone $r."
    done
  fi
fi

# --- SSH. The fleet key from 1Password is this computer's key for your servers and your other computers.
# ~/.ssh/config starts with an Include of the personal layer's ssh/config when it has one. ssh keeps the
# first value it finds for each setting, so those shortcuts win over anything else in the file.
SSH_KEY="$HOME/.ssh/aibrain_fleet"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if ssh_key="$(op read "$SSH_KEY_ITEM/private key?ssh-format=openssh" 2>/dev/null)" && [[ -n "$ssh_key" ]] &&
   ssh_pub="$(op read "$SSH_KEY_ITEM/public key" 2>/dev/null)"; then
  [[ "$(cat "$SSH_KEY" 2>/dev/null)" == "$ssh_key" ]] || (umask 077; printf '%s\n' "$ssh_key" > "$SSH_KEY")
  chmod 600 "$SSH_KEY"
  [[ "$(cat "$SSH_KEY.pub" 2>/dev/null)" == "$ssh_pub ssh fleet key" ]] || printf '%s ssh fleet key\n' "$ssh_pub" > "$SSH_KEY.pub"
  # Your other computers log in here with the same key
  touch "$HOME/.ssh/authorized_keys" && chmod 600 "$HOME/.ssh/authorized_keys"
  grep -qF "$ssh_pub" "$HOME/.ssh/authorized_keys" || printf '%s ssh fleet key\n' "$ssh_pub" >> "$HOME/.ssh/authorized_keys"
else
  warn "Couldn't read the \"$SSH_KEY_ITEM_NAME\" item from 1Password, so the fleet key isn't installed."
fi
unset ssh_key
ssh_include=""
[[ ! -e "$PERSONAL/ssh/config" ]] || ssh_include="Include ~/Projects/aibrain-personal/ssh/config"
touch "$HOME/.ssh/config" && chmod 600 "$HOME/.ssh/config"
# Every Include this script ever wrote comes out, then the current one goes first
ssh_rest="$(grep -vxE 'Include ~/Projects/aibrain(-personal)?/ssh/config' "$HOME/.ssh/config" | sed '/./,$!d' || true)"
ssh_new="$(printf '%s%s%s' "$ssh_include" "${ssh_include:+${ssh_rest:+$'\n\n'}}" "$ssh_rest")"
if [[ "$ssh_new" != "$(< "$HOME/.ssh/config")" ]]; then
  [[ ! -s "$HOME/.ssh/config" ]] || { mkdir -p "$BACKUP/.ssh" && cp "$HOME/.ssh/config" "$BACKUP/.ssh/config"; }
  printf '%s\n' "$ssh_new" > "$HOME/.ssh/config"
fi
# The SSH server takes key logins only. On Omarchy ufw blocks it from the LAN, and Tailscale lets it in from your tailnet.
SSHD_CONF=/etc/ssh/sshd_config.d/50-aibrain.conf
sshd_conf='# Managed by ~/Projects/aibrain/bootstrap.sh: key logins only, no root.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no'
# Ubuntu calls the server ssh.service, and may start it from ssh.socket, its default.
if [[ "$DISTRO" == omarchy ]]; then SSH_UNITS=(sshd.service); else SSH_UNITS=(ssh.service ssh.socket); fi
ssh_running() { local u; for u in "${SSH_UNITS[@]}"; do systemctl is-enabled --quiet "$u" && systemctl is-active --quiet "$u" && return 0; done; return 1; }
if [[ "$DISTRO" == ubuntu ]] && pkg_missing openssh-server; then pkg_add openssh-server; fi
if [[ "$(cat "$SSHD_CONF" 2>/dev/null)" != "$sshd_conf" ]] || ! ssh_running; then
  if ! have_tty && ! sudo -n true 2>/dev/null; then
    warn "The SSH server isn't set up, and that needs sudo. Run this once in a terminal."
  else
    say "Setting up the SSH server"
    if [[ "$(cat "$SSHD_CONF" 2>/dev/null)" != "$sshd_conf" ]]; then
      printf '%s\n' "$sshd_conf" | sudo tee "$SSHD_CONF" >/dev/null
      sudo ssh-keygen -A >/dev/null   # host keys, which Arch otherwise makes only when sshd first starts
      [[ "$DISTRO" != ubuntu ]] || sudo install -d -m 0755 /run/sshd   # sshd -t needs it; Ubuntu makes it only for a running server
      sudo sshd -t || die "sshd rejected its config. Check $SSHD_CONF."
      ! systemctl is-active --quiet "${SSH_UNITS[0]}" || sudo systemctl reload "${SSH_UNITS[0]}"
    fi
    ssh_running || sudo systemctl enable --now "${SSH_UNITS[0]}"
  fi
fi

# --- The OS agent: Ctrl+Super+Shift+A opens Claude Code in bypass mode in the OS agent's folder, which holds
# its memory for this computer (bin/aibrain-agent). A new folder gets a starting AGENTS.md; after that the
# file is the agent's own.
os_dir="$HOME/osagent"
for d in "${OS_AGENT_DIRS[@]}"; do if [[ -d "$d" ]]; then os_dir="$d"; break; fi; done
mkdir -p "$os_dir" "$(dirname "$OS_AGENT_FILE")"
[[ "$(cat "$OS_AGENT_FILE" 2>/dev/null)" == "$os_dir" ]] || printf '%s\n' "$os_dir" > "$OS_AGENT_FILE"
[[ -e "$os_dir/AGENTS.md" ]] || cat > "$os_dir/AGENTS.md" <<'EOF'
# OS agent

This folder is the memory of the agent that looks after this computer: its setup, hardware, problems and open work. Keep what you learn here as files, one topic per `.md`, and keep this file pointing to them. Open work goes in `NEXT-STEPS.md`.

A fix that must outlast a reinstall goes in the personal layer, in `computers/<name>/`, as aibrain's README describes under "Computers". `~/.config/aibrain/computer` holds this computer's name; without that file, the name is the hostname.
EOF
HYPR_BINDINGS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"
if desktop; then
  hypr_block='-- >>> aibrain >>>
-- Ctrl+Super+Shift+A: Claude Code in bypass mode in the OS agent folder. Managed by ~/Projects/aibrain/bootstrap.sh.
hl.unbind("SUPER + SHIFT + CTRL + A")
o.bind("SUPER + SHIFT + CTRL + A", "Agent", "aibrain-agent")'
  [[ "$HYPR_IGNORE_KEY_UNKNOWN" != 1 ]] || hypr_block+='
-- KEY_UNKNOWN is evdev 240 / XKB 248. Consume unsupported reports before they
-- enter the pressed-key list and become NUL input on focus changes.
hl.bind("code:248", function() end, { locked = true, ignore_mods = true, dont_inhibit = true, submap_universal = true, description = "Ignore unsupported key reports" })'
  hypr_block+='
-- <<< aibrain <<<'
  mkdir -p "$(dirname "$HYPR_BINDINGS")" && touch "$HYPR_BINDINGS"
  # Take out the block, with the blank line before it, then put it back at the end
  hypr_new="$(awk '
    /^-- >>> aibrain >>>$/ { held = 0; skip = 1; next }
    skip { if ($0 ~ /^-- <<< aibrain <<<$/) skip = 0; next }
    /^$/ { if (held) print ""; held = 1; next }
    { if (held) print ""; held = 0; print }
  ' "$HYPR_BINDINGS")"
  hypr_new="${hypr_new:+$hypr_new$'\n\n'}$hypr_block"
  if [[ "$hypr_new" != "$(< "$HYPR_BINDINGS")" ]]; then
    mkdir -p "$BACKUP/.config/hypr" && cp "$HYPR_BINDINGS" "$BACKUP/.config/hypr/bindings.lua"
    printf '%s\n' "$hypr_new" > "$HYPR_BINDINGS"
  fi
fi

# --- Claude Code: user-scope MCP servers live in ~/.claude.json, which is not tracked. Add them here, e.g.:
# claude mcp add --scope user <name> -- <command> [args...]
# Plugins, e.g.:
# claude plugin install <plugin>@claude-plugins-official

# --- Tailscale, the way Omarchy's own installer (omarchy-install-service-tailscale) sets it up: the
# package, tailscaled, the tailnet joined with routes accepted, $USER as operator, Taildrop into
# ~/Downloads, the bar widget, and the admin console web app. The installer can't be re-run once
# Tailscale is set up (its `tailscale up --accept-routes` then fails on the operator setting), so
# this does its steps one at a time, each only when it isn't done yet. It joins with the
# "Tailscale auth key" item in the vault when there is one, and otherwise with a browser login.
# A computer with TS_SHARE_LAN set shares that LAN instead: it advertises the LAN, forwards IPv4 for
# it, and doesn't accept routes, because it reaches that LAN directly. Its route needs approving once
# in the admin console. On Ubuntu the package comes from Tailscale's apt repo. Without a desktop, Taildrop
# receiving, the bar widget and the web app are left out.
TS_SYSCTL=/etc/sysctl.d/99-aibrain-tailscale.conf
ts_up() { [[ "$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')" == Running ]]; }
ts_prefs() { tailscale debug prefs 2>/dev/null || true; }
ts_accept() { if [[ -n "$TS_SHARE_LAN" ]]; then echo false; else echo true; fi; }
ts_prefs_ok() {
  [[ "$(ts_prefs | jq -r '[.OperatorUser, .RouteAll, ((.AdvertiseRoutes // []) | join(","))] | map(tostring) | join("|")')" == "$USER|$(ts_accept)|$TS_SHARE_LAN" ]]
}
ts_sysctl() { printf '# Managed by ~/Projects/aibrain/bootstrap.sh: this machine routes %s onto the tailnet.\nnet.ipv4.ip_forward = 1\n' "$1"; }
ts_fwd_ok() { # forwarding on for a subnet router, and no forwarding file of ours anywhere else
  local lan="$TS_SHARE_LAN"
  if [[ -n "$lan" ]]; then
    [[ "$(cat "$TS_SYSCTL" 2>/dev/null)" == "$(ts_sysctl "$lan")" && "$(sysctl -n net.ipv4.ip_forward)" == 1 ]]
  else
    [[ ! -e "$TS_SYSCTL" ]]
  fi
}
tsd_running() { systemctl is-enabled --quiet tailscaled.service && systemctl is-active --quiet tailscaled.service; }
# AIBRAIN_TEST_KEEP_TAILSCALE=1 leaves the system's Tailscale alone. The tests set it on their host, which
# they run as another computer, so its settings would change the host's.
if [[ "${AIBRAIN_TEST_KEEP_TAILSCALE:-}" == 1 ]]; then
  :
elif pkg_missing tailscale || ! tsd_running || ! ts_up || ! ts_prefs_ok || ! ts_fwd_ok; then
  if ! have_tty && ! sudo -n true 2>/dev/null; then
    warn "Tailscale isn't fully set up, and that needs sudo. Run this once in a terminal."
  else
    say "Setting up Tailscale"
    pkg_add tailscale
    tsd_running || sudo systemctl enable --now tailscaled.service
    if ! ts_up; then
      # --reset so joining leaves exactly these settings, whatever an earlier setup left behind
      up=(sudo tailscale up --reset --accept-routes --operator="$USER")
      # --reset also drops a machine name given with --hostname. Keep it; a first join uses this
      # computer's name, so after a reinstall the tailnet knows it by its old name again.
      ts_host="$(ts_prefs | jq -r '.Hostname // empty')"
      up+=(--hostname="${ts_host:-$COMPUTER}")
      if op item get "$TS_KEY_ITEM" --vault "$OP_VAULT" >/dev/null 2>&1; then
        op read "op://$OP_VAULT/$TS_KEY_ITEM/credential" | "${up[@]}" --auth-key=file:/dev/stdin --timeout=60s ||
          warn "The Tailscale auth key in 1Password didn't work. It may have expired: put a new one in the \"$TS_KEY_ITEM\" item."
      fi
      if ! ts_up; then
        if have_tty; then
          "${up[@]}"   # prints a login.tailscale.com link and waits for the login
        else
          warn "Tailscale needs a browser login. Run this once in a terminal, or add a \"$TS_KEY_ITEM\" item to 1Password."
        fi
      fi
    fi
    if ts_up; then
      lan="$TS_SHARE_LAN"
      if ! ts_fwd_ok; then
        if [[ -n "$lan" ]]; then
          ts_sysctl "$lan" | sudo tee "$TS_SYSCTL" >/dev/null
          sudo sysctl -q -p "$TS_SYSCTL"
        else
          sudo rm -f "$TS_SYSCTL"
        fi
      fi
      ts_prefs_ok || sudo tailscale set --operator="$USER" --accept-routes="$(ts_accept)" --advertise-routes="$lan"
    fi
  fi
fi
if desktop && omarchy-cmd-present tailscale; then
  systemctl --user is-enabled --quiet omarchy-tailscale-receive.service 2>/dev/null ||
    systemctl --user enable --now omarchy-tailscale-receive.service || warn "Couldn't turn on Taildrop receiving (omarchy-tailscale-receive.service)."
  [[ "$(omarchy-plugin-list 2>/dev/null | awk '$1 == "omarchy.tailscale" { print $2 }')" == enabled ]] ||
    omarchy-plugin-enable omarchy.tailscale || warn "Couldn't add Tailscale to the bar."
  [[ -e "$HOME/.local/share/applications/Tailscale.desktop" ]] ||
    omarchy-webapp-install "Tailscale" "https://login.tailscale.com/admin/machines" https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/tailscale-light.png ||
    warn "Couldn't add the Tailscale admin console web app."
fi

# --- Logins
if [[ "$CODEX_ONLY" != 1 ]] && ! claude auth status >/dev/null 2>&1; then
  if have_tty; then
    say "Logging in to Claude"
    claude auth login </dev/tty
  else
    warn "Claude Code isn't logged in. Run: claude auth login"
  fi
fi

# --- Claude Code asks before its first session in a folder until that folder is trusted, and trusting a
# parent doesn't cover the repos inside it. Trust the OS agent folder and every repo in ~/Projects, the
# way Claude Code's docs say to: projects["<path>"].hasTrustDialogAccepted in ~/.claude.json.
CLAUDE_JSON="$HOME/.claude.json"
trust_dirs=("$os_dir")
for d in "$HOME"/Projects/*/; do [[ -e "$d.git" || "${d%/}" == "$PERSONAL" ]] && trust_dirs+=("${d%/}"); done
if [[ "$CODEX_ONLY" != 1 && -s "$CLAUDE_JSON" ]] &&
   [[ -n "$(jq -r '.projects as $p | $ARGS.positional[] | select((($p // {})[.] // {}).hasTrustDialogAccepted != true)' --args "${trust_dirs[@]}" < "$CLAUDE_JSON")" ]]; then
  claude_json_tmp="$(mktemp "$CLAUDE_JSON.XXXXXX")"
  jq 'reduce $ARGS.positional[] as $d (.; .projects[$d].hasTrustDialogAccepted = true)' --args "${trust_dirs[@]}" < "$CLAUDE_JSON" > "$claude_json_tmp"
  chmod --reference="$CLAUDE_JSON" "$claude_json_tmp" && mv "$claude_json_tmp" "$CLAUDE_JSON"
fi

# --- The privacy check that runs on GitHub (.github/workflows/privacy.yml) reads the personal denylist from
# the AIBRAIN_DENYLIST secret of the public repo. Keep that secret equal to privacy/denylist, when this
# login administers the repo. The variable AIBRAIN_DENYLIST_SHA256 records which version it holds.
if [[ "$REPO" =~ ^https://github\.com/([^/]+/[^/]+)$ && -s "$PERSONAL/privacy/denylist" ]]; then
  slug="${BASH_REMATCH[1]%.git}"
  if [[ "$(gh api "repos/$slug" --jq .permissions.admin 2>/dev/null)" == true ]]; then
    deny_sum="$(sha256sum < "$PERSONAL/privacy/denylist" | cut -c1-64)"
    if [[ "$(gh variable get AIBRAIN_DENYLIST_SHA256 -R "$slug" 2>/dev/null)" != "$deny_sum" ]]; then
      say "Updating the privacy denylist that GitHub's check of $slug uses"
      gh secret set AIBRAIN_DENYLIST -R "$slug" < "$PERSONAL/privacy/denylist" &&
        gh variable set AIBRAIN_DENYLIST_SHA256 -R "$slug" --body "$deny_sum" ||
        warn "Couldn't update the AIBRAIN_DENYLIST secret of $slug, so GitHub's privacy check may use an old list. The GitHub token needs Secrets and Variables write access."
    fi
  fi
fi

# --- Your own steps, for what no setting covers: the personal layer's setup.sh on every computer, then
# computers/<name>/setup.sh on this one. Like this script, each must change nothing on a second run.
# They get AIBRAIN, PERSONAL, COMPUTER and BACKUP; one that fails gets a warning, and the run goes on.
for f in "$PERSONAL/setup.sh" "$PERSONAL/computers/$COMPUTER/setup.sh"; do
  [[ -f "$f" ]] || continue
  AIBRAIN="$AIBRAIN" PERSONAL="$PERSONAL" COMPUTER="$COMPUTER" BACKUP="$BACKUP" bash "$f" ||
    warn "${f#"$HOME"/} failed (exit $?)."
done

[[ -d "$BACKUP" ]] && warn "Files this run replaced are saved in $BACKUP"
say "aibrain setup complete. New terminals pick up the aiagent token."
