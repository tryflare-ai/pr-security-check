#!/usr/bin/env bash
# shellcheck disable=SC2016 # hostile strings are literal on purpose
# shellcheck source=test/lib.sh
# Smoke tests for action.yml. Usage: bash test/run.sh
. "$(dirname "$0")/lib.sh"

# Fixture repository: one base commit, one head commit touching IaC files.
REPO_DIR="$WORK/repo"
mkdir -p "$REPO_DIR/iam" && cd "$REPO_DIR" || exit 1
git init -q && git config user.email t@example.com && git config user.name test
echo base > README && git add . && git commit -qm base
BASE=$(git rev-parse HEAD)
printf '{"Action":"*"}\n' > iam/admin-policy.json
echo 'acl = "public-read"' > main.tf
echo docs > "notes with spaces.txt"
git add . && git commit -qm head
HEAD_SHA=$(git rev-parse HEAD)

pr() { # pr <token> [VAR=value ...]
  local token=$1; shift
  run_step 0 FLARE_TOKEN="$token" FLARE_API_URL="$API/api/webhooks/pr-check" \
    FLARE_PATHS="${PATHS-}" FLARE_FAIL_ON="${FAIL_ON:-critical}" FLARE_COMMENT=true \
    EVENT_NAME="${EVENT:-pull_request}" BASE_SHA="$BASE" HEAD_SHA="$HEAD_SHA" PR_NUMBER=7 \
    BRANCH_NAME="$HOSTILE" REPO=o/r COMMIT_SHA="$HEAD_SHA" "$@"
}

pr ""
check "fork PR without token exits 0" "$RC" 0
check "fork PR writes zero findings" "$(output findings_count)" 0
check "fork PR emits skip notice" "$(grep -c 'no API key available' "$WORK/stdout")" 1

pr flr_pr_test_token
check "critical finding fails the check" "$RC" 1
check "findings_count output" "$(output findings_count)" 2
check "critical_count output" "$(output critical_count)" 1
check "hostile branch sent verbatim" \
  "$(last_request | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["body"]["metadata"]["branch"])')" "$HOSTILE"
check "only IaC files sent" \
  "$(last_request | "$PY" -c 'import json,sys; print(",".join(json.load(sys.stdin)["body"]["files"]))')" "iam/admin-policy.json,main.tf"
check "comment carries marker" "$(head -1 "$GH_BODY")" "<!-- flare-pr-security-check -->"
check "model output kept literal" "$(grep -c '100% sure: %s %n' "$GH_BODY")" 1
check "severity heading capitalised" "$(grep -c '^### Critical$' "$GH_BODY")" 1
check "new comment is POSTed" "$(grep -c 'issues/7/comments -X POST' "$GH_LOG")" 1

GH_EXISTING="111 222" pr flr_pr_test_token
check "existing comment lookup paginates" "$(grep -c -- '--paginate' "$GH_LOG")" 2
check "first existing comment is PATCHed" "$(grep -c 'issues/comments/111 -X PATCH' "$GH_LOG")" 1

FAIL_ON=none pr flr_pr_test_token
check "fail-on none passes" "$RC" 0

PATHS="," pr flr_pr_test_token
check "empty custom path list falls back to defaults" "$(output findings_count)" 2

PATHS=" .tf , " FAIL_ON=none pr flr_pr_test_token
check "custom paths filter" \
  "$(last_request | "$PY" -c 'import json,sys; print(",".join(json.load(sys.stdin)["body"]["files"]))')" "main.tf"

pr bad-token-0000
check "invalid token fails" "$RC" 1
check "invalid token message" "$(grep -c 'authentication failed' "$WORK/stdout")" 1

pr limit-token-000
check "rate limit does not fail" "$RC" 0

EVENT=pull_request_target FAIL_ON=none pr flr_pr_test_token
check "pull_request_target warns" "$(grep -c 'pull_request_target is not supported' "$WORK/stdout")" 1

finish
