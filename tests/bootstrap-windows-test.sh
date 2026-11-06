#!/bin/bash
# The Windows counterpart of bootstrap-test.sh, for a Windows computer that's set up already: bootstrap.sh
# has run once in a terminal there, so the aiagent token and the managed settings are in place.
# A throwaway home can't work on Windows, because winget, Program Files and Claude Code's installer act on
# the real computer whatever HOME says. So this runs the last commit's bootstrap.sh on this computer, twice,
# as the checkout's copy (AIBRAIN_RERUN, so ~/Projects/aibrain itself is left as it is). It checks that both
# runs succeed, that the second changes nothing, and that the links, the session-state hook, Codex, the
# ChatGPT app, the SSH server and Tailscale work.
# Usage: tests/bootstrap-windows-test.sh
set -uo pipefail
[[ "$(uname -s)" == MINGW* ]] || { echo "This test runs on Windows, in Git Bash." >&2; exit 2; }
SRC="$(cd "$(dirname "$0")/.." && pwd)"   # this checkout, holding the commit under test
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
git -C "$SRC" show HEAD:bootstrap.sh > "$T/bootstrap.sh"
fails=0
check() { # check <name> <condition...>
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
run() { # run <n>: run the script without a terminal, keeping its output in $T/run<n>
  AIBRAIN_RERUN=1 bash "$T/bootstrap.sh" </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$T/run$1"
  echo "[exit ${PIPESTATUS[0]}]" >> "$T/run$1"
}
LINK_DIRS=(.claude .claude/skills .claude/agents .agents/skills .codex .codex/skills .grok .grok/skills .local/bin)
snap() { # what a second run must leave as it was
  (
    cd ~ || exit 1
    sha256sum .bashrc .gitconfig .ssh/config .ssh/aibrain_fleet .ssh/aibrain_fleet.pub .ssh/authorized_keys .config/aibrain/* 2>&1
    echo "managed settings: $(cmp -s Projects/aibrain/claude/managed-settings.json "/c/Program Files/ClaudeCode/managed-settings.json" && echo installed || echo differs)"
    echo "trusted by Claude: $(jq -r '(.projects // {}) | to_entries[] | select(.value.hasTrustDialogAccepted == true) | .key' .claude.json | tr -d '\r' | sort | tr '\n' ' ')"
    for d in "${LINK_DIRS[@]}"; do find "$d" -mindepth 1 -maxdepth 1 -type l -printf "$d/%f -> %l\n" 2>/dev/null | sort; done
    for r in aibrain aibrain-personal; do
      echo "$r: $(git -C "Projects/$r" rev-parse --short HEAD) dirty=[$(git -C "Projects/$r" status --porcelain | tr '\n' ' ')] stashes=$(git -C "Projects/$r" stash list | wc -l)"
    done
  )
}
hook_ok() { # the Stop hook, run exactly as the linked settings.json wires it
  local S="$T/sessions" cmd
  cmd="$(jq -r '.hooks.Stop[0].hooks[0].command // empty' ~/.claude/settings.json | tr -d '\r')"
  [[ -n "$cmd" ]] && printf '{"session_id":"bootstrap-test"}' | AIBRAIN_SESSION_STATE="$(cygpath -m "$S")" bash -c "$cmd" >/dev/null 2>&1 &&
    [[ -e "$S/bootstrap-test/idle" ]]
}

echo "--- run 1"; run 1; cat "$T/run1"; snap > "$T/snap1"
echo "--- run 2"; run 2; cat "$T/run2"; snap > "$T/snap2"
check "run 1 succeeds" grep -qx '\[exit 0\]' "$T/run1"
check "run 2 succeeds" grep -qx '\[exit 0\]' "$T/run2"
check "run 2 changes nothing" diff "$T/snap1" "$T/snap2"
check "run 2 installs and replaces nothing" bash -c '! grep -E "^==> (Installing|Setting|Adding|Logging|Making)|Files this run replaced" "$1"' _ "$T/run2"
check "python3 is winget's Python" bash -c '[[ "$(command -v python3)" == */Programs/Python/Python3*/python3 ]]'
check "managed settings installed" grep -qx 'managed settings: installed' "$T/snap2"
check "links are real and resolve" bash -c 'cd ~ && [[ -L .claude/settings.json && -z "$(find "$@" -mindepth 1 -maxdepth 1 -xtype l 2>/dev/null)" ]]' _ "${LINK_DIRS[@]}"
check "grab-issue skill linked for every tool" bash -c 'for d in .agents .claude .codex .grok; do test -f ~/$d/skills/grab-issue/SKILL.md || exit 1; done'
check "the checkout's own links are links" test -L "$HOME/Projects/aibrain/.claude/skills/webapp-testing"
check "session-state hook runs" hook_ok
# A new terminal's PATH comes from the registry, not from the runs above
check "codex runs in a new terminal" powershell.exe -NoProfile -Command '$env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine"); codex --version | Out-Null; exit $LASTEXITCODE'
check "the ChatGPT app is installed" powershell.exe -NoProfile -Command 'if (-not (Get-AppxPackage -Name OpenAI.Codex)) { exit 1 }'
login() { # login <ssh> <ssh options>...: log in to this computer over SSH; ssh's errors on stdout
  local ssh="$1"; shift
  "$ssh" -F /dev/null -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR "$@" "${USER:-$USERNAME}@localhost" true 2>&1
}
# Both clients: Git Bash's, which agents use, and Windows' own, which reads keys more leniently
for c in /usr/bin/ssh /c/Windows/System32/OpenSSH/ssh.exe; do
  check "the SSH server takes the fleet key from $c" login "$c" -i "$HOME/.ssh/aibrain_fleet" -o IdentitiesOnly=yes
done
check "the SSH server takes no passwords" bash -c '[[ "$1" == *"Permission denied (publickey)"* ]]' _ "$(login /usr/bin/ssh -o PubkeyAuthentication=no)"
check "on the tailnet" bash -c '[[ "$("/c/Program Files/Tailscale/tailscale.exe" status --json | jq -r .BackendState | tr -d "\r")" == Running ]]'

echo
if (( fails )); then echo "$fails FAILED"; exit 1; fi
echo "all passed"
