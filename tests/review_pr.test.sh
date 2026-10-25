#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REVIEW_PR="$REPO_ROOT/scripts/review_pr.sh"

# shellcheck source=tests/helpers.sh
source "$SCRIPT_DIR/helpers.sh"

sanitize_path

read -r CLONE _ORIGIN TMPDIR <<< "$(setup_repo)"
TMPDIRS+=("$TMPDIR")

cd "$CLONE" || exit 1

# Base commit
mkdir -p src tests
echo "print('a')" > src/a.py

cat << 'EOF' > tests/test_a.py
def test_a():
    assert 1 == 1
    assert 2 == 2
EOF

cat << 'EOF' > src/b.test.ts
it("x", () => {
    expect(true).toBe(true);
});
EOF

git add .
git commit -m "initial commit"
git push origin main

# Setup PR 7
git checkout -b pr7
cat << 'EOF' > src/a.py
while True:
    try:
        pass
    except: pass
EOF

cat << 'EOF' > src/b.test.ts
it.only("x", () => {
    expect(true).toBe(true);
});
EOF

git rm tests/test_a.py
echo "notes" > notes.txt
git add notes.txt src/a.py src/b.test.ts
git commit -m "pr7 changes"
git commit --allow-empty -m "empty 1"
git commit --allow-empty -m "empty 2"
git commit --allow-empty -m "empty 3"
git push origin HEAD:refs/pull/7/head

cat << 'EOF' > "$TMPDIR/allowlist7.txt"
src/a.py
src/*.test.ts
EOF

# Setup PR 5
git checkout main
git checkout -b pr5
echo "print('a modified')" > src/a.py

cat << 'EOF' >> tests/test_a.py

def test_b():
    assert 3 == 3
EOF

git add src/a.py tests/test_a.py
git commit -m "pr5 changes"
git push origin HEAD:refs/pull/5/head

cat << 'EOF' > "$TMPDIR/allowlist5.txt"
src/a.py
tests/test_a.py
EOF

echo "--- Run 1: PR 7 with NO_GH=1 BASE=main ---"
set +e
OUT1="$(NO_GH=1 BASE=main bash "$REVIEW_PR" 7 "$TMPDIR/allowlist7.txt" 2>&1)"
EXIT1=$?
set -e

assert_contains "$OUT1" "❌ outside allowlist: notes.txt"
# Intended: deleting a file outside the allowlist is a change to a file the task may not touch.
assert_contains "$OUT1" "❌ outside allowlist: tests/test_a.py"
assert_contains "$OUT1" "❌ test files deleted"
assert_contains "$OUT1" "❌ asserts dropped"
assert_contains "$OUT1" ".only"
assert_contains "$OUT1" "while True"
assert_contains "$OUT1" "⚠️  empty commit(s)"
assert_count "$OUT1" "NOT CHECKED (no gh)" 2
assert_exit 1 "$EXIT1"

echo "--- Run 2: PR 7 with fake gh ---"
setup_fake_gh

export GH_JSON='{
  "number": 7,
  "title": "PR 7",
  "body": "Closes #123\nFixes #31",
  "state": "OPEN",
  "isDraft": false,
  "baseRefName": "main",
  "headRefName": "pr7",
  "headRefOid": "1234567890",
  "additions": 10,
  "deletions": 5,
  "changedFiles": 4,
  "files": [],
  "statusCheckRollup": [{"name": "test", "conclusion": "FAILURE"}],
  "author": {"login": "testuser"},
  "closingIssuesReferences": [{"number": 123}, {"number": 31}]
}'

set +e
OUT2="$(bash "$REVIEW_PR" 7 "$TMPDIR/allowlist7.txt" 31 2>&1)"
EXIT2=$?
set -e

assert_contains "$OUT2" "⚠️  closes multiple issues"
assert_contains "$OUT2" "❌ expected PR to close only #31"
assert_contains "$OUT2" "❌ test: FAILURE"
assert_exit 1 "$EXIT2"

echo "--- Run 3: Clean PR 5 with fake gh ---"
export GH_JSON='{
  "number": 5,
  "title": "Clean PR",
  "body": "Closes #31",
  "state": "OPEN",
  "isDraft": false,
  "baseRefName": "main",
  "headRefName": "pr5",
  "headRefOid": "1234567890",
  "additions": 3,
  "deletions": 0,
  "changedFiles": 2,
  "files": [],
  "statusCheckRollup": [{"name": "test", "conclusion": "SUCCESS"}],
  "author": {"login": "testuser"},
  "closingIssuesReferences": [{"number": 31}]
}'

set +e
OUT3="$(bash "$REVIEW_PR" 5 "$TMPDIR/allowlist5.txt" 31 2>&1)"
EXIT3=$?
set -e

assert_contains "$OUT3" "Summary: 0 fail, 0 warn"
assert_exit 0 "$EXIT3"

echo "--- Run 4: Clean PR 5 with NO_GH=1 BASE=main ---"
set +e
OUT4="$(NO_GH=1 BASE=main bash "$REVIEW_PR" 5 "$TMPDIR/allowlist5.txt" 31 2>&1)"
EXIT4=$?
set -e

assert_contains "$OUT4" "Summary: 0 fail"
assert_exit 0 "$EXIT4"

finish
