#!/usr/bin/env bash
# Local stand-in for CI when GitHub Actions can't run (billing, outage, no runners).
# Merges one or more PR heads onto origin/<base> in a throwaway worktree, optionally starts a
# throwaway Postgres container, and runs the steps defined in a project steps file.
#
# Usage:
#   STEPS_FILE=<path> bash local_ci.sh <PR#> [PR# ...]
#   (keep the steps file in the project repo, e.g. scripts/ci-steps.sh, so every session runs the same gate)
#   (from inside the repository; BASE defaults to the repo's default branch)
#
# The steps file is plain bash. It must define:
#   STEPS=(name1 name2 ...)            # order of execution
#   step_<name>() { ...; }             # one function per step; non-zero exit = failure
# and may set NEED_PG=1 (start Postgres), PG_IMAGE, PG_DB, PG_USER, PG_PASSWORD.
# Steps get: $WT (worktree path), $PG_URL (if NEED_PG), $RUN_DIR (logs), $BASE.
#
# Safety: never touches the user's checkout or their database. The worktree lives under
# $SCRATCH (default: $HOME/.lci), Postgres listens on $PG_PORT (default 5433) with data in tmpfs,
# and both are removed at the end unless KEEP=1. Nothing is pushed or merged on GitHub.
set -uo pipefail
# Associative arrays need bash 4+ (macOS ships 3.2 as /bin/bash: `brew install bash`, then run with that bash).
[ "${BASH_VERSINFO[0]}" -ge 4 ] || { echo "local_ci.sh needs bash >= 4 (this is $BASH_VERSION)"; exit 2; }

# With no PR numbers it checks origin/<base> itself (e.g. after merging a wave).
: "${STEPS_FILE:?set STEPS_FILE to the project steps file}"
# The repository's default branch (origin/HEAD), unless BASE is set. Jules branches from it.
default_base() {
  git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' && return
  gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null && return
  echo main
}
BASE="${BASE:-$(default_base)}"
# Keep this path SHORT on Windows: npm installs nest deeply and exceed MAX_PATH (260) under long temp dirs.
SCRATCH="${SCRATCH:-$HOME/.lci}"
PG_PORT="${PG_PORT:-5433}"
NEED_PG=0; PG_IMAGE="postgres:16-alpine"; PG_DB="ci_test"; PG_USER="postgres"; PG_PASSWORD="postgres"
# shellcheck source=/dev/null
source "$STEPS_FILE"

# The PID keeps two runs in the same second (a test suite, two terminals) from sharing a worktree and log dir.
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
WT="$SCRATCH/wt-$STAMP"; RUN_DIR="$SCRATCH/run-$STAMP"; mkdir -p "$RUN_DIR"
PG_NAME="local-ci-pg-$STAMP"
REPO="$(git rev-parse --show-toplevel)" || exit 2

cleanup() {
  [ "$NEED_PG" = "1" ] && docker rm -f "$PG_NAME" >/dev/null 2>&1
  if [ "${KEEP:-0}" != "1" ]; then git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1; fi
}
trap cleanup EXIT INT TERM

echo "== setup: worktree from origin/$BASE + PRs: $*"
git -C "$REPO" fetch -q origin "$BASE" || exit 2
git -C "$REPO" worktree add -q --detach "$WT" "origin/$BASE" || exit 2
HEADS=""
for pr in "$@"; do
  git -C "$WT" fetch -q origin "pull/$pr/head" || { echo "  cannot fetch PR #$pr"; exit 2; }
  sha="$(git -C "$WT" rev-parse --short FETCH_HEAD)"; HEADS="$HEADS #$pr@$sha"
  if ! git -C "$WT" -c user.name=local-ci -c user.email=local-ci@localhost merge -q --no-edit FETCH_HEAD >"$RUN_DIR/merge-$pr.log" 2>&1; then
    echo "  ❌ PR #$pr does not merge cleanly onto the others (see $RUN_DIR/merge-$pr.log)"; exit 1
  fi
  echo "  merged #$pr ($sha)"
done
echo "$HEADS" > "$RUN_DIR/heads.txt"

if [ "$NEED_PG" = "1" ]; then
  echo "== setup: throwaway Postgres ($PG_IMAGE) on port $PG_PORT"
  MSYS_NO_PATHCONV=1 docker run -d --rm --name "$PG_NAME" -e POSTGRES_USER="$PG_USER" -e POSTGRES_PASSWORD="$PG_PASSWORD" \
    -e POSTGRES_DB="$PG_DB" -p "$PG_PORT:5432" --tmpfs /var/lib/postgresql/data "$PG_IMAGE" >/dev/null || exit 2
  for _ in $(seq 1 60); do docker exec "$PG_NAME" pg_isready -U "$PG_USER" >/dev/null 2>&1 && break; sleep 1; done
  docker exec "$PG_NAME" pg_isready -U "$PG_USER" >/dev/null 2>&1 || { echo "  Postgres did not start"; exit 2; }
  PG_URL="postgresql://$PG_USER:$PG_PASSWORD@localhost:$PG_PORT/$PG_DB?schema=public"
fi
export WT RUN_DIR BASE PG_URL REPO

declare -A RESULT
for s in "${STEPS[@]}"; do
  echo "== step: $s"
  start=$(date +%s)
  ( cd "$WT" && "step_$s" ) >"$RUN_DIR/$s.log" 2>&1
  rc=$?   # the step's own exit code, never a pipe's
  RESULT[$s]="$rc $(( $(date +%s) - start ))s"
  if [ $rc -eq 0 ]; then echo "   ✅ $s (${RESULT[$s]#* })"; else echo "   ❌ $s exit $rc (${RESULT[$s]#* }) — tail of $RUN_DIR/$s.log:"; tail -15 "$RUN_DIR/$s.log" | sed 's/^/      /'; fi
done

echo "== summary for$HEADS"
fail=0
for s in "${STEPS[@]}"; do rc="${RESULT[$s]%% *}"; [ "$rc" = "0" ] && echo "  ✅ $s" || { echo "  ❌ $s (exit $rc)"; fail=1; }; done
echo "logs: $RUN_DIR"
exit $fail
