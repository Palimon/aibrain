#!/usr/bin/env bash
# Unit tests for claude/hooks/sign-in-handoff.py: feed it Stop events with made-up final messages and
# check which ones it blocks.
# Usage: tests/sign-in-handoff-test.sh
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/claude/hooks/sign-in-handoff.py"
fails=0

ev() { # ev <message> [active]: run the hook on a Stop event with that final message, print its stdout
  jq -nc --arg m "$1" --argjson a "${2:-false}" '{hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}' |
    python3 -I "$HOOK"
}
check() { # check <block|allow> <name> <message> [active]
  local out; out="$(ev "$3" "${4:-false}")"
  if [[ $1 == block && $out == *'"decision": "block"'* ]] || [[ $1 == allow && -z $out ]]; then
    echo "ok   $2"
  else
    echo "FAIL $2 (wanted $1): ${out:-allowed}"; fails=$((fails + 1))
  fi
}

check block "on a computer, run a sign-in script"   '2. **ChatGPT sign-in.** On the build box, run `~/Projects/gateway/sign-in.sh`. Until then it falls back.'
check block "log in as a user and run"               '1. Sign in to ChatGPT: log in as alice and run `/opt/gateway/sign-in.sh`, then tell me.'
check block "ssh -t to a sign-in"                    'Run `ssh -t devbox /opt/gateway/sign-in.sh` from your laptop, then tell me when it is done.'
check block "a bare command line"                    $'One step for you:\n\n    ssh -t devbox ~/tools/chatgpt-login.sh\n'
check block "gh auth login at a desktop"             '3. At its desktop, run `gh auth login -h github.com`.'
check block "tailscale up"                           'Then run `sudo tailscale up` on the new server and open the link it prints.'
check block "until you run"                          'It stays open until you run `scripts/chatgpt-login.sh` on both servers.'
check block "either run"                             'Either run `~/gateway/sign-in.sh` on the server, or add funds.'
check block "you will need to run"                   'If the refresh fails, you will need to run `~/gateway/sign-in.sh` there.'
check block "codex login --device-auth"              '- Run `codex login --device-auth` on the server.'
check allow "after one block"                        '3. At its desktop, run `gh auth login -h github.com`.' true
check allow "the agent ran it"                       'I ran `~/gateway/sign-in.sh` on the server over ssh; its check passed.'
check allow "the agent runs it next"                 'I will run `ssh devbox ~/gateway/sign-in.sh` in the background next.'
check allow "the remote sign-in from here"           'Run `~/gateway/remote-sign-in.sh devbox` in the background; it prints the code.'
check allow "only the address and code"              'Open https://auth.example.com/device on any device and enter the code ABCD-1234 within 15 minutes.'
check allow "prose about a login"                    'You do three browser steps: the Codex login, the Tailscale login and the GitHub one.'
check allow "no sign-in at all"                      $'1. Run `make test`.\n2. Merge the branch.'
check allow "an empty message"                       ''
if [[ -n "$(printf 'not json' | python3 -I "$HOOK")" ]]; then echo "FAIL bad input prints something"; fails=$((fails + 1)); else echo "ok   bad input allowed"; fi

if (( fails )); then echo "$fails failed"; exit 1; fi
echo "all passed"
