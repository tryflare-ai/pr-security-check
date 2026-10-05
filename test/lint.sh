#!/usr/bin/env bash
# Static checks: no ${{ }} inside run: blocks, shellcheck every run block, zizmor.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
"${PYTHON:-python3}" - "$ROOT/action.yml" "$OUT" <<'PY'
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
for i, step in enumerate(steps):
    run = step.get("run", "")
    if "${{" in run:
        sys.exit(f"action.yml step {i} ({step.get('name')}) interpolates an expression into run:; pass it via env:")
    with open(f"{sys.argv[2]}/step-{i}.sh", "w") as f:
        f.write("#!/usr/bin/env bash\n" + run)
PY
shellcheck -S style "$OUT"/*.sh
echo "shellcheck: clean"
if command -v zizmor >/dev/null 2>&1; then
  zizmor --offline "$ROOT"
fi
