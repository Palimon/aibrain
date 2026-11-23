#!/usr/bin/env bash
# Unit tests for bootstrap.sh's codex_rpc: run it under set -u against fake `codex` programs, one that
# answers the JSON-RPC requests and some that end at once, as a codex that can't start does.
# Usage: tests/codex-rpc-test.sh
set -u
BOOTSTRAP="$(cd "$(dirname "$0")/.." && pwd)/bootstrap.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
sed -n '/^codex_rpc() {/,/^}/p' "$BOOTSTRAP" > "$W/codex_rpc.sh"
[[ -s "$W/codex_rpc.sh" ]] || { echo "FAIL: no codex_rpc in bootstrap.sh"; exit 1; }
fails=0

fake() { # fake <name> <body>: a fake codex in $W/<name>/codex
  mkdir -p "$W/$1"; printf '#!/usr/bin/env bash\n%s\n' "$2" > "$W/$1/codex"; chmod +x "$W/$1/codex"
}
fake answers 'while IFS= read -r l; do id="$(jq -r ".id // empty" <<< "$l")"; [[ -z $id ]] || jq -nc --argjson id "$id" "{id: \$id, result: {n: \$id}}"; done'
fake exits 'exit 1'
fake missing 'exit 127'

run() { # run <fake> <requests>...: codex_rpc's output, exit code and errors, in $W/out, $W/rc and $W/err
  PATH="$W/$1:$PATH" bash -c 'set -euo pipefail; source "$0"; codex_rpc "$@"' "$W/codex_rpc.sh" "${@:2}" \
    > "$W/out.raw" 2> "$W/err"
  echo $? > "$W/rc"
  tr -d '\r' < "$W/out.raw" > "$W/out"   # jq on Windows ends its lines with CRLF
}
check() { # check <name> <test>
  if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; echo "  out: $(cat "$W/out")"; echo "  err: $(cat "$W/err")"; fails=$((fails + 1)); fi
}

run answers '{"method":"a"}' '{"method":"b"}'
check 'a working app-server prints each result' '[[ $(cat "$W/rc") == 0 && $(cat "$W/out") == $'"'"'{"n":1}\n{"n":2}'"'"' ]]'

for f in exits missing; do
  for i in $(seq 10); do
    run "$f" '{"method":"a"}'
    check "an app-server that ends at once ($f, run $i) fails without a bash error" \
      '[[ $(cat "$W/rc") != 0 && ! -s "$W/out" && ! -s "$W/err" ]]'
  done
done

((fails == 0)) && echo "All codex_rpc tests passed." || { echo "$fails codex_rpc test(s) failed."; exit 1; }
