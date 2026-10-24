#!/usr/bin/env bash
# Merge reviewed PRs one at a time, the safe way:
#   for each PR: merge the base branch into the PR branch (in a scratch worktree, never your own checkout),
#   run the tests, push, wait for every CI job, then merge with the expected head SHA.
# Stops at the first problem and says why. Run from inside the repository.
#
#   TEST_CMD="screener/.venv/Scripts/python -m pytest tests/ -q" bash merge_queue.sh 92 90 93
#
# Env: TEST_CMD (required; run from the worktree root, its exit code decides), BASE (default main),
#      WT (scratch worktree, default ../<repo>-mq), MERGE_FLAG (default --merge).
# Why serial: every merge makes the remaining PRs stale, and tests from one PR can fail on another PR's
# code (seen: an "no email in the repo" test failing on a fixture added by a different PR).
set -u
: "${TEST_CMD:?set TEST_CMD, e.g. TEST_CMD='npm test' or 'python -m pytest -q'}"
BASE="${BASE:-main}"
ROOT="$(git rev-parse --show-toplevel)" || exit 1
WT="${WT:-$(dirname "$ROOT")/$(basename "$ROOT")-mq}"
MERGE_FLAG="${MERGE_FLAG:---merge}"
LOG="$(mktemp)"
cd "$ROOT" || exit 1
[ -d "$WT" ] || git worktree add -q -f "$WT" "origin/$BASE" --detach || { echo "cannot create worktree $WT"; exit 1; }

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
    [ $rc -eq 0 ] || { echo "tests failed on #$n after merging $BASE (log: $LOG), stopping"; exit 1; }
    (cd "$WT" && git push -q origin "HEAD:$branch") || { echo "push to $branch failed"; exit 1; }
    sleep 20                                            # let GitHub register the new checks
  fi
  gh pr checks "$n" --watch --interval 20 > /dev/null 2>&1
  git fetch -q origin
  sha="$(gh pr view "$n" --json headRefOid -q .headRefOid)"
  git merge-base --is-ancestor "origin/$BASE" "$sha" || { echo "#$n fell behind $BASE meanwhile, stopping"; exit 1; }
  bad="$(gh pr checks "$n" 2>&1 | awk -F'\t' '$2!="pass" && $2!="skipping"' | wc -l)"
  [ "$bad" -eq 0 ] || { echo "#$n: not every check passed:"; gh pr checks "$n"; exit 1; }
  gh pr ready "$n" > /dev/null 2>&1 || true            # Jules leaves its PRs as drafts
  gh pr merge "$n" $MERGE_FLAG --match-head-commit "$sha" && echo "merged #$n" || { echo "merge of #$n failed"; exit 1; }
done
echo "queue done"
