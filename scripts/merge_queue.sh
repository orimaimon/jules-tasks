#!/usr/bin/env bash
# Merge reviewed PRs one at a time, the safe way:
#   for each PR: merge the base branch into the PR branch (in a scratch worktree, never your own checkout),
#   run the tests, push, wait for every CI job, then merge with the expected head SHA.
# Stops at the first problem and says why. Run from inside the repository.
#
#   TEST_CMD="screener/.venv/Scripts/python -m pytest tests/ -q" bash merge_queue.sh 92 90 93
#
# Env: TEST_CMD (required; run from the worktree root, its exit code decides), BASE (default: the repo's default branch),
#      WT (scratch worktree, default ../<repo>-mq), MERGE_FLAG (default --merge), KEEP_WT (default 0).
# Why serial: every merge makes the remaining PRs stale, and tests from one PR can fail on another PR's
# code (seen: a "no email in the repo" test failing on a fixture added by a different PR).
# A PR that already contains the latest base is not re-tested locally: its CI ran on exactly that head.
set -uo pipefail
: "${TEST_CMD:?set TEST_CMD, e.g. TEST_CMD='npm test' or 'python -m pytest -q'}"
ROOT="$(git rev-parse --show-toplevel)" || exit 1
# The repository's default branch (origin/HEAD), unless BASE is set. Jules branches from it.
default_base() {
  git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' && return
  gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null && return
  echo main
}
BASE="${BASE:-$(cd "$ROOT" && default_base)}"
echo "base: $BASE"
WT="${WT:-$(dirname "$ROOT")/$(basename "$ROOT")-mq}"
MERGE_FLAG="${MERGE_FLAG:---merge}"
LOG="$(mktemp)"
CREATED_WT=0

cleanup() {
  rm -f "$LOG"
  if [ "${KEEP_WT:-0}" != "1" ] && [ "$CREATED_WT" = "1" ]; then
    git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

cd "$ROOT" || exit 1
if [ ! -d "$WT" ]; then
  git worktree add -q -f "$WT" "origin/$BASE" --detach || { echo "cannot create worktree $WT"; exit 1; }
  CREATED_WT=1
fi

check_ci() {
  local pr="$1" json
  json="$(gh pr view "$pr" --json statusCheckRollup 2>&1)" || return 1
  node -e '
    const j = JSON.parse(process.argv[1]);
    const r = j.statusCheckRollup || [];
    if (!r.length) { console.error("  no CI checks reported"); process.exit(1); }
    let bad = 0;
    for (const c of r) {
      const name = c.name || c.context;
      const concl = (c.conclusion || c.state || "").toUpperCase();
      const good = ["SUCCESS", "SKIPPED", "NEUTRAL"].includes(concl);
      if (!good) { bad++; console.error("  ❌ " + name + ": " + (concl || c.status || "PENDING")); }
    }
    process.exit(bad ? 1 : 0);
  ' "$json"
}

for n in "$@"; do
  echo "=== #$n"
  branch="$(gh pr view "$n" --json headRefName -q .headRefName)" || exit 1
  git fetch -q origin                                   # always fetch first: a stale origin/BASE says "up to date"
  sha="$(gh pr view "$n" --json headRefOid -q .headRefOid)"
  if ! git merge-base --is-ancestor "origin/$BASE" "$sha"; then
    (cd "$WT" && git checkout -q --detach "origin/$branch" && git merge -q --no-edit "origin/$BASE") \
      || { echo "merging $BASE into #$n failed (conflict?): resolve by hand"; exit 1; }
    # The exit code of the test command itself, never of a pipe ("pytest | tail -1 && push" pushed a red branch once).
    (cd "$WT" && eval "$TEST_CMD") > "$LOG" 2>&1; rc=$?
    echo "tests: $(tail -1 "$LOG")"
    if [ $rc -ne 0 ]; then
      echo "tests failed on #$n after merging $BASE, stopping:"
      tail -25 "$LOG"
      exit 1
    fi
    (cd "$WT" && git push -q origin "HEAD:$branch") || { echo "push to $branch failed"; exit 1; }
    sleep 20                                            # let GitHub register the new checks
  fi
  gh pr checks "$n" --watch --interval 20 > /dev/null 2>&1 || true
  git fetch -q origin
  sha="$(gh pr view "$n" --json headRefOid -q .headRefOid)"
  git merge-base --is-ancestor "origin/$BASE" "$sha" || { echo "#$n fell behind $BASE meanwhile, stopping"; exit 1; }
  check_ci "$n" || { echo "#$n: not every check passed, stopping"; exit 1; }
  gh pr ready "$n" > /dev/null 2>&1 || true            # Jules leaves its PRs as drafts
  gh pr merge "$n" $MERGE_FLAG --match-head-commit "$sha" && echo "merged #$n" || { echo "merge of #$n failed"; exit 1; }
done
echo "queue done"
