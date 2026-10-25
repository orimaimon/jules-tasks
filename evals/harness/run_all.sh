#!/usr/bin/env bash
# Run every eval with and without the skill, N samples each, then grade each answer blind.
#   bash evals/harness/run_all.sh [samples=3] [eval ids...]
# Needs: claude (logged in), node. Each run is a real model call: ~$0.10-0.15 per run, plus grading.
# Results: $EVROOT/out/<with|without>-<id>-<sample>.{jsonl,meta.json,grade.json}, then a summary table.
set -uo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
export SKILL_ROOT="${SKILL_ROOT:-$(cd "$H/../.." && pwd)}"
export EVROOT="${EVROOT:-${TMPDIR:-/tmp}/jules-tasks-evals}"
N="${1:-3}"; shift || true
IDS="${*:-$(node -e 'console.log(require(process.argv[1]).evals.map(e=>e.id).join(" "))' "$SKILL_ROOT/evals/evals.json")}"
mkdir -p "$EVROOT/out"
JOBS() { for k in $(seq 1 "$N"); do for i in $IDS; do echo "with $i $k"; echo "without $i $k"; done; done; }
JOBS | xargs -P "${PARALLEL:-6}" -L 1 bash "$H/run_one.sh"
JOBS | xargs -P "${PARALLEL:-6}" -L 1 bash "$H/grade_one.sh"
node "$H/summary.js" "$EVROOT" "$SKILL_ROOT/evals/evals.json" "$N" $IDS
