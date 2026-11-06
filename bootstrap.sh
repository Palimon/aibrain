#!/bin/bash
# aibrain bootstrap: brings any Omarchy machine to the same AI agent setup,
# whatever state it starts in. Re-running it changes nothing. It also runs on Ubuntu (24.04 is tested),
# for a computer without Omarchy, such as a headless server, and on Windows 11 in Git Bash.
#
# Two repos make the setup. This one, at ~/Projects/aibrain, is public and holds nothing personal.
# Your personal layer, at ~/Projects/aibrain-personal, holds config.sh (the values below), your
# instructions for every agent, SSH shortcuts and the privacy denylist, and in computers/<name>/ what
# differs on one computer. Agent tools get their setup from both through symlinks, listed in the table
# below.
#
# Run it from ~/Projects/aibrain/bootstrap.sh, or before anything is cloned, from
# the clipboard: bash <(wl-paste), or in Git Bash on Windows, bash <(cat /dev/clipboard). Either way, once the checkout matches
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
  TS_ACCEPT_ROUTES=""             # 0: don't accept the tailnet's routes, on a LAN another computer shares (README, "Computers")
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
# Omarchy links its own skills into. Vendored skills include their reference files, scripts, examples,
# licenses and agents/ metadata in the same folder; link the whole folder, including webapp-testing.
# Sources and manual updates are in skills/UPSTREAM.md.
# This includes retro and the separate apply-learnings skill; keep both in every destination.
SKILL_DIRS=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.grok/skills" "$HOME/.pi/agent/skills" "$HOME/.hermes/skills")
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
# --- Which system this is: Omarchy, Ubuntu, or Windows (Git Bash). Steps that differ ask DISTRO, or use
# pkg_missing and pkg_add. On Windows a package is a winget id.
if [[ "$(uname -s)" == MINGW* ]]; then
  DISTRO=windows
  export USER="${USER:-$USERNAME}"   # Windows sets USERNAME; Git Bash doesn't always set USER
  # ln -s makes a real Windows symlink or fails, instead of quietly copying (links need Developer Mode)
  export MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict"
else
  os_id="$( (. /etc/os-release && echo "$ID") 2>/dev/null || true)"
  case "$os_id" in
    omarchy) DISTRO=omarchy ;;
    ubuntu) DISTRO=ubuntu UBUNTU_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")" ;;
    *) die "This setup runs on Omarchy, Ubuntu or Windows (in Git Bash), not \"${os_id:-an unknown system}\"." ;;
  esac
fi
pkg_missing() { # pkg_missing <package>: true when the package isn't installed
  case "$DISTRO" in
    omarchy) omarchy-pkg-missing "$1" ;;
    windows) ! winget list --id "$1" --exact --accept-source-agreements --disable-interactivity >/dev/null 2>&1 ;;
    *) [[ "$(dpkg-query -W -f '${db:Status-Status}' "$1" 2>/dev/null)" != installed ]] ;;
  esac
}
win_path() { # Windows: put the folders installers added to the registry's PATH on this shell's PATH too
  # Only new folders go in, at the front, so Git Bash's own tools stay ahead of System32's find and sort.
  local d new=""
  while IFS= read -r d; do
    [[ -n "$d" && ":$PATH:" != *":$d:"* && ":$new:" != *":$d:"* ]] && new+="$d:"
  done < <(powershell.exe -NoProfile -Command '[Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")' |
    tr -d '\r' | tr ';' '\n' | while IFS= read -r d; do [[ -n "$d" ]] && cygpath -u "$d"; done)
  PATH="$new$PATH"
}
win_admin() { # win_admin <powershell commands>: on Windows, run them as administrator, after Windows asks you (UAC)
  # They run in a window of their own, which closes at the end, so an error is kept in a file and shown here.
  local ps log rc
  ps="$(mktemp --suffix=.ps1)" log="$(mktemp)"
  printf '%s\n' '$ErrorActionPreference = "Stop"' 'try {' "$1" '} catch {' \
    "  \$_ | Out-String | Set-Content -LiteralPath '$(cygpath -w "$log")'; exit 1" '}' > "$ps"
  powershell.exe -NoProfile -Command "\$p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$(cygpath -w "$ps")'; exit \$p.ExitCode"
  rc=$?
  [[ ! -s "$log" ]] || warn "As administrator: $(tr -d '\r' < "$log" | sed '/^\s*$/d')"
  rm -f "$ps" "$log"; return $rc
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
codex_rpc() { # codex_rpc <request>...: send JSON-RPC requests, without ids, to `codex app-server`, the API the
  # ChatGPT app uses, and print each result on a line. Fails on the first error.
  local id=0 req line rc=0
  coproc CODEX_RPC { codex app-server 2>/dev/null; }
  for req in '{"method":"initialize","params":{"clientInfo":{"name":"aibrain","version":"1"},"capabilities":{"experimentalApi":true}}}' "$@"; do
    jq -c --argjson id "$id" '. + {id: $id}' <<< "$req" >&"${CODEX_RPC[1]}"
    rc=1
    while IFS= read -r -t 60 line <&"${CODEX_RPC[0]}"; do
      [[ "$(jq -r '.id // empty' <<< "$line")" == "$id" ]] || continue
      jq -e 'has("result")' <<< "$line" >/dev/null && rc=0
      ((rc || id == 0)) || jq -c .result <<< "$line"
      break
    done
    ((rc == 0)) || break
    ((id++ > 0)) || printf '%s\n' '{"method":"initialized"}' >&"${CODEX_RPC[1]}"
  done
  exec {CODEX_RPC[1]}>&-
  wait "$CODEX_RPC_PID" 2>/dev/null
  return "$rc"
}
pkg_add() { # pkg_add <package>...: install the packages that are missing, from the distro's repos or a vendor's
  local p missing=()
  for p in "$@"; do if pkg_missing "$p"; then missing+=("$p"); fi; done
  ((${#missing[@]})) || return 0
  say "Installing ${missing[*]}"
  if [[ "$DISTRO" == windows ]]; then
    # Per-user where the package allows it, so no administrator is needed. Python goes on the PATH ahead of
    # Windows' python app aliases.
    for p in "${missing[@]}"; do
      local extra=()
      case "$p" in Python.Python.*) extra=(--scope user --custom PrependPath=1) ;; esac
      winget install --id "$p" --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity "${extra[@]}" >/dev/null ||
        die "winget couldn't install $p."
    done
    win_path
    return 0
  fi
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
# asks for the password one last time. On Windows the same comes from UAC set to never notify:
# administrators elevate without being asked, with UAC itself still on. Setting it asks through UAC one
# last time, and from then on win_admin needs no terminal (win_admin_ok).
UAC_KEY='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
win_uac_quiet() {
  [[ "$(powershell.exe -NoProfile -Command "\$k = Get-ItemProperty '$UAC_KEY'; \"\$(\$k.ConsentPromptBehaviorAdmin) \$(\$k.PromptOnSecureDesktop)\"" | tr -d '\r')" == "0 0" ]]
}
win_admin_ok() { have_tty || win_uac_quiet; }   # win_admin can run: someone can answer UAC, or it won't ask
admin_ok() { # a step that changes the whole computer can run: sudo works or can ask, or on Windows, win_admin
  if [[ "$DISTRO" == windows ]]; then win_admin_ok; else have_tty || sudo -n true 2>/dev/null; fi
}
if [[ "$DISTRO" == windows ]] && ! win_uac_quiet; then
  if have_tty; then
    say "Letting administrators elevate without being asked (UAC)"
    win_admin "Set-ItemProperty -Path '$UAC_KEY' -Name ConsentPromptBehaviorAdmin -Value 0
Set-ItemProperty -Path '$UAC_KEY' -Name PromptOnSecureDesktop -Value 0" && win_uac_quiet ||
      die "Couldn't set UAC to elevate administrators without asking. This user must be an administrator."
  else
    warn "UAC still asks before each change to the whole computer, and setting that needs you once. Run this once in a terminal."
  fi
fi
SUDOERS=/etc/sudoers.d/zz-aibrain
SUDOERS_LINE="$USER ALL=(ALL) NOPASSWD: ALL"
if [[ "$DISTRO" != windows && "$(sudo -n cat "$SUDOERS" 2>/dev/null)" != "$SUDOERS_LINE" ]]; then
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
# and mise's own apt repos. Windows gets them, jq and the GitHub CLI from winget; Git for Windows is
# already there, since this runs in its Git Bash.
if [[ "$DISTRO" == omarchy ]]; then
  pkg_add 1password-cli python
elif [[ "$DISTRO" == windows ]]; then
  pkg_add Python.Python.3.13 jqlang.jq AgileBits.1Password.CLI GitHub.cli
  win_path
  # The hooks and the privacy guard run python3 on every system. python.org's Windows Python has no
  # python3.exe, and Windows' own python3 is an app alias that only offers the Store, so the install gets
  # a python3.exe: a copy of its python.exe, renewed when an update changes that.
  py_dir="$(python -c 'import os, sys; print(os.path.dirname(sys.executable))' 2>/dev/null | tr -d '\r')" ||
    die "Python from winget isn't on the PATH. Open a new Git Bash and run this again."
  py_dir="$(cygpath -u "$py_dir")"
  cmp -s "$py_dir/python.exe" "$py_dir/python3.exe" || cp "$py_dir/python.exe" "$py_dir/python3.exe"
  [[ "$(command -v python3)" == "$py_dir/python3" ]] && python3 -c '' ||
    die "python3 isn't Python from winget but $(command -v python3). Put $py_dir first on the PATH."
  # Links: the agent tools reach the repos through symlinks, which Windows lets you make only in Developer Mode
  ln_check="$(mktemp -d)" ln_ok=1
  ln -s "$ln_check" "$ln_check/link" 2>/dev/null || ln_ok=""
  rm -rf "$ln_check"
  [[ -n "$ln_ok" ]] || die "Windows doesn't let this user make symlinks. Turn on Developer Mode (Settings > System > Advanced, or open ms-settings:developers), then run this again."
  # Bash scripts need LF, which Git for Windows changes to CRLF by default, in every checkout
  [[ "$(git config --global core.autocrlf)" == false ]] || git config --global core.autocrlf false
else
  pkg_add ca-certificates curl gpg git jq python3
  pkg_add 1password-cli mise
fi

# --- gh through mise, the same way Omarchy's launchers in ~/.local/bin do it (on Windows it came from
# winget, above). Claude Code comes later, once this computer's settings are known.
if [[ "$DISTRO" != windows ]]; then
  say "Installing the GitHub CLI"
  MISE_MINIMUM_RELEASE_AGE=0 mise use -g --quiet gh
fi

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
# setup-git would write gh's versioned install path; point at the mise shim so gh upgrades don't break git.
# winget's gh keeps one path, on the PATH.
gh_helper="$MISE_SHIMS/gh"; [[ "$DISTRO" != windows ]] || gh_helper=gh
for host in github.com gist.github.com; do
  git config --global --replace-all "credential.https://$host.helper" ''
  git config --global --add "credential.https://$host.helper" "!$gh_helper auth git-credential"
done
# --- ~/Projects/aibrain is a checkout of origin/main
fresh_clone() { # fresh_clone <dir> <repo>: clone <repo> into <dir>, saving whatever was there
  if [[ -e "$1" ]]; then
    warn "~/${1#"$HOME"/} isn't a checkout of $2. Moving it to $BACKUP and cloning fresh."
    saved "$1"
  fi
  mkdir -p "$(dirname "$1")"
  git clone -q "$2" "$1"
  exclude_worktrees "$1"
  win_links "$1"
}
win_links() { # win_links <dir>: on Windows, the checkout's own symlinks are real links
  # Git for Windows clones links as small text files unless the checkout says it may make links, and
  # makes them only on a fresh checkout of the file. A file that should be a link is checked out again.
  [[ "$DISTRO" == windows ]] || return 0
  local mode f
  [[ "$(git -C "$1" config core.symlinks)" == true ]] || git -C "$1" config core.symlinks true
  git -C "$1" ls-files -s | while read -r mode _ _ f; do
    [[ "$mode" == 120000 && ! -L "$1/$f" ]] || continue
    rm -f "$1/$f" && git -C "$1" checkout -q -- "$f"
  done
}
exclude_worktrees() { # exclude_worktrees <dir>: Claude Code's session worktrees in .claude/worktrees/ are never local changes
  # It goes in the checkout's own .git/info/exclude, not a .gitignore, so it covers any repo the script
  # keeps, the personal layer included, without a commit there.
  local f; f="$(git -C "$1" rev-parse --git-path info/exclude)"
  [[ "$f" == /* || "$f" == [A-Za-z]:/* ]] || f="$1/$f"   # Git for Windows writes an absolute path as C:/...
  grep -qxF '/.claude/worktrees/' "$f" 2>/dev/null && return
  mkdir -p "$(dirname "$f")"
  [[ ! -s "$f" || -z "$(tail -c 1 "$f")" ]] || echo >> "$f"
  echo '/.claude/worktrees/' >> "$f"
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
with open(path, "w", newline="\n") as f: json.dump(cur, f, indent=2); f.write("\n")
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
  exclude_worktrees "$dir"
  win_links "$dir"
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
else
  win_links "$AIBRAIN"   # the update above does this; a run that skips it still needs real links
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
  if [[ "$DISTRO" == windows ]]; then
    about="$(powershell.exe -NoProfile -Command '$c = Get-CimInstance Win32_ComputerSystem; "$($c.Manufacturer) $($c.Model)"' 2>/dev/null | tr -d '\r' || true)"
  else
    about="$(hostnamectl --json=short 2>/dev/null |
      jq -r '[.HardwareVendor, .HardwareModel, .Chassis] | map(select(. != null and . != "")) | join(" ")' 2>/dev/null || true)"
  fi
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
# Code from mise is removed, along with its managed settings below. On Windows it's Anthropic's native
# install, in ~/.local/bin, which keeps itself up to date, and the Claude app comes from winget.
[[ "$DISTRO" != windows || "$CODEX_ONLY" != 1 ]] || die "CODEX_ONLY isn't supported on Windows yet."
if [[ "$CODEX_ONLY" != 1 ]]; then
  if [[ "$DISTRO" == windows ]]; then
    if [[ ! -x "$HOME/.local/bin/claude.exe" ]]; then
      say "Installing Claude Code"
      powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex' >/dev/null ||
        die "Claude Code's installer failed."
    fi
    pkg_add Anthropic.Claude
  else
    say "Installing Claude Code"
    MISE_MINIMUM_RELEASE_AGE=0 mise use -g --quiet claude
  fi
  # Claude Code's first start migrates settings.json (it turns "opus" into "opus[1m]") and records that in
  # ~/.claude.json. Let that happen now, before settings.json links to the repo, so it stays as committed.
  claude auth status >/dev/null 2>&1 || true
elif mise ls --installed claude 2>/dev/null | grep -q .; then
  say "Removing Claude Code, since this computer is Codex-only"
  mise unuse -g --quiet claude 2>/dev/null || true   # its line in mise's config; this leaves the install
  mise uninstall --quiet --all claude && mise reshim
fi
# Codex: Omarchy installs it the first time it's started. On Windows the CLI comes from winget, along with
# the ChatGPT app from the Microsoft Store, which has Codex in it too; winget upgrade updates both.
# Elsewhere Codex comes through mise, once; a version pinned later (mise use -g codex@<version>) is kept.
if [[ "$DISTRO" == windows ]]; then
  pkg_add OpenAI.Codex 9PLM9XGG6VKS   # 9PLM9XGG6VKS: the ChatGPT app's Store id
elif [[ "$DISTRO" != omarchy ]] && ! mise which codex >/dev/null 2>&1; then
  say "Installing Codex"
  MISE_MINIMUM_RELEASE_AGE=0 mise use -g --quiet codex
fi

# --- Links from the agent tools into the repos. A skill, agent or script in the personal layer wins over
# one here with the same name. The shared grab-issue skill is available in every project;
# existing project-local skills remain untouched.
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
# to its own session (README, "Model and effort"). On Windows the file is in Program Files, which only an
# administrator may write.
MANAGED_SETTINGS=/etc/claude-code/managed-settings.json
if [[ "$DISTRO" == windows ]]; then
  MANAGED_SETTINGS="/c/Program Files/ClaudeCode/managed-settings.json"
  if ! cmp -s "$AIBRAIN/claude/managed-settings.json" "$MANAGED_SETTINGS"; then
    say "Setting Claude Code's default model and effort"
    win_admin_ok || die "Installing $MANAGED_SETTINGS needs an administrator. Run this once in a terminal."
    win_admin "New-Item -ItemType Directory -Force -Path '$(cygpath -w "${MANAGED_SETTINGS%/*}")' | Out-Null
Copy-Item -Force -LiteralPath '$(cygpath -w "$AIBRAIN/claude/managed-settings.json")' -Destination '$(cygpath -w "$MANAGED_SETTINGS")'" &&
      cmp -s "$AIBRAIN/claude/managed-settings.json" "$MANAGED_SETTINGS" ||
      die "Couldn't install $MANAGED_SETTINGS as administrator."
  fi
elif [[ "$CODEX_ONLY" == 1 ]]; then
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
# .bashrc's interactive-shell check, because agents' shells are non-interactive. On Windows that's every
# Git Bash, Claude Code's included; PowerShell doesn't read it.
say "Updating ~/.bashrc"
touch "$HOME/.bashrc"
block="# >>> aibrain >>>
# 1Password service account for AI agents (vault: $OP_VAULT). Managed by ~/Projects/aibrain/bootstrap.sh."'
# A launcher that sets AIBRAIN_NO_VAULT=1 keeps the token out of an agent'\''s shells.
if [[ -n ${AIBRAIN_NO_VAULT:-} ]]; then unset OP_SERVICE_ACCOUNT_TOKEN; elif [[ -r ~/.config/op/aiagent-token ]]; then export OP_SERVICE_ACCOUNT_TOKEN="$(< ~/.config/op/aiagent-token)"; fi'
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

# --- Issue labels are per-project opt-ins. Keep configured GitHub labels current on light and full
# setups, including after a reinstall. Local test remotes and projects without a manifest are skipped.
for project in "$HOME"/Projects/*/; do
  [[ -f "$project/docs/agents/labels.json" ]] || continue
  python3 -I "$AIBRAIN/bin/aibrain-labels" "$project" ||
    warn "Couldn't synchronize the configured labels for $(basename "$project"). Check GitHub Issues write access."
done

# --- SSH. The fleet key from 1Password is this computer's key for your servers and your other computers.
# ~/.ssh/config starts with an Include of the personal layer's ssh/config when it has one. ssh keeps the
# first value it finds for each setting, so those shortcuts win over anything else in the file.
SSH_KEY="$HOME/.ssh/aibrain_fleet"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
# (On Windows op writes the key's lines with CRLF, which Git Bash's OpenSSH can't read: tr takes the CRs out.)
if ssh_key="$(op read "$SSH_KEY_ITEM/private key?ssh-format=openssh" 2>/dev/null | tr -d '\r')" && [[ -n "$ssh_key" ]] &&
   ssh_pub="$(op read "$SSH_KEY_ITEM/public key" 2>/dev/null | tr -d '\r')"; then
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
if [[ "$DISTRO" != windows ]] && { [[ "$(cat "$SSHD_CONF" 2>/dev/null)" != "$sshd_conf" ]] || ! ssh_running; }; then
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
# its memory for this computer (bin/aibrain-agent). On Windows there's no hotkey: the folder is a project in
# the ChatGPT app (below), and Claude's app lists it once a session has run there. A new folder gets a
# starting AGENTS.md and NEXT-STEPS.md; after that the files are the agent's own.
os_dir="$HOME/osagent"
for d in "${OS_AGENT_DIRS[@]}"; do if [[ -d "$d" ]]; then os_dir="$d"; break; fi; done
mkdir -p "$os_dir" "$(dirname "$OS_AGENT_FILE")"
[[ "$(cat "$OS_AGENT_FILE" 2>/dev/null)" == "$os_dir" ]] || printf '%s\n' "$os_dir" > "$OS_AGENT_FILE"
[[ -e "$os_dir/AGENTS.md" ]] || cat > "$os_dir/AGENTS.md" <<EOF
# OS agent for $COMPUTER

This folder is the memory of the agent that looks after this computer, $COMPUTER: its setup, hardware, problems and open work. Keep what you learn here as files, one topic per \`.md\`, and keep this file pointing to them. Open work goes in \`NEXT-STEPS.md\`.

A fix that must outlast a reinstall goes in the personal layer, in \`computers/$COMPUTER/\`, as aibrain's README describes under "Computers".
EOF
[[ -e "$os_dir/NEXT-STEPS.md" ]] || printf '%s\n' "# Open work on $COMPUTER" "" "Nothing yet." > "$os_dir/NEXT-STEPS.md"
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
# in the admin console. A computer with TS_ACCEPT_ROUTES=0 doesn't accept routes either: it sits on a
# LAN that another computer shares, and accepted, that LAN's route would send its own LAN traffic,
# replies included, into the tailnet. It doesn't accept them even while it first joins. On Ubuntu the package comes from Tailscale's apt repo. Without a desktop, Taildrop
# receiving, the bar widget and the web app are left out.
# On Windows it's Tailscale's own app from winget, whose service needs no sudo and has no operator. It
# joins unattended instead, so it stays up while nobody is signed in to Windows, as tailscaled does
# elsewhere, and Taildrop comes with the app. Sharing a LAN (TS_SHARE_LAN) isn't supported there yet.
TS_SYSCTL=/etc/sysctl.d/99-aibrain-tailscale.conf
TS_PKG=tailscale TS_ADMIN=(sudo) TS_OWNER=(--operator="$USER") TS_OWNER_PREF='.OperatorUser' TS_OWNER_WANT="$USER"
if [[ "$DISTRO" == windows ]]; then
  TS_PKG=Tailscale.Tailscale TS_ADMIN=() TS_OWNER=(--unattended) TS_OWNER_PREF='.ForceDaemon' TS_OWNER_WANT=true
  PATH="/c/Program Files/Tailscale:$PATH"
fi
ts_up() { [[ "$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' | tr -d '\r')" == Running ]]; }
ts_prefs() { tailscale debug prefs 2>/dev/null || true; }
ts_accept() { if [[ -n "$TS_SHARE_LAN" || "$TS_ACCEPT_ROUTES" == 0 ]]; then echo false; else echo true; fi; }
ts_prefs_ok() {
  [[ "$(ts_prefs | jq -r "[$TS_OWNER_PREF, .RouteAll, ((.AdvertiseRoutes // []) | join(\",\"))] | map(tostring) | join(\"|\")" | tr -d '\r')" == "$TS_OWNER_WANT|$(ts_accept)|$TS_SHARE_LAN" ]]
}
ts_sysctl() { printf '# Managed by ~/Projects/aibrain/bootstrap.sh: this machine routes %s onto the tailnet.\nnet.ipv4.ip_forward = 1\n' "$1"; }
ts_fwd_ok() { # forwarding on for a subnet router, and no forwarding file of ours anywhere else
  local lan="$TS_SHARE_LAN"
  [[ "$DISTRO" != windows ]] || return 0
  if [[ -n "$lan" ]]; then
    [[ "$(cat "$TS_SYSCTL" 2>/dev/null)" == "$(ts_sysctl "$lan")" && "$(sysctl -n net.ipv4.ip_forward)" == 1 ]]
  else
    [[ ! -e "$TS_SYSCTL" ]]
  fi
}
tsd_running() {
  if [[ "$DISTRO" == windows ]]; then
    [[ "$(powershell.exe -NoProfile -Command '$s = Get-Service Tailscale -ErrorAction SilentlyContinue; "$($s.Status) $($s.StartType)"' | tr -d '\r')" == "Running Automatic" ]]
  else
    systemctl is-enabled --quiet tailscaled.service && systemctl is-active --quiet tailscaled.service
  fi
}
# AIBRAIN_TEST_KEEP_TAILSCALE=1 leaves the system's Tailscale alone. The tests set it on their host, which
# they run as another computer, so its settings would change the host's.
if [[ "${AIBRAIN_TEST_KEEP_TAILSCALE:-}" == 1 ]]; then
  :
elif [[ "$DISTRO" == windows && -n "$TS_SHARE_LAN" ]]; then
  warn "TS_SHARE_LAN isn't supported on Windows yet, so Tailscale is left as it is."
elif pkg_missing "$TS_PKG" || ! tsd_running || ! ts_up || ! ts_prefs_ok || ! ts_fwd_ok; then
  if ! admin_ok; then
    warn "Tailscale isn't fully set up, and that needs sudo or an administrator. Run this once in a terminal."
  else
    say "Setting up Tailscale"
    pkg_add "$TS_PKG"   # on Windows its installer asks you through UAC
    if ! tsd_running; then
      if [[ "$DISTRO" == windows ]]; then
        win_admin "Set-Service Tailscale -StartupType Automatic; Start-Service Tailscale" ||
          warn "Couldn't start the Tailscale service."
      else
        sudo systemctl enable --now tailscaled.service
      fi
    fi
    if ! ts_up; then
      # --reset so joining leaves exactly these settings, whatever an earlier setup left behind
      up=("${TS_ADMIN[@]}" tailscale up --reset --accept-routes="$(ts_accept)" "${TS_OWNER[@]}")
      # --reset also drops a machine name given with --hostname. Keep it; a first join uses this
      # computer's name, so after a reinstall the tailnet knows it by its old name again.
      ts_host="$(ts_prefs | jq -r '.Hostname // empty' | tr -d '\r')"
      up+=(--hostname="${ts_host:-$COMPUTER}")
      if op item get "$TS_KEY_ITEM" --vault "$OP_VAULT" >/dev/null 2>&1; then
        if [[ "$DISTRO" == windows ]]; then   # tailscale.exe can't open /dev/stdin; a file in this user's temp folder instead
          ts_key="$(mktemp)"; op read "op://$OP_VAULT/$TS_KEY_ITEM/credential" > "$ts_key"
          "${up[@]}" --auth-key="file:$(cygpath -w "$ts_key")" --timeout=60s && ts_rc=0 || ts_rc=$?
          rm -f "$ts_key"
        else
          op read "op://$OP_VAULT/$TS_KEY_ITEM/credential" | "${up[@]}" --auth-key=file:/dev/stdin --timeout=60s && ts_rc=0 || ts_rc=$?
        fi
        ((ts_rc == 0)) ||
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
      ts_prefs_ok || "${TS_ADMIN[@]}" tailscale set "${TS_OWNER[@]}" --accept-routes="$(ts_accept)" --advertise-routes="$lan"
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

# --- The SSH server on Windows: Windows' own OpenSSH, an optional feature, set up in one step as administrator.
# Key logins only (a block at the top of C:\ProgramData\ssh\sshd_config, where the first value wins), the
# fleet key in administrators_authorized_keys (sshd reads that file instead of ~/.ssh/authorized_keys for
# an administrator), Git Bash as the shell, the service started with Windows, and a firewall rule of its own
# that lets SSH in through Tailscale's network adapter only, with Windows' rule for every network turned off.
# The adapter exists once Tailscale is up, so this step comes after Tailscale's.
# Checking needs no administrator: the service, a login here with the fleet key, no password logins, the rule.
WIN_SSH_ADAPTER=Tailscale
WIN_SSH_RULE="Managed by ~/Projects/aibrain/bootstrap.sh: SSH through the $WIN_SSH_ADAPTER adapter only"
win_ssh_login() { # win_ssh_login <ssh options>...: log in to this computer and run true; ssh's errors on stdout
  # Git Bash's ssh, the one agents use, which is stricter about keys than Windows' own
  /usr/bin/ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR "$@" "$USER@localhost" true 2>&1
}
win_sshd_ok() {
  local want="Running Automatic|True $WIN_SSH_RULE|" got   # then Windows' own rule: turned off, or not there
  got="$(powershell.exe -NoProfile -Command '
    $s = Get-Service sshd -ErrorAction SilentlyContinue
    $r = Get-NetFirewallRule -Name aibrain-sshd -ErrorAction SilentlyContinue
    $d = Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue
    "$($s.Status) $($s.StartType)|$($r.Enabled) $($r.Description)|$($d.Enabled)"' | tr -d '\r')"
  [[ "$got" == "$want" || "$got" == "${want}False" ]] &&
    win_ssh_login -i "$SSH_KEY" -o IdentitiesOnly=yes >/dev/null &&
    [[ "$(win_ssh_login -o PubkeyAuthentication=no)" == *"Permission denied (publickey)"* ]]
}
if [[ "$DISTRO" == windows ]]; then
  if [[ -z "${ssh_pub:-}" ]]; then
    warn "The SSH server isn't set up, since the fleet key couldn't be read."
  elif ! ts_up; then
    warn "The SSH server isn't set up, since it waits for Tailscale, whose adapter its firewall rule names."
  elif ! win_sshd_ok; then
    if ! win_admin_ok; then
      warn "The SSH server isn't fully set up, and that needs an administrator. Run this once in a terminal."
    else
      say "Setting up the SSH server"
      win_admin "
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null }
\$dir = \"\$env:ProgramData\\ssh\"; \$conf = \"\$dir\\sshd_config\"
if (-not (Test-Path \$conf)) { Start-Service sshd; Stop-Service sshd }   # its first start writes the config and host keys
\$block = \"# >>> aibrain >>>\`n# Managed by ~/Projects/aibrain/bootstrap.sh: key logins only.\`nPasswordAuthentication no\`nKbdInteractiveAuthentication no\`n# <<< aibrain <<<\`n\"
\$text = [IO.File]::ReadAllText(\$conf)
\$new = \$block + [regex]::Replace(\$text, '(?s)# >>> aibrain >>>.*?# <<< aibrain <<<\r?\n', '')
if (\$new -ne \$text) { [IO.File]::WriteAllText(\$conf, \$new) }
& \"\$env:WINDIR\\System32\\OpenSSH\\sshd.exe\" -t; if (\$LASTEXITCODE) { throw \"sshd rejected \$conf\" }
\$keys = \"\$dir\\administrators_authorized_keys\"; \$line = '$ssh_pub ssh fleet key'
if (-not (Test-Path \$keys) -or -not (@(Get-Content \$keys) -contains \$line)) { Add-Content -Encoding ascii -LiteralPath \$keys -Value \$line }
icacls.exe \$keys /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
if (-not (Test-Path HKLM:\\SOFTWARE\\OpenSSH)) { New-Item -Path HKLM:\\SOFTWARE\\OpenSSH | Out-Null }   # the feature makes it, locked down
Set-ItemProperty -Path HKLM:\\SOFTWARE\\OpenSSH -Name DefaultShell -Type String -Value '$(cygpath -w /)\\bin\\bash.exe'
Set-Service sshd -StartupType Automatic
Restart-Service sshd
Disable-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue
\$rule = @{ Direction = 'Inbound'; Protocol = 'TCP'; LocalPort = 22; Action = 'Allow'; Profile = 'Any'; Enabled = 'True'
  InterfaceAlias = '$WIN_SSH_ADAPTER'; Description = '$WIN_SSH_RULE' }
if (Get-NetFirewallRule -Name aibrain-sshd -ErrorAction SilentlyContinue) { Set-NetFirewallRule -Name aibrain-sshd @rule }
else { New-NetFirewallRule -Name aibrain-sshd -DisplayName 'OpenSSH server, tailnet only (aibrain)' @rule | Out-Null }" &&
        win_sshd_ok || warn "The SSH server isn't fully set up. Check: ssh -i ~/.ssh/aibrain_fleet $USER@localhost"
    fi
  fi
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
# Claude Code on Windows names a folder C:/Users/..., where Git Bash says /c/Users/...
[[ "$DISTRO" != windows ]] || mapfile -t trust_dirs < <(cygpath -m "${trust_dirs[@]}")
if [[ "$CODEX_ONLY" != 1 && -s "$CLAUDE_JSON" ]] &&
   [[ -n "$(jq -r '.projects as $p | $ARGS.positional[] | select((($p // {})[.] // {}).hasTrustDialogAccepted != true)' --args "${trust_dirs[@]}" < "$CLAUDE_JSON")" ]]; then
  claude_json_tmp="$(mktemp "$CLAUDE_JSON.XXXXXX")"
  jq 'reduce $ARGS.positional[] as $d (.; .projects[$d].hasTrustDialogAccepted = true)' --args "${trust_dirs[@]}" < "$CLAUDE_JSON" > "$claude_json_tmp"
  chmod --reference="$CLAUDE_JSON" "$claude_json_tmp" && mv "$claude_json_tmp" "$CLAUDE_JSON"
fi

# --- Codex trusts the same folders, in ~/.codex/config.toml's projects table, and the ChatGPT app gets the OS
# agent's folder as a project, which Codex keeps in its state database. Both go through codex_rpc, so
# neither file is edited by hand. Codex on Windows names a folder C:\Users\...
if command -v codex >/dev/null 2>&1; then
  codex_dirs=("${trust_dirs[@]}")
  [[ "$DISTRO" != windows ]] || mapfile -t codex_dirs < <(cygpath -w "${codex_dirs[@]}")
  if ! codex_state="$(codex_rpc '{"method":"config/read","params":{}}' '{"method":"project/list","params":{"limit":1000}}')"; then
    warn "Couldn't reach codex app-server, so Codex may not trust ${codex_dirs[0]} and the repos, and the ChatGPT app may have no OS Agent project."
  else
    codex_trust="$(jq -sc '.[0].config.projects as $p | [$ARGS.positional[] | select((($p // {})[.] // {}).trust_level != "trusted") | {(.): {trust_level: "trusted"}}] | add // empty' --args "${codex_dirs[@]}" <<< "$codex_state")"
    if [[ -n "$codex_trust" ]]; then
      say "Making Codex trust the OS agent's folder and the repos in ~/Projects"
      codex_rpc "$(jq -nc --argjson v "$codex_trust" '{method: "config/value/write", params: {keyPath: "projects", mergeStrategy: "upsert", value: $v}}')" >/dev/null ||
        warn "Couldn't make Codex trust ${codex_dirs[*]}."
    fi
    if ! jq -se --arg d "${codex_dirs[0]}" '.[1].data | any(.roots[].path == $d)' <<< "$codex_state" >/dev/null; then
      say "Adding the OS agent's folder to the ChatGPT app as a project"
      codex_rpc "$(jq -nc --arg d "${codex_dirs[0]}" --arg k "aibrain-$(date +%s)-$RANDOM" '{method: "project/create", params: {idempotencyKey: $k, name: "OS Agent", roots: [{path: $d}]}}')" >/dev/null ||
        warn "Couldn't add ${codex_dirs[0]} to the ChatGPT app as a project."
    fi
  fi
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
