#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034 # hostile strings are literal on purpose; vars are used by run.sh
# Shared harness for the action smoke tests.
#
# Extracts every `run:` block from action.yml, then executes them with the
# system /bin/bash (3.2 on macOS) against a stub Flare API and a stub `gh`, so
# tests exercise exactly the shipped script on both GNU and BSD userlands.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/flare-action-test.XXXXXX")
PY=${PYTHON:-python3}
BASH_UNDER_TEST=${BASH_UNDER_TEST:-/bin/bash}
PWNED_MARKER=/tmp/flare-pwned
HOSTILE='a";touch${IFS}/tmp/flare-pwned;echo"$(touch /tmp/flare-pwned)`touch /tmp/flare-pwned`'
FAILS=0

export RUNNER_TEMP="$WORK" GH_LOG="$WORK/gh.log" GH_BODY="$WORK/gh-body" GH_TOKEN=test-gh-token
rm -f "$PWNED_MARKER"

"$PY" - "$ROOT/action.yml" "$WORK/step" <<'PY'
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
for i, step in enumerate(steps):
    if "${{" in step.get("run", ""):
        sys.exit(f"step {i} interpolates an expression into run:")
    open(f"{sys.argv[2]}-{i}.sh", "w").write(step.get("run", ""))
PY
EXTRACT_RC=$?
[ "$EXTRACT_RC" -eq 0 ] || { echo "FAIL: could not extract run blocks"; exit 1; }

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'SH'
#!/bin/bash
echo "gh $*" >> "$GH_LOG"
prev=""
for a in "$@"; do
  case "$a" in body=*) printf '%s' "${a#body=}" > "$GH_BODY" ;; esac
  [ "$prev" = "--body" ] && printf '%s' "$a" > "$GH_BODY"
  prev=$a
done
case "$*" in
  *--paginate*) [ -n "${GH_EXISTING:-}" ] && printf '%s\n' $GH_EXISTING ;;
  "issue create"*) echo "https://github.com/o/r/issues/1" ;;
esac
exit 0
SH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

PORT=$((20000 + RANDOM % 20000))
"$PY" "$ROOT/test/stub_server.py" "$PORT" "$WORK/stub.log" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break
  sleep 0.25
done
API="http://127.0.0.1:$PORT"

# run_step <index> [VAR=value ...] -- runs step <index> with a fresh GITHUB_OUTPUT.
run_step() {
  local index=$1; shift
  : > "$WORK/output"
  env GITHUB_OUTPUT="$WORK/output" "$@" "$BASH_UNDER_TEST" "$WORK/step-$index.sh" > "$WORK/stdout" 2>&1
  RC=$?
}

output() { sed -n "s/^$1=//p" "$WORK/output" | tail -1; }
last_request() { tail -1 "$WORK/stub.log"; }

check() { # check <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: expected [$3], got [$2]"
    sed 's/^/       | /' "$WORK/stdout"
    FAILS=$((FAILS + 1))
  fi
}

finish() {
  check "no injected command ran" "$([ -e "$PWNED_MARKER" ] && echo yes || echo no)" "no"
  if [ "$FAILS" -gt 0 ]; then
    echo "$FAILS check(s) failed"
    exit 1
  fi
  echo "all checks passed"
}
