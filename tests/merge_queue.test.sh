#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MERGE_QUEUE="$REPO_ROOT/scripts/merge_queue.sh"

# shellcheck source=tests/helpers.sh
source "$SCRIPT_DIR/helpers.sh"

sanitize_path

# Create fake gh setup
GH_DIR="$(mktemp -d)"
TMPDIRS+=("$GH_DIR")

FAKE_GH_BIN="$GH_DIR/gh"
GH_LOG_FILE="$GH_DIR/gh.log"
touch "$GH_LOG_FILE"

cat << 'EOF' > "$FAKE_GH_BIN"
#!/usr/bin/env bash
set -uo pipefail

echo "$*" >> "$GH_LOG_FILE"

subcommand="${1:-}"
action="${2:-}"

if [ "$subcommand" = "pr" ]; then
  if [ "$action" = "view" ]; then
    pr_num="${3:-1}"

    # Check if -q query is present
    is_q=0
    for arg in "$@"; do
      if [ "$arg" = "-q" ] || [ "$arg" = ".headRefOid" ]; then
        is_q=1
      fi
    done

    # Find PR branch on origin
    pr_branch="${PR_BRANCH:-pr$pr_num}"
    head_oid="$(git ls-remote origin "refs/heads/$pr_branch" 2>/dev/null | awk '{print $1}')"

    if [ "$is_q" = "1" ]; then
      echo "$head_oid"
      exit 0
    fi

    # Check json requested
    json_arg=""
    for ((i=1; i<=$#; i++)); do
      if [ "${!i}" = "--json" ]; then
        next=$((i+1))
        json_arg="${!next:-}"
      fi
    done

    if [[ "$json_arg" == *"statusCheckRollup"* ]]; then
      concl="${CI_CONCLUSION:-SUCCESS}"
      cat <<JSON
{
  "statusCheckRollup": [
    {"name": "test", "conclusion": "$concl"}
  ]
}
JSON
      exit 0
    fi

    cf="${CHANGED_FILES:-1}"
    add="${ADDITIONS:-5}"
    del="${DELETIONS:-2}"

    cat <<JSON
{
  "headRefName": "$pr_branch",
  "headRefOid": "$head_oid",
  "changedFiles": $cf,
  "additions": $add,
  "deletions": $del
}
JSON
    exit 0
  elif [ "$action" = "checks" ] || [ "$action" = "ready" ]; then
    exit 0
  elif [ "$action" = "merge" ]; then
    match_sha=""
    for ((i=1; i<=$#; i++)); do
      if [ "${!i}" = "--match-head-commit" ]; then
        next=$((i+1))
        match_sha="${!next:-}"
      fi
    done

    if [ -n "$match_sha" ]; then
      if [ "${FAKE_GH_TREE_MISMATCH:-0}" = "1" ]; then
        empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
        bad_sha="$(git commit-tree -m "mismatch" -p "$match_sha" "$empty_tree")"
        git push origin "$bad_sha:refs/heads/main" >/dev/null 2>&1
      else
        git push origin "$match_sha:refs/heads/main" >/dev/null 2>&1
      fi
    fi
    exit 0
  fi
fi

exit 0
EOF
chmod +x "$FAKE_GH_BIN"

export PATH="$GH_DIR:$PATH"
export GH_LOG_FILE

# Helper to build a test environment
setup_scenario_repo() {
  read -r CLONE ORIGIN TMPDIR <<< "$(setup_repo)"
  TMPDIRS+=("$TMPDIR")
  echo "$CLONE" "$ORIGIN" "$TMPDIR"
}

echo "--- Scenario 1: Happy path ---"
read -r CLONE ORIGIN TMPDIR <<< "$(setup_scenario_repo)"
cd "$CLONE" || exit 1

# Base commit on main
echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"
git push -q origin main 2>/dev/null

# PR branch pr1 on top of main
git checkout -q -b pr1
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "add feature"
git push -q origin pr1 2>/dev/null
git checkout -q main

pr1_sha="$(git rev-parse origin/pr1)"

: > "$GH_LOG_FILE"
set +e
OUT="$(TEST_CMD="true" BASE=main bash "$MERGE_QUEUE" 1 2>&1)"
EXIT_CODE=$?
set -e

assert_exit 0 "$EXIT_CODE" "Happy path should exit with 0"
assert_contains "$OUT" "merged #1 (tree check"
assert_contains "$OUT" "queue done"

LOG_CONTENT="$(cat "$GH_LOG_FILE")"
assert_contains "$LOG_CONTENT" "pr ready 1"
assert_contains "$LOG_CONTENT" "pr merge 1 --merge --match-head-commit"

origin_main_sha="$(git -C "$ORIGIN" rev-parse refs/heads/main)"
if [ "$origin_main_sha" = "$pr1_sha" ]; then
  echo "  ✅ origin's main equals PR head SHA"
else
  echo "  ❌ ASSERTION FAILED: origin main SHA ($origin_main_sha) != PR head SHA ($pr1_sha)"
  FAILURES=$((FAILURES + 1))
fi
cd "$REPO_ROOT" || exit 1

echo "--- Scenario 2: Red CI ---"
read -r CLONE ORIGIN TMPDIR <<< "$(setup_scenario_repo)"
cd "$CLONE" || exit 1

echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"
git push -q origin main 2>/dev/null

git checkout -q -b pr1
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "add feature"
git push -q origin pr1 2>/dev/null
git checkout -q main

: > "$GH_LOG_FILE"
set +e
OUT="$(CI_CONCLUSION="FAILURE" TEST_CMD="true" BASE=main bash "$MERGE_QUEUE" 1 2>&1)"
EXIT_CODE=$?
set -e

assert_exit 1 "$EXIT_CODE" "Red CI should exit with 1"
assert_contains "$OUT" "not every check passed, stopping"

LOG_CONTENT="$(cat "$GH_LOG_FILE")"
assert_not_contains "$LOG_CONTENT" "pr merge"
cd "$REPO_ROOT" || exit 1

echo "--- Scenario 3: Empty PR ---"
read -r CLONE ORIGIN TMPDIR <<< "$(setup_scenario_repo)"
cd "$CLONE" || exit 1

echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"
git push -q origin main 2>/dev/null

git checkout -q -b pr1
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "add feature"
git push -q origin pr1 2>/dev/null
git checkout -q main

: > "$GH_LOG_FILE"
set +e
OUT="$(CHANGED_FILES=0 TEST_CMD="true" BASE=main bash "$MERGE_QUEUE" 1 2>&1)"
EXIT_CODE=$?
set -e

assert_exit 1 "$EXIT_CODE" "Empty PR should exit with 1"
assert_contains "$OUT" "0 changed lines"

LOG_CONTENT="$(cat "$GH_LOG_FILE")"
assert_not_contains "$LOG_CONTENT" "pr merge"
cd "$REPO_ROOT" || exit 1

echo "--- Scenario 4: Behind main with failing tests ---"
read -r CLONE ORIGIN TMPDIR <<< "$(setup_scenario_repo)"
cd "$CLONE" || exit 1

echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"
git push -q origin main 2>/dev/null

# Cut PR branch
git checkout -q -b pr1
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "add feature"
git push -q origin pr1 2>/dev/null
git checkout -q main

# New commit on main after PR branch cut
echo "main update" > main_update.txt
git add main_update.txt
git commit -q -m "main update"
git push -q origin main 2>/dev/null

pr1_orig_sha="$(git -C "$ORIGIN" rev-parse refs/heads/pr1)"

: > "$GH_LOG_FILE"
set +e
OUT="$(TEST_CMD="false" SKIP_GH_CI=1 BASE=main bash "$MERGE_QUEUE" 1 2>&1)"
EXIT_CODE=$?
set -e

assert_exit 1 "$EXIT_CODE" "Behind main with failing tests should exit with 1"
assert_contains "$OUT" "tests failed on #1 after merging main"

pr1_after_sha="$(git -C "$ORIGIN" rev-parse refs/heads/pr1)"
if [ "$pr1_orig_sha" = "$pr1_after_sha" ]; then
  echo "  ✅ PR branch on origin is unchanged"
else
  echo "  ❌ ASSERTION FAILED: PR branch on origin changed ($pr1_orig_sha vs $pr1_after_sha)"
  FAILURES=$((FAILURES + 1))
fi
cd "$REPO_ROOT" || exit 1

echo "--- Scenario 5: Behind main with passing tests ---"
read -r CLONE ORIGIN TMPDIR <<< "$(setup_scenario_repo)"
cd "$CLONE" || exit 1

echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"
git push -q origin main 2>/dev/null

# Cut PR branch
git checkout -q -b pr1
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "add feature"
git push -q origin pr1 2>/dev/null
git checkout -q main

# New commit on main after PR branch cut
echo "main update" > main_update.txt
git add main_update.txt
git commit -q -m "main update"
git push -q origin main 2>/dev/null

old_main_sha="$(git -C "$ORIGIN" rev-parse refs/heads/main)"

: > "$GH_LOG_FILE"
set +e
OUT="$(TEST_CMD="true" SKIP_GH_CI=1 BASE=main bash "$MERGE_QUEUE" 1 2>&1)"
EXIT_CODE=$?
set -e

assert_exit 0 "$EXIT_CODE" "Behind main with passing tests should exit with 0"
assert_contains "$OUT" "merged #1 (tree check"

# PR branch on origin now contains main (git merge-base --is-ancestor)
if git -C "$ORIGIN" merge-base --is-ancestor "$old_main_sha" refs/heads/pr1; then
  echo "  ✅ PR branch on origin contains main"
else
  echo "  ❌ ASSERTION FAILED: PR branch on origin does not contain main"
  FAILURES=$((FAILURES + 1))
fi

# origin's main contains the PR's file
if git -C "$CLONE" archive origin/main feature.txt >/dev/null 2>&1; then
  echo "  ✅ origin's main contains the PR's file"
else
  echo "  ❌ ASSERTION FAILED: origin's main does not contain feature.txt"
  FAILURES=$((FAILURES + 1))
fi
cd "$REPO_ROOT" || exit 1

echo "--- Scenario 6: Tree check mismatch ---"
read -r CLONE ORIGIN TMPDIR <<< "$(setup_scenario_repo)"
cd "$CLONE" || exit 1

echo "initial" > file.txt
git add file.txt
git commit -q -m "initial commit"
git push -q origin main 2>/dev/null

git checkout -q -b pr1
echo "feature" > feature.txt
git add feature.txt
git commit -q -m "add feature"
git push -q origin pr1 2>/dev/null
git checkout -q main

: > "$GH_LOG_FILE"
set +e
OUT="$(FAKE_GH_TREE_MISMATCH=1 TEST_CMD="true" BASE=main bash "$MERGE_QUEUE" 1 2>&1)"
EXIT_CODE=$?
set -e

assert_exit 1 "$EXIT_CODE" "Tree check mismatch should exit with 1"
assert_contains "$OUT" "tree differs"
cd "$REPO_ROOT" || exit 1

echo "--- Scenario 7: TEST_CMD unset ---"
read -r CLONE ORIGIN TMPDIR <<< "$(setup_scenario_repo)"
cd "$CLONE" || exit 1

set +e
OUT="$(unset TEST_CMD; BASE=main bash "$MERGE_QUEUE" 1 2>&1)"
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "  ✅ Assert non-zero exit code passed: $EXIT_CODE"
else
  echo "  ❌ ASSERTION FAILED: Expected non-zero exit code, got 0"
  FAILURES=$((FAILURES + 1))
fi

assert_contains "$OUT" "TEST_CMD"
cd "$REPO_ROOT" || exit 1

finish
