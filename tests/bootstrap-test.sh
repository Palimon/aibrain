#!/bin/bash
# Runs bootstrap.sh in throwaway homes on tmpfs, so a change can be tested without touching the real
# home. Each scenario runs the script twice and checks the second run changes nothing.
# Needs OP_SERVICE_ACCOUNT_TOKEN set (every shell has it unless a launcher sets AIBRAIN_NO_VAULT=1). Tests the last commit in this checkout.
# Usage: tests/bootstrap-test.sh fresh|bashrc-migrate|no-personal|migrate|projects-junk|full|unknown-key-binding|picks|computers|worktrees|ubuntu|ubuntu-claude|all
#
# Each home gets a personal layer cloned from a fixture made from personal.example, except in
# no-personal (none, so the script makes one) and full, which clones a copy of your own personal layer
# (AIBRAIN_TEST_PERSONAL, default ~/Projects/aibrain-personal, its committed state) and the small repo
# its config.sh names in TEST_REPO. Without those, full is skipped.
#
# Limits: pacman packages, sudoers, the SSH server and /etc/claude-code are system-wide, so those steps
# see the real machine. They write the same thing on every computer, the commit's own version of it, and
# host_state checks that the host's copies don't change. Tailscale's settings differ from computer to
# computer, and the homes run as computers other than the host, so the script leaves the host's Tailscale
# alone (AIBRAIN_TEST_KEEP_TAILSCALE); host_state checks that too. A home's mise installs are the host's,
# so a host scenario never runs as a Codex-only computer, whose run would uninstall the host's Claude Code. The ubuntu scenarios run in an Ubuntu 24.04 container instead (Docker,
# through sudo when this user can't reach it), where every step runs for real except joining the tailnet.
# There is no user systemd bus inside the test, so the Taildrop warning is expected.
set -uo pipefail
ROOT="$XDG_RUNTIME_DIR/aibrain-test"
REAL_MISE="${MISE_DATA_DIR:-$HOME/.local/share/mise}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"   # this checkout, holding the commit under test
REAL_PERSONAL="${AIBRAIN_TEST_PERSONAL:-$HOME/Projects/aibrain-personal}"
FIXTURE="$ROOT/personal-fixture"
host_state() { # what the host scenarios must leave as it was: the host's Tailscale and system-wide files
  echo "tailscale prefs: $(tailscale debug prefs 2>/dev/null | jq -r '[.OperatorUser, .RouteAll, ((.AdvertiseRoutes // []) | join(","))] | map(tostring) | join("|")')"
  echo "ip forwarding: $(sysctl -n net.ipv4.ip_forward)"
  sha256sum /etc/sysctl.d/99-aibrain-tailscale.conf /etc/claude-code/managed-settings.json /etc/ssh/sshd_config.d/50-aibrain.conf 2>&1
  echo "sudoers: $(sudo -n sha256sum /etc/sudoers.d/zz-aibrain 2>&1)"
}
host_check() { # host_check: fail loudly when the host differs from HOST_BEFORE
  if diff <(printf '%s\n' "$HOST_BEFORE") <(host_state); then
    echo "HOST_UNCHANGED: yes"
  else
    echo "HOST_UNCHANGED: NO. This scenario changed the host. Put the lines above marked < back by hand." >&2
    echo "HOST_UNCHANGED: NO"; return 1
  fi
}
trap 'rm -rf "$ROOT"' EXIT                   # the homes hold copies of the token
mkdir -p "$ROOT"; git -C "$SRC" show HEAD:bootstrap.sh > "$ROOT/pasted.sh"

mkfixture() { # a personal layer repo: personal.example as committed, with test values, a skill of its own, a
  # setup.sh for every computer, and a computer named test-box with a setting and a setup.sh of its own
  rm -rf "$FIXTURE"; mkdir -p "$FIXTURE"
  git -C "$SRC" archive HEAD personal.example | tar -x -C "$FIXTURE" --strip-components=1
  printf '%s\n' 'GIT_NAME="Test User"' 'GIT_EMAIL="test@example.com"' >> "$FIXTURE/config.sh"
  printf '%s\n' 'mkdir -p "$HOME/setup-ran" && touch "$HOME/setup-ran/every-computer"' > "$FIXTURE/setup.sh"
  mkdir -p "$FIXTURE/computers/test-box" "$FIXTURE/computers/ubuntu-box" "$FIXTURE/computers/ubuntu-claude-box"
  printf '%s\n' '# test-box: a test computer, added 2026-01-01' 'HYPR_IGNORE_KEY_UNKNOWN=1' > "$FIXTURE/computers/test-box/config.sh"
  printf '%s\n' 'mkdir -p "$HOME/setup-ran" && printf "%s %s\n" "$COMPUTER" "$PERSONAL" > "$HOME/setup-ran/test-box"' > "$FIXTURE/computers/test-box/setup.sh"
  printf '%s\n' '# ubuntu-box: a headless Codex-only server, added 2026-01-01' 'HEADLESS=1' 'CODEX_ONLY=1' 'TS_ACCEPT_ROUTES=0' > "$FIXTURE/computers/ubuntu-box/config.sh"
  printf '%s\n' '# ubuntu-claude-box: a computer with every default, added 2026-01-01' > "$FIXTURE/computers/ubuntu-claude-box/config.sh"
  printf '%s\n' 're:\bxyzzy-fixture-term\b' >> "$FIXTURE/privacy/denylist"
  mkdir -p "$FIXTURE/skills/fixture-skill"
  printf '%s\n' '---' 'name: fixture-skill' 'description: A personal skill.' '---' > "$FIXTURE/skills/fixture-skill/SKILL.md"
  # A personal copy must win over the newly vendored handoff skill, including its support files.
  mkdir -p "$FIXTURE/skills/handoff"
  printf '%s\n' '---' 'name: handoff' 'description: A personal handoff override.' '---' > "$FIXTURE/skills/handoff/SKILL.md"
  printf '%s\n' 'Reference for the personal handoff override.' > "$FIXTURE/skills/handoff/REFERENCE.md"
  mkdir -p "$FIXTURE/claude/agents"
  printf '%s\n' '---' 'name: fixture-agent' 'description: A personal agent.' '---' > "$FIXTURE/claude/agents/fixture-agent.md"
  git -C "$FIXTURE" init -q -b main && git -C "$FIXTURE" add -A &&
    git -C "$FIXTURE" -c user.name=t -c user.email=t@example.com commit -qm fixture
  git -C "$FIXTURE" config receive.denyCurrentBranch updateInstead   # the script pushes a new computer's folder
}
mkfixture

mkhome() { # an Omarchy-like home: tool stubs' skill links, default .bashrc, mise installs shared read-only
  H="$ROOT/$1"; rm -rf "$H"; mkdir -p "$H/.local/share/mise/installs" "$H/.config"
  for t in claude gh; do ln -s "$REAL_MISE/installs/$t" "$H/.local/share/mise/installs/$t"; done
  for d in .agents/skills .claude/skills .codex/skills .pi/agent/skills .hermes/skills; do
    mkdir -p "$H/$d"
    for s in omarchy diagnose-crash; do ln -s "/usr/share/omarchy/default/agents/skills/$s" "$H/$d/$s"; done
  done
  cp /etc/skel/.bashrc "$H/.bashrc"
  # Migrate a previous manual installation to the repo-managed folder link.
  mkdir -p "$H/.codex/skills/handoff"
  printf '%s\n' 'Previous manual handoff installation.' > "$H/.codex/skills/handoff/SKILL.md"
  mkdir -p "$H/.config/hypr" "$H/.ssh"   # files of the user's own that the script adds to
  printf '%s\n' '-- Keep only your personal keybinding overrides here.' '' 'o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh x")' > "$H/.config/hypr/bindings.lua"
  printf '%s\n' 'Host old-box' '    HostName 192.0.2.7' > "$H/.ssh/config"
}
oldsplit() { # a setup from before the personal layer: one repo at ~/Projects/aibrain with its own history, linked as
  # the instructions file and the SSH shortcuts, with an uncommitted edit
  local A="$H/Projects/aibrain"
  mkdir -p "$A/ssh" "$H/.claude" && printf '# old instructions\n' > "$A/AGENTS.md" && printf 'Host old\n' > "$A/ssh/config"
  git -C "$A" init -q -b main && git -C "$A" add -A && git -C "$A" -c user.name=t -c user.email=t@example.com commit -qm old
  git -C "$A" remote add origin "$SRC"
  echo "# uncommitted" >> "$A/AGENTS.md"
  ln -s "$A/AGENTS.md" "$H/.claude/CLAUDE.md"
  printf '%s\n' 'Include ~/Projects/aibrain/ssh/config' '' "$(cat "$H/.ssh/config")" > "$H/.ssh/config"
  mkdir -p "$H/.config/op"; chmod 700 "$H/.config/op"; (umask 077; printf '%s' "$OP_SERVICE_ACCOUNT_TOKEN" > "$H/.config/op/aiagent-token")
}
PERSONAL_REPO="$FIXTURE"   # the script's AIBRAIN_PERSONAL_REPO
EXTRA_ENV=()   # more variables for the script, such as AIBRAIN_SETUP
run() { # run <with-env-token 0|1> <script>; no tty, no DBus (gh can't reach the real keyring)
  local tok=(); [[ $1 == 1 ]] && tok=(OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN")
  [[ " ${EXTRA_ENV[*]} " != *ubuntu-box* ]] || { echo "ubuntu-box is Codex-only, so only the ubuntu scenarios run as it"; rc=1; exit 1; }
  (cd "$H" && setsid -w env -i HOME="$H" USER="$USER" PATH=/usr/local/bin:/usr/bin TERM=dumb \
    XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" XDG_STATE_HOME="$H/.local/state" XDG_CACHE_HOME="$H/.cache" \
    DBUS_SESSION_BUS_ADDRESS=disabled: AIBRAIN_TEST_KEEP_TAILSCALE=1 AIBRAIN_REPO="$SRC" AIBRAIN_PERSONAL_REPO="$PERSONAL_REPO" "${tok[@]}" "${EXTRA_ENV[@]}" bash "$2" </dev/null 2>&1) | sed 's/\x1b\[[0-9;]*m//g'
  echo "[exit ${PIPESTATUS[0]}]"
}
snap() {
  sha256sum "$H/.bashrc" "$H/.gitconfig" "$H/.config/git/config" "$H/.config/gh/hosts.yml" "$H/.config/mise/config.toml" \
    "$H/.config/hypr/bindings.lua" "$H/.ssh/config" "$H/.ssh/aibrain_fleet" "$H/.ssh/aibrain_fleet.pub" "$H/.ssh/authorized_keys" 2>/dev/null | sed "s#$H#~#"
  stat -c '%a %n' "$H/.config/op" "$H/.config/op/aiagent-token" "$H/.ssh" "$H/.ssh/aibrain_fleet" "$H/.ssh/config" 2>/dev/null | sed "s#$H#~#"
  echo "setup: $(cat "$H/.config/aibrain/setup" 2>/dev/null || echo unsaved)"
  echo "projects: $(cd "$H/Projects" 2>/dev/null && ls | tr '\n' ' ')"
  echo "trusted by Claude: $(jq -r '(.projects // {}) | to_entries[] | select(.value.hasTrustDialogAccepted == true) | .key' "$H/.claude.json" 2>/dev/null | sed "s#$H#~#" | sort | tr '\n' ' ')"
  for d in .claude .claude/skills .claude/agents .agents/skills .codex .codex/skills .grok .pi/agent/skills .hermes/skills .local/bin; do
    find "$H/$d" -mindepth 1 -maxdepth 1 \( -type l -o -name '*.json' -o -name '*.md' -o -name .git \) -printf "$d/%f -> %l\n" 2>/dev/null | sort
  done | sed "s#$H#~#g"
  local A="$H/Projects/aibrain" P="$H/Projects/aibrain-personal"
  echo "aibrain: $(git -C "$A" rev-parse --short HEAD 2>/dev/null) dirty=[$(git -C "$A" status --porcelain 2>/dev/null | tr '\n' ' ')] stashes=$(git -C "$A" stash list 2>/dev/null | wc -l)"
  echo "excludes: $(cat "$A/.git/info/exclude" "$P/.git/info/exclude" 2>/dev/null | sha256sum | cut -c1-12)"
  echo "aibrain git: hooks=$(git -C "$A" config core.hooksPath) identity=$(git -C "$A" config user.name) <$(git -C "$A" config user.email)>"
  echo "aibrain-personal: $(git -C "$P" rev-parse --short HEAD 2>/dev/null || echo not-a-repo) dirty=[$(git -C "$P" status --porcelain 2>/dev/null | tr '\n' ' ')] files=[$(cd "$P" 2>/dev/null && find . -type f -not -path './.git/*' | sort | tr '\n' ' ')]"
  echo "os agent: $(sed "s#$H#~#" "$H/.config/aibrain/os-agent-dir" 2>/dev/null)"
  echo "computer: $(cat "$H/.config/aibrain/computer" 2>/dev/null || echo unsaved)"
  echo "setup.sh ran: $(ls "$H/setup-ran" 2>/dev/null | tr '\n' ' ')"
  hook_state
}
hook_state() { # run the Stop hook exactly as the linked settings.json wires it, as this home's user
  local S="$H/.local/state/aibrain/sessions" cmd
  cmd="$(jq -r '.hooks.Stop[0].hooks[0].command // empty' "$H/.claude/settings.json" 2>/dev/null)"
  if [[ -n "$cmd" ]] && printf '{"session_id":"bootstrap-test"}' |
       env -i HOME="$H" PATH=/usr/local/bin:/usr/bin XDG_STATE_HOME="$H/.local/state" bash -c "$cmd" >/dev/null 2>&1 &&
       [[ -e "$S/bootstrap-test/idle" ]]; then
    echo "session-state hook: ok"
  else
    echo "session-state hook: FAIL"
  fi
  rm -rf "${S:?}/bootstrap-test"
  echo "session-state folder: $(stat -c %a "$S" 2>/dev/null || echo missing)"
  echo "managed settings: $(cmp -s "$H/Projects/aibrain/claude/managed-settings.json" /etc/claude-code/managed-settings.json && echo installed || echo differs)"
}
check_twice() {
  snap > "$H.snap1"; echo "--- run 2 (checkout)"; run 0 "$H/Projects/aibrain/bootstrap.sh" | grep -v '^==>' ; snap > "$H.snap2"
  if diff "$H.snap1" "$H.snap2"; then echo "IDEMPOTENT: yes"; else echo "IDEMPOTENT: NO"; fi
  if grep -qx 'session-state hook: ok' "$H.snap2" && grep -qx 'session-state folder: 700' "$H.snap2"; then
    echo "SESSION_STATE_HOOK: yes"
  else
    echo "SESSION_STATE_HOOK: NO"
  fi
  if grep -qx 'managed settings: installed' "$H.snap2"; then echo "MANAGED_SETTINGS: yes"; else echo "MANAGED_SETTINGS: NO"; fi
  if grep -qx '.claude/agents/contractor-sonnet.md -> ~/Projects/aibrain/claude/agents/contractor-sonnet.md' "$H.snap2"; then
    echo "AGENTS_LINKED: yes"
  else
    echo "AGENTS_LINKED: NO"
  fi
  # Check every skill folder and its reference files, including personal overrides.
  if python3 - "$H" <<'PY'
from pathlib import Path
import sys
home = Path(sys.argv[1])
skills = {}
for root in (home / 'Projects/aibrain', home / 'Projects/aibrain-personal'):
    for folder in (root / 'skills').glob('*/'):
        if folder.is_dir():
            assert (folder / 'SKILL.md').is_file(), folder
            skills[folder.name] = folder
destinations = [home / p for p in ('.agents/skills', '.claude/skills', '.codex/skills',
                                  '.pi/agent/skills', '.hermes/skills')]
destinations += list((home / '.hermes/profiles').glob('*/skills'))
for dest in destinations:
    for name, source in skills.items():
        linked = dest / name
        assert linked.is_symlink() and linked.resolve() == source.resolve(), linked
        for reference in source.rglob('*'):
            if reference.is_file():
                assert (linked / reference.relative_to(source)).is_file(), reference
PY
  then
    echo "SKILLS_LINKED: yes"
  else
    echo "SKILLS_LINKED: NO"; rc=1
  fi
  # The personal layer is linked and the privacy guard is on, and the committed files pass it
  if grep -qx '.claude/CLAUDE.md -> ~/Projects/aibrain-personal/AGENTS.md' "$H.snap2" &&
     grep -q '^aibrain git: hooks=.githooks identity=[^ ]* <[0-9]*+[^ ]*@users.noreply.github.com>$' "$H.snap2" &&
     (cd "$H/Projects/aibrain" && env -i HOME="$H" PATH=/usr/bin python3 -I privacy/scan.py tree HEAD); then
    echo "PERSONAL_AND_PRIVACY: yes"
  else
    echo "PERSONAL_AND_PRIVACY: NO"
  fi
}
show() { echo "--- end state"; cat "$H.snap2"; echo "--- backups"; (cd "$H/.local/state/aibrain" 2>/dev/null && find . -maxdepth 3 | sort | head -30); }

# --- Ubuntu: the script runs in an Ubuntu container with systemd, as a user with passwordless sudo, so its
# packages, apt repos, SSH server and services are the container's own. The engine is a bare copy of this
# checkout with HEAD as main. tailscale is a stub, so the container never joins your tailnet; the real
# package and tailscaled are still installed and started. The stub keeps its prefs in a state file, so up,
# set and logout change them, and logs each of those calls. It starts joined, accepting routes, with no
# operator, the way a join outside the script leaves Tailscale.
UBUNTU_DOCKERFILE='FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd systemd-sysv dbus sudo && rm -rf /var/lib/apt/lists/*
RUN (userdel -r ubuntu || true) && useradd -m -u 1000 -s /bin/bash user && echo "user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/00-test && chmod 440 /etc/sudoers.d/00-test
CMD ["/sbin/init"]'
TS_STUB='#!/bin/sh
# tailscale test stub: prefs in a state file; up, set and logout change them and are logged
d=/var/lib/tailscale-stub
. "$d/state"
cmd="$1"; shift
case "$cmd" in
  status) printf "{\"BackendState\":\"%s\"}\n" "$STATE" ;;
  debug)
    r=null; [ -z "$ROUTES" ] || r="[\"$(echo "$ROUTES" | sed "s/,/\",\"/g")\"]"
    printf "{\"OperatorUser\":\"%s\",\"RouteAll\":%s,\"AdvertiseRoutes\":%s,\"Hostname\":\"%s\"}\n" "$OPERATOR" "$ROUTEALL" "$r" "$HOST" ;;
  up|set|logout)
    [ "$(id -u)" = 0 ] || { echo "tailscale test stub: $cmd needs root" >&2; exit 1; }
    echo "$cmd $*" >> "$d/log"
    for a; do
      case "$a" in
        --reset) OPERATOR= ROUTEALL=false ROUTES= HOST= ;;
        --accept-routes) ROUTEALL=true ;;
        --accept-routes=*) ROUTEALL="${a#*=}" ;;
        --operator=*) OPERATOR="${a#*=}" ;;
        --advertise-routes=*) ROUTES="${a#*=}" ;;
        --hostname=*) HOST="${a#*=}" ;;
        --auth-key=*) cat >/dev/null ;;
      esac
    done
    case "$cmd" in up) STATE=Running ;; logout) STATE=NeedsLogin ;; esac
    printf "STATE=%s\nOPERATOR=%s\nROUTEALL=%s\nROUTES=%s\nHOST=%s\n" "$STATE" "$OPERATOR" "$ROUTEALL" "$ROUTES" "$HOST" > "$d/state" ;;
  *) echo "tailscale test stub: $cmd $*" >&2; exit 1 ;;
esac'
DOCKER=(docker); docker info >/dev/null 2>&1 || DOCKER=(sudo -n --preserve-env=OP_SERVICE_ACCOUNT_TOKEN docker)
CT=""
ubuntu_start() { # ubuntu_start <name>: a fresh container, $CT, with the engine and personal layer under /fixtures
  local image="aibrain-test-ubuntu:$(printf '%s' "$UBUNTU_DOCKERFILE" | sha256sum | cut -c1-12)"
  if ! "${DOCKER[@]}" image inspect "$image" >/dev/null 2>&1; then
    printf '%s\n' "$UBUNTU_DOCKERFILE" | "${DOCKER[@]}" build -q -t "$image" - >/dev/null || { echo "UBUNTU: couldn't build $image"; exit 1; }
  fi
  rm -rf "$ROOT/engine.git"; git clone -q --bare "$SRC" "$ROOT/engine.git"
  git -C "$ROOT/engine.git" update-ref refs/heads/main "$(git -C "$SRC" rev-parse HEAD)"
  git -C "$ROOT/engine.git" symbolic-ref HEAD refs/heads/main
  CT="aibrain-test-$1-$$"; trap '"${DOCKER[@]}" rm -f "$CT" >/dev/null 2>&1; rm -rf "$ROOT"' EXIT
  "${DOCKER[@]}" run -d --name "$CT" --privileged --cgroupns=private --tmpfs /run --tmpfs /run/lock \
    -v "$ROOT:/fixtures" "$image" >/dev/null || { echo "UBUNTU: couldn't start the container"; exit 1; }
  printf '%s\n' "$TS_STUB" | "${DOCKER[@]}" exec -i "$CT" sh -c 'cat > /usr/local/bin/tailscale && chmod 755 /usr/local/bin/tailscale &&
    mkdir -p /var/lib/tailscale-stub && printf "%s\n" STATE=Running OPERATOR= ROUTEALL=true ROUTES= HOST=old-name > /var/lib/tailscale-stub/state' ||
    { echo "UBUNTU: couldn't install the tailscale stub"; exit 1; }
  for _ in $(seq 60); do
    [[ "$("${DOCKER[@]}" exec "$CT" systemctl is-system-running 2>/dev/null)" =~ ^(running|degraded)$ ]] && return 0
    sleep 1
  done
  echo "UBUNTU: systemd didn't start in the container"; exit 1
}
urun() { # urun <with-env-token 0|1> <script> [VAR=value...]: run the script in the container as user, no tty
  local tok=() s="$2"; [[ $1 == 1 ]] && tok=(-e OP_SERVICE_ACCOUNT_TOKEN); shift 2
  local e=(); for v in "$@"; do e+=(-e "$v"); done
  "${DOCKER[@]}" exec -u user -w /home/user -e HOME=/home/user -e USER=user -e PATH=/usr/local/bin:/usr/bin:/bin \
    -e TERM=dumb -e AIBRAIN_REPO=/fixtures/engine.git -e AIBRAIN_PERSONAL_REPO=/fixtures/personal-fixture "${tok[@]}" "${e[@]}" \
    "$CT" setsid -w bash "$s" </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
  echo "[exit ${PIPESTATUS[0]}]"
}
usnap() { # the container's state: the user's files and links, and the system's packages, apt repos and services
  "${DOCKER[@]}" exec -u user -w /home/user -e HOME=/home/user "$CT" bash -c '
    cd ~ && sha256sum .bashrc .gitconfig .config/gh/hosts.yml .config/mise/config.toml .ssh/config .ssh/aibrain_fleet .ssh/authorized_keys 2>/dev/null
    stat -c "%a %n" .config/op .config/op/aiagent-token .ssh .ssh/aibrain_fleet 2>/dev/null
    echo "computer: $(cat .config/aibrain/computer 2>/dev/null || echo unsaved)"
    echo "hypr bindings: $(test -e .config/hypr/bindings.lua && echo present || echo none)"
    for d in .claude .claude/skills .claude/agents .agents/skills .codex .codex/skills .local/bin; do
      find "$d" -mindepth 1 -maxdepth 1 -type l -printf "$d/%f -> %l\n" 2>/dev/null | sort
    done
    echo "aibrain: $(git -C Projects/aibrain rev-parse --short HEAD) dirty=[$(git -C Projects/aibrain status --porcelain | tr "\n" " ")]"
    echo "aibrain-personal: $(git -C Projects/aibrain-personal rev-parse --short HEAD) dirty=[$(git -C Projects/aibrain-personal status --porcelain | tr "\n" " ")]"
    echo "mise tools: $(mise ls -g --current 2>/dev/null | awk "{print \$1}" | sort | tr "\n" " ")"
    echo "commands: $(. ~/.bashrc; for c in op gh codex claude mise python3 jq; do command -v $c >/dev/null && printf "%s " $c; done)"
    dpkg-query -W -f "\${Package} \${db:Status-Status}\n" ca-certificates curl gpg git jq python3 1password-cli mise tailscale openssh-server 2>&1
    sudo sha256sum /etc/sudoers.d/zz-aibrain /etc/ssh/sshd_config.d/50-aibrain.conf /etc/apt/sources.list.d/aibrain-* /etc/apt/keyrings/aibrain-* 2>&1
    echo "managed settings: $(test -e /etc/claude-code/managed-settings.json && echo present || echo none)"
    for u in ssh.service ssh.socket tailscaled.service; do echo "$u: $(systemctl is-enabled $u 2>/dev/null) $(systemctl is-active $u 2>/dev/null)"; done
    echo "session-state folder: $(stat -c %a .local/state/aibrain/sessions 2>/dev/null || echo missing)"
    echo "tailscale: $(tailscale status | jq -r .BackendState)"
    echo "tailscale prefs: $(tailscale debug prefs | jq -r "[.OperatorUser, .RouteAll, ((.AdvertiseRoutes // []) | join(\",\")), .Hostname] | map(tostring) | join(\"|\")")"'
}
ucheck_twice() { # ucheck_twice <snap file prefix>: run the checkout's copy again and compare
  usnap > "$1.snap1"; echo "--- run 2 (checkout)"; urun 0 /home/user/Projects/aibrain/bootstrap.sh | grep -v '^==>'; usnap > "$1.snap2"
  if diff "$1.snap1" "$1.snap2"; then echo "IDEMPOTENT: yes"; else echo "IDEMPOTENT: NO"; fi
}

if [[ "${1:-}" != ubuntu* && "${1:-}" != all ]]; then
  HOST_BEFORE="$(host_state)"
  trap 'host_check || rc=1; rm -rf "$ROOT"; exit "${rc:-0}"' EXIT
fi
if [[ "${1:-}" == all ]]; then
  HOST_BEFORE="$(host_state)"; rc=0
  echo "######## labels"; python3 -I "$SRC/tests/labels-test.py" || rc=1
  for s in fresh bashrc-migrate no-personal migrate projects-junk full unknown-key-binding picks computers worktrees ubuntu ubuntu-claude; do
    echo "######## $s"; "$0" "$s" || rc=1
  done
  echo "######## all"; host_check || rc=1; exit "$rc"
fi
case "${1:-}" in
bashrc-migrate)
  # Both the previous managed block and older loose token lines must converge.
  mkhome bashrc-migrate
  cat >> "$H/.bashrc" <<'EOF'

# 1Password service account for AI agents
[[ -r ~/.config/op/aiagent-token ]] && export OP_SERVICE_ACCOUNT_TOKEN="$(< ~/.config/op/aiagent-token)"

# >>> aibrain >>>
# 1Password service account for AI agents (vault: aiagents). Managed by ~/Projects/aibrain/bootstrap.sh.
[[ -r ~/.config/op/aiagent-token ]] && export OP_SERVICE_ACCOUNT_TOKEN="$(< ~/.config/op/aiagent-token)"
# <<< aibrain <<<
# Keep this user line.
EOF
  echo "--- run 1 (old bashrc block and loose lines)"; run 1 "$ROOT/pasted.sh"
  cp "$H/.bashrc" "$H.bashrc1"
  check_twice; show
  comment="# A launcher that sets AIBRAIN_NO_VAULT=1 keeps the token out of an agent's shells."
  token_line='if [[ -n ${AIBRAIN_NO_VAULT:-} ]]; then unset OP_SERVICE_ACCOUNT_TOKEN; elif [[ -r ~/.config/op/aiagent-token ]]; then export OP_SERVICE_ACCOUNT_TOKEN="$(< ~/.config/op/aiagent-token)"; fi'
  if cmp -s "$H.bashrc1" "$H/.bashrc" &&
     [[ "$(grep -Fxc '# >>> aibrain >>>' "$H/.bashrc")" == 1 ]] &&
     [[ "$(grep -Fxc '# <<< aibrain <<<' "$H/.bashrc")" == 1 ]] &&
     [[ "$(grep -Fxc "$comment" "$H/.bashrc")" == 1 ]] &&
     [[ "$(grep -Fxc "$token_line" "$H/.bashrc")" == 1 ]] &&
     [[ "$(grep -c 'aiagent-token' "$H/.bashrc")" == 1 ]] &&
     grep -Fxq '# Keep this user line.' "$H/.bashrc"; then
    echo "BASHRC_MIGRATED: yes"
  else
    echo "BASHRC_MIGRATED: NO"; rc=1; exit 1
  fi
  ;;
fresh)
  mkhome fresh; echo '{"theme":"light"}' > "$H/.claude/settings.json"
  echo "--- run 1 (pasted, agent token)"; run 1 "$ROOT/pasted.sh"; check_twice; show
  echo "--- bashrc block"; grep -n -A3 '>>> aibrain' "$H/.bashrc"
  echo "--- ssh config"; cat "$H/.ssh/config"
  echo "--- hypr bindings"; cat "$H/.config/hypr/bindings.lua"
  if [[ -L "$H/.claude/skills/fixture-skill" ]]; then echo "PERSONAL_SKILL: yes"; else echo "PERSONAL_SKILL: NO"; fi
  if [[ -L "$H/.claude/agents/fixture-agent.md" ]]; then echo "PERSONAL_AGENT: yes"; else echo "PERSONAL_AGENT: NO"; fi
  ;;
no-personal)
  # No personal layer anywhere: the script makes one from personal.example, and links it
  mkhome no-personal; PERSONAL_REPO=none
  echo "--- run 1 (pasted, agent token, no personal layer)"; run 1 "$ROOT/pasted.sh"; check_twice; show
  # Settings off by default: no keyboard filter
  if grep -q 'aibrain-agent' "$H/.config/hypr/bindings.lua" && ! grep -q 'code:248' "$H/.config/hypr/bindings.lua"; then
    echo "DEFAULTS: yes"
  else
    echo "DEFAULTS: NO"
  fi
  ;;
migrate)
  # A computer set up before the personal layer existed: ~/Projects/aibrain holds other history and an
  # uncommitted edit.
  # It's saved and replaced by a clone, the personal layer is cloned, and the old links are replaced.
  mkhome migrate; oldsplit
  echo "--- run 1 (pasted)"; run 0 "$ROOT/pasted.sh"; check_twice; show
  if [[ "$(head -n 1 "$H/.ssh/config")" == 'Include ~/Projects/aibrain-personal/ssh/config' ]] &&
     ! grep -qx 'Include ~/Projects/aibrain/ssh/config' "$H/.ssh/config" && grep -qx 'Host old-box' "$H/.ssh/config" &&
     grep -qx '# uncommitted' "$H/.local/state/aibrain"/backup-*/Projects/aibrain/AGENTS.md; then
    echo "MIGRATED: yes"
  else
    echo "MIGRATED: NO"; cat "$H/.ssh/config"
  fi
  ;;
projects-junk)
  mkhome projects-junk; mkdir -p "$H/Projects/aibrain"; echo junk > "$H/Projects/aibrain/notes.txt"
  echo "--- run 1"; run 1 "$ROOT/pasted.sh"; check_twice; show
  ;;
full)
  # A full setup chosen through AIBRAIN_SETUP, which is saved, so the second run is full without it.
  # It uses your own personal layer, so its denylist checks this repo too. AIBRAIN_REPOS_ONLY keeps
  # the clone to the one small repo its config.sh names.
  test_repo="$(git -C "$REAL_PERSONAL" show HEAD:config.sh 2>/dev/null | bash -c 'source /dev/stdin >/dev/null 2>&1; echo "${TEST_REPO:-}"')"
  if [[ -z "$test_repo" ]]; then echo "SKIPPED: no TEST_REPO in $REAL_PERSONAL/config.sh"; exit 0; fi
  mkhome full; git clone -q --bare "$REAL_PERSONAL" "$ROOT/personal-copy.git"; PERSONAL_REPO="$ROOT/personal-copy.git"
  EXTRA_ENV=(AIBRAIN_SETUP=full AIBRAIN_REPOS_ONLY="$test_repo")
  echo "--- run 1 (pasted, agent token, full)"; run 1 "$ROOT/pasted.sh"
  EXTRA_ENV=(AIBRAIN_REPOS_ONLY="$test_repo"); check_twice; show
  if [[ -d "$H/Projects/$test_repo/.git" ]]; then echo "FULL_CLONE: yes"; else echo "FULL_CLONE: NO"; fi
  ;;
unknown-key-binding)
  # Replace an older managed block containing a filter with incomplete flags.
  # Keep the user's own bindings and ensure a second bootstrap adds no duplicate. The filter is
  # test-box's setting, so the first run names the computer; the second finds the saved name.
  mkhome unknown-key-binding; EXTRA_ENV=(AIBRAIN_COMPUTER=test-box)
  cat >> "$H/.config/hypr/bindings.lua" <<'EOF'

-- >>> aibrain >>>
hl.bind("code:248", function() end, { ignore_mods = false })
-- <<< aibrain <<<
EOF
  echo "--- run 1 (existing unsupported-key filter)"; run 1 "$ROOT/pasted.sh"
  binding='hl.bind("code:248", function() end, { locked = true, ignore_mods = true, dont_inhibit = true, submap_universal = true, description = "Ignore unsupported key reports" })'
  if [[ "$(grep -Fc "$binding" "$H/.config/hypr/bindings.lua")" == 1 ]] &&
     ! grep -Fq 'ignore_mods = false' "$H/.config/hypr/bindings.lua" &&
     grep -Fq 'o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh x")' "$H/.config/hypr/bindings.lua"; then
    echo "UNKNOWN_KEY_FILTER: yes"
  else
    echo "UNKNOWN_KEY_FILTER: NO"; rc=1; exit 1
  fi
  EXTRA_ENV=(); check_twice; show
  ;;
picks)
  # Model and effort picks saved by Claude Code's pickers are put back, not stashed; other edits are stashed.
  mkhome picks
  echo "--- run 1 (pasted, agent token)"; run 1 "$ROOT/pasted.sh"
  A="$H/Projects/aibrain"
  python3 -I - "$A/claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s["model"] = "fable"; s["modelSettings"] = {"claude-opus-5-5": {"effortLevel": "xhigh"}, "claude-fable-5-1": {"effortLevel": "high"}}
json.dump(dict(reversed(list(s.items()))), open(p, "w"), indent=2)  # reordered, as Claude Code writes it
PY
  echo "--- run 2 (checkout, after picks)"; run 0 "$A/bootstrap.sh" | grep -v '^==>'
  if [[ -z "$(git -C "$A" status --porcelain)" && "$(git -C "$A" stash list | wc -l)" == 0 ]]; then
    echo "PICKS_DROPPED: yes"
  else
    echo "PICKS_DROPPED: NO"; git -C "$A" status --short; git -C "$A" stash list
  fi
  check_twice; show
  ;;
worktrees)
  # Claude Code's session worktrees under .claude/worktrees/ in either checkout are never local changes, so
  # they're never stashed, also in a checkout from before the script excluded them.
  mkhome worktrees; A="$H/Projects/aibrain" P="$H/Projects/aibrain-personal"
  echo "--- run 1 (pasted, agent token)"; run 1 "$ROOT/pasted.sh" | grep -v '^==>'
  for c in "$A" "$P"; do
    sed -i '\#^/\.claude/worktrees/$#d' "$c/.git/info/exclude"
    git -C "$c" worktree add -q -b session-test "$c/.claude/worktrees/session-test"
    echo "a session's edit" >> "$c/.claude/worktrees/session-test/README.md"
  done
  echo "--- run 2 (checkout, with a session worktree in each checkout)"; run 0 "$A/bootstrap.sh" | grep -v '^==>' | tee "$H.run2"
  check_twice | tee "$H.run3"; ok=1
  for c in "$A" "$P"; do
    if [[ -n "$(git -C "$c" status --porcelain)" || -n "$(git -C "$c" stash list)" ]] ||
       [[ "$(grep -c '^/\.claude/worktrees/$' "$c/.git/info/exclude")" != 1 ]] ||
       ! grep -qx "a session's edit" "$c/.claude/worktrees/session-test/README.md"; then
      ok=0; echo "$c:"; git -C "$c" status --short; git -C "$c" stash list
    fi
  done
  ! grep -qiE 'stashed|Ignoring path' "$H.run2" "$H.run3" || { ok=0; grep -hiE 'stashed|Ignoring path' "$H.run2" "$H.run3"; }
  if ((ok)); then echo "WORKTREES_NOT_STASHED: yes"; else echo "WORKTREES_NOT_STASHED: NO"; fi
  ;;
computers)
  # Every computer has a folder in the personal layer, computers/<name>/. With no terminal and no name,
  # the computer is the hostname, unsaved, with a warning, and only the layer's setup.sh runs.
  # AIBRAIN_COMPUTER names it and is saved, so its config.sh and setup.sh apply on later runs without it.
  # A new name gets a folder, committed and pushed once. (The questions asked in a terminal can't be
  # tested here.)
  mkhome computers; ok=1; B="$H/.config/hypr/bindings.lua" C="$H/.config/aibrain/computer"
  head0="$(git -C "$FIXTURE" rev-parse HEAD)"
  echo "--- run 1 (pasted, agent token, no name)"; run 1 "$ROOT/pasted.sh" | grep -v '^==>' | tee "$H.run1"
  if [[ -e "$C" ]] || grep -q code:248 "$B" || [[ "$(ls "$H/setup-ran" | tr '\n' ' ')" != "every-computer " ]] ||
     ! grep -q 'has no name in the personal layer yet' "$H.run1"; then
    ok=0; echo "unnamed: wrong"
  fi
  EXTRA_ENV=(AIBRAIN_COMPUTER=test-box)
  echo "--- run 2 (checkout, AIBRAIN_COMPUTER=test-box)"; run 0 "$H/Projects/aibrain/bootstrap.sh" | grep -v '^==>'
  if [[ "$(cat "$C")" != test-box ]] || ! grep -q code:248 "$B" ||
     [[ "$(cat "$H/setup-ran/test-box")" != "test-box $H/Projects/aibrain-personal" ]]; then
    ok=0; echo "named: wrong"
  fi
  EXTRA_ENV=(); check_twice
  grep -q code:248 "$B" || { ok=0; echo "saved name: wrong"; }
  [[ "$(git -C "$FIXTURE" rev-parse HEAD)" == "$head0" ]] || { ok=0; echo "existing computer: pushed a commit"; }
  EXTRA_ENV=(AIBRAIN_COMPUTER=new-box)
  echo "--- run (AIBRAIN_COMPUTER=new-box, a new computer)"; run 0 "$H/Projects/aibrain/bootstrap.sh" | grep -v '^==>'
  head1="$(git -C "$FIXTURE" rev-parse HEAD)"
  if [[ "$(cat "$C")" != new-box ]] || grep -q code:248 "$B" ||
     [[ "$(git -C "$FIXTURE" log -1 --format=%s)" != "computers/new-box: a new computer" ]] ||
     [[ "$(git -C "$FIXTURE" show HEAD:computers/new-box/config.sh | head -n 1)" != "# new-box: "*", added "* ]]; then
    ok=0; echo "new computer: wrong"
  fi
  EXTRA_ENV=()
  echo "--- run (saved new-box)"; run 0 "$H/Projects/aibrain/bootstrap.sh" | grep -v '^==>'
  [[ "$(git -C "$FIXTURE" rev-parse HEAD)" == "$head1" ]] || { ok=0; echo "new computer: pushed again"; }
  if ((ok)); then echo "COMPUTERS: yes"; else echo "COMPUTERS: NO"; fi
  show
  ;;
ubuntu)
  # A fresh Ubuntu 24.04 server set up as a headless, Codex-only computer (HEADLESS=1, CODEX_ONLY=1)
  ubuntu_start ubuntu; U="$ROOT/ubuntu"
  echo "--- run 1 (pasted, agent token, AIBRAIN_COMPUTER=ubuntu-box)"; urun 1 /fixtures/pasted.sh AIBRAIN_COMPUTER=ubuntu-box | grep -v '^==>'
  ucheck_twice "$U"; echo "--- end state"; cat "$U.snap2"
  s="$(cat "$U.snap2")"
  # TS_ACCEPT_ROUTES=0 turns off the routes an earlier join accepted
  if [[ "$s" == *"tailscale prefs: user|false||old-name"* ]]; then echo "UBUNTU_NO_ROUTES: yes"; else echo "UBUNTU_NO_ROUTES: NO"; fi
  if [[ "$s" == *"computer: ubuntu-box"* && "$s" == *"commands: op gh codex mise python3 jq "* &&
        "$s" != *"claude "* && "$s" == *"managed settings: none"* && "$s" == *"hypr bindings: none"* &&
        "$s" == *"session-state folder: missing"* && "$s" == *"tailscaled.service: enabled active"* &&
        "$s" =~ ssh\.(service|socket):\ enabled\ active && "$s" == *"1password-cli installed"* && "$s" == *"mise installed"* &&
        "$s" == *".codex/AGENTS.md -> /home/user/Projects/aibrain-personal/AGENTS.md"* ]]; then
    echo "UBUNTU_HEADLESS_CODEX: yes"
  else
    echo "UBUNTU_HEADLESS_CODEX: NO"
  fi
  if "${DOCKER[@]}" exec -u user "$CT" bash -c 'cd /home/user/Projects/aibrain && env -i HOME=/home/user PATH=/usr/bin python3 -I privacy/scan.py tree HEAD' >/dev/null; then
    echo "PRIVACY_SCAN: yes"
  else
    echo "PRIVACY_SCAN: NO"
  fi
  # A first join, in a terminal: it doesn't accept routes, not even before a later set
  echo "--- run 3 (checkout, in a terminal, after tailscale logout)"
  "${DOCKER[@]}" exec "$CT" sh -c 'tailscale logout && : > /var/lib/tailscale-stub/log'
  printf '%s\n' 'exec script -qec "bash $HOME/Projects/aibrain/bootstrap.sh" /dev/null' > "$ROOT/in-terminal.sh"
  urun 0 /fixtures/in-terminal.sh AIBRAIN_SETUP=light | tr -d '\r' | grep -v '^==>'
  log="$("${DOCKER[@]}" exec "$CT" cat /var/lib/tailscale-stub/log)"; echo "--- tailscale calls"; echo "$log"
  ucheck_twice "$U.join"; s="$(cat "$U.join.snap2")"
  if [[ "$log" == "up --reset --accept-routes=false --operator=user --hostname=old-name" &&
        "$s" == *"tailscale: Running"* && "$s" == *"tailscale prefs: user|false||old-name"* ]]; then
    echo "UBUNTU_JOIN_NO_ROUTES: yes"
  else
    echo "UBUNTU_JOIN_NO_ROUTES: NO"; cat "$U.join.snap2"
  fi
  ;;
ubuntu-claude)
  # Ubuntu 24.04 with every default: Claude Code and its managed settings. Then the same computer turns
  # Codex-only, which removes Claude Code, and a further run changes nothing.
  ubuntu_start ubuntu-claude; U="$ROOT/ubuntu-claude"
  echo "--- run 1 (pasted, agent token, AIBRAIN_COMPUTER=ubuntu-claude-box)"; urun 1 /fixtures/pasted.sh AIBRAIN_COMPUTER=ubuntu-claude-box | grep -v '^==>'
  ucheck_twice "$U"; s="$(cat "$U.snap2")"
  if [[ "$s" == *"commands: op gh codex claude mise"* && "$s" == *"managed settings: present"* &&
        "$s" == *"session-state folder: 700"* && "$s" == *"hypr bindings: none"* && "$s" == *"tailscale prefs: user|true||old-name"* ]]; then
    echo "UBUNTU_CLAUDE: yes"
  else
    echo "UBUNTU_CLAUDE: NO"; cat "$U.snap2"
  fi
  echo "--- run 3 (checkout, AIBRAIN_COMPUTER=ubuntu-box: Codex-only now)"
  urun 0 /home/user/Projects/aibrain/bootstrap.sh AIBRAIN_COMPUTER=ubuntu-box | grep -v '^==>'
  ucheck_twice "$U.codex"; s="$(cat "$U.codex.snap2")"
  if [[ "$s" == *"commands: op gh codex mise"* && "$s" != *"claude "* && "$s" == *"managed settings: none"* &&
        "$s" == *"tailscale prefs: user|false||old-name"* ]]; then
    echo "UBUNTU_TO_CODEX_ONLY: yes"
  else
    echo "UBUNTU_TO_CODEX_ONLY: NO"; cat "$U.codex.snap2"
  fi
  ;;
*) echo "Usage: $0 fresh|bashrc-migrate|no-personal|migrate|projects-junk|full|unknown-key-binding|picks|computers|worktrees|ubuntu|ubuntu-claude|all" >&2; rc=1; exit 2 ;;
esac
