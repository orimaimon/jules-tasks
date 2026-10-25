#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers.sh
source "$SCRIPT_DIR/helpers.sh"

LOCAL_CI="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/local_ci.sh"

setup_test_env() {
  local info
  info="$(setup_repo)"
  read -r clone origin tmpdir <<< "$info"
  TMPDIRS+=("$tmpdir")

  (
    cd "$clone"
    git checkout -q -b main 2>/dev/null || true
    echo "initial" > README.md
    git add README.md
    git commit -q -m "Initial commit"
    git push -q origin main
    git remote set-head origin main
  )

  echo "$clone $origin $tmpdir"
}

create_pr_branch() {
  local clone="$1"
  local pr_num="$2"
  local branch="pr-$pr_num"
  shift 2
  # remaining args: key=value files to create/update
  (
    cd "$clone"
    git checkout -q -b "$branch" main
    for item in "$@"; do
      local file="${item%%=*}"
      local content="${item#*=}"
      echo "$content" > "$file"
      git add "$file"
    done
    git commit -q -m "PR $pr_num commit"
    git push -q origin "refs/heads/$branch:refs/pull/$pr_num/head"
    git checkout -q main
    git branch -D "$branch" >/dev/null
  )
}

echo "Running local_ci.sh test suite..."

# -----------------------------------------------------------------------------
# Scenario 1: Two PRs that touch different files (PR 1 adds x.txt, PR 2 adds y.txt)
# -----------------------------------------------------------------------------
echo "Test Scenario 1: Two PRs touching different files"
read -r clone origin tmpdir <<< "$(setup_test_env)"
scratch="$tmpdir/scratch"
mkdir -p "$scratch"

create_pr_branch "$clone" 1 "x.txt=content x"
create_pr_branch "$clone" 2 "y.txt=content y"

steps1="$tmpdir/steps1.sh"
cat << 'EOF' > "$steps1"
STEPS=(check_both)
step_check_both() {
  [ -f x.txt ] && [ -f y.txt ]
}
EOF

set +e
output1="$(cd "$clone" && STEPS_FILE="$steps1" SCRATCH="$scratch" BASE=main bash "$LOCAL_CI" 1 2 2>&1)"
exit1=$?
set -e

assert_exit 0 "$exit1" "Scenario 1 should exit 0"
assert_contains "$output1" "merged #1" "Output should confirm PR #1 merged"
assert_contains "$output1" "merged #2" "Output should confirm PR #2 merged"
assert_contains "$output1" "== summary for #1@" "Summary should list #1@"
assert_contains "$output1" "#2@" "Summary should list #2@"
assert_contains "$output1" "✅ check_both" "Summary should report success for check_both"

wt_lines="$(cd "$clone" && git worktree list | wc -l)"
assert_exit 1 "$wt_lines" "git worktree list should show only 1 worktree (the clone)"

# -----------------------------------------------------------------------------
# Scenario 2: Three steps where the middle one fails and last writes a marker
# -----------------------------------------------------------------------------
echo "Test Scenario 2: Step failure, order, and marker file in RUN_DIR"
read -r clone origin tmpdir <<< "$(setup_test_env)"
scratch="$tmpdir/scratch"
mkdir -p "$scratch"

steps2="$tmpdir/steps2.sh"
cat << 'EOF' > "$steps2"
STEPS=(first second third)
step_first() {
  return 0
}
step_second() {
  return 3
}
step_third() {
  touch "$RUN_DIR/step3_marker.txt"
  return 0
}
EOF

set +e
output2="$(cd "$clone" && STEPS_FILE="$steps2" SCRATCH="$scratch" BASE=main bash "$LOCAL_CI" 2>&1)"
exit2=$?
set -e

assert_exit 1 "$exit2" "Scenario 2 should exit 1 on step failure"
assert_contains "$output2" "❌ second (exit 3)" "Summary should show second step failed with exit 3"
assert_contains "$output2" "✅ third" "Summary should show third step succeeded"

marker_file="$(find "$scratch" -name "step3_marker.txt" | head -n 1)"
if [ -n "$marker_file" ] && [ -f "$marker_file" ]; then
  echo "  ✅ Assert marker file exists in RUN_DIR passed"
else
  echo "  ❌ ASSERTION FAILED: Marker file step3_marker.txt not found in RUN_DIR under $scratch"
  FAILURES=$((FAILURES + 1))
fi

# -----------------------------------------------------------------------------
# Scenario 3: Two PRs that change the same line of the same file (conflict)
# -----------------------------------------------------------------------------
echo "Test Scenario 3: Merge conflict"
read -r clone origin tmpdir <<< "$(setup_test_env)"
scratch="$tmpdir/scratch"
mkdir -p "$scratch"

(
  cd "$clone"
  echo "base line" > conflict.txt
  git add conflict.txt
  git commit -q -m "Add conflict.txt on main"
  git push -q origin main
)

create_pr_branch "$clone" 1 "conflict.txt=change A"
create_pr_branch "$clone" 2 "conflict.txt=change B"

steps3="$tmpdir/steps3.sh"
cat << 'EOF' > "$steps3"
STEPS=(dummy)
step_dummy() { return 0; }
EOF

set +e
output3="$(cd "$clone" && STEPS_FILE="$steps3" SCRATCH="$scratch" BASE=main bash "$LOCAL_CI" 1 2 2>&1)"
exit3=$?
set -e

assert_exit 1 "$exit3" "Scenario 3 should exit 1 on merge conflict"
assert_contains "$output3" "does not merge cleanly" "Output should announce merge conflict"

# -----------------------------------------------------------------------------
# Scenario 4: No PR numbers
# -----------------------------------------------------------------------------
echo "Test Scenario 4: No PR numbers (checks origin/main)"
read -r clone origin tmpdir <<< "$(setup_test_env)"
scratch="$tmpdir/scratch"
mkdir -p "$scratch"

(
  cd "$clone"
  echo "main content" > main_only.txt
  git add main_only.txt
  git commit -q -m "Add main_only.txt"
  git push -q origin main
)

steps4="$tmpdir/steps4.sh"
cat << 'EOF' > "$steps4"
STEPS=(check_main)
step_check_main() {
  [ -f main_only.txt ]
}
EOF

set +e
output4="$(cd "$clone" && STEPS_FILE="$steps4" SCRATCH="$scratch" BASE=main bash "$LOCAL_CI" 2>&1)"
exit4=$?
set -e

assert_exit 0 "$exit4" "Scenario 4 with no PRs should exit 0"
assert_contains "$output4" "✅ check_main" "Summary should show check_main passed"

# -----------------------------------------------------------------------------
# Scenario 5: KEEP=1
# -----------------------------------------------------------------------------
echo "Test Scenario 5: KEEP=1 preserves worktree"
read -r clone origin tmpdir <<< "$(setup_test_env)"
scratch="$tmpdir/scratch"
mkdir -p "$scratch"

steps5="$tmpdir/steps5.sh"
cat << 'EOF' > "$steps5"
STEPS=(noop)
step_noop() { return 0; }
EOF

set +e
output5="$(cd "$clone" && KEEP=1 STEPS_FILE="$steps5" SCRATCH="$scratch" BASE=main bash "$LOCAL_CI" 2>&1)"
exit5=$?
set -e

assert_exit 0 "$exit5" "Scenario 5 with KEEP=1 should exit 0"

wt_dir="$(find "$scratch" -maxdepth 1 -type d -name "wt-*" | head -n 1)"
if [ -n "$wt_dir" ] && [ -d "$wt_dir" ]; then
  echo "  ✅ Assert worktree exists after KEEP=1 passed"
  git -C "$clone" worktree remove --force "$wt_dir" >/dev/null 2>&1 || true
else
  echo "  ❌ ASSERTION FAILED: Worktree directory not found under $scratch after KEEP=1"
  FAILURES=$((FAILURES + 1))
fi

# -----------------------------------------------------------------------------
# Scenario 6: STEPS_FILE unset
# -----------------------------------------------------------------------------
echo "Test Scenario 6: STEPS_FILE unset fails"
read -r clone origin tmpdir <<< "$(setup_test_env)"
scratch="$tmpdir/scratch"
mkdir -p "$scratch"

set +e
output6="$(cd "$clone" && unset STEPS_FILE && SCRATCH="$scratch" BASE=main bash "$LOCAL_CI" 2>&1)"
exit6=$?
set -e

if [ "$exit6" -ne 0 ]; then
  echo "  ✅ Assert non-zero exit passed: $exit6"
else
  echo "  ❌ ASSERTION FAILED: local_ci.sh exited with 0 when STEPS_FILE was unset"
  FAILURES=$((FAILURES + 1))
fi
assert_contains "$output6" "STEPS_FILE" "Output should mention STEPS_FILE when unset"

# -----------------------------------------------------------------------------
# Scenario 7: Two runs back-to-back with KEEP=1
# -----------------------------------------------------------------------------
echo "Test Scenario 7: Two runs back-to-back with KEEP=1 use separate directories"
read -r clone origin tmpdir <<< "$(setup_test_env)"
scratch="$tmpdir/scratch"
mkdir -p "$scratch"

steps7="$tmpdir/steps7.sh"
cat << 'EOF' > "$steps7"
STEPS=(noop)
step_noop() { return 0; }
EOF

set +e
output7_a="$(cd "$clone" && KEEP=1 STEPS_FILE="$steps7" SCRATCH="$scratch" BASE=main bash "$LOCAL_CI" 2>&1)"
exit7_a=$?
output7_b="$(cd "$clone" && KEEP=1 STEPS_FILE="$steps7" SCRATCH="$scratch" BASE=main bash "$LOCAL_CI" 2>&1)"
exit7_b=$?
set -e

assert_exit 0 "$exit7_a" "Scenario 7 run 1 should exit 0"
assert_exit 0 "$exit7_b" "Scenario 7 run 2 should exit 0"

wt_count="$(find "$scratch" -maxdepth 1 -type d -name "wt-*" | wc -l)"
if [ "$wt_count" -eq 2 ]; then
  echo "  ✅ Assert separate worktree directories created passed: count=$wt_count"
else
  echo "  ❌ ASSERTION FAILED: Expected 2 worktree directories under $scratch, got $wt_count"
  FAILURES=$((FAILURES + 1))
fi

# Clean up remaining worktrees in scenario 7 so git worktree list is clean
for wt in "$scratch"/wt-*; do
  if [ -d "$wt" ]; then
    git -C "$clone" worktree remove --force "$wt" >/dev/null 2>&1 || true
  fi
done

finish
