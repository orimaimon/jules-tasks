#!/usr/bin/env bash
set -uo pipefail

FAILURES=0
TMPDIRS=()

cleanup() {
  for d in "${TMPDIRS[@]}"; do
    if [ -d "$d" ]; then
      rm -rf "$d"
    fi
  done
}
trap cleanup EXIT

finish() {
  if [ "$FAILURES" -gt 0 ]; then
    echo "Test failed with $FAILURES failure(s)."
    exit 1
  else
    echo "All tests passed."
    exit 0
  fi
}

sanitize_path() {
  local clean_path=""
  local entry
  IFS=':' read -ra PATH_ENTRIES <<< "$PATH"
  for entry in "${PATH_ENTRIES[@]}"; do
    if [ -f "$entry/jules" ]; then
      continue
    fi
    if [ -z "$clean_path" ]; then
      clean_path="$entry"
    else
      clean_path="$clean_path:$entry"
    fi
  done
  export PATH="$clean_path"
}

setup_repo() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  local origin="$tmpdir/origin.git"
  local clone="$tmpdir/clone"

  git init --bare -q -b main "$origin"
  git clone -q "$origin" "$clone"

  (
    cd "$clone" || exit 1
    git config user.name "Test User"
    git config user.email "test@example.com"
  )

  echo "$clone $origin $tmpdir"
}

setup_fake_gh() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  TMPDIRS+=("$tmpdir")

  local fake_bin="$tmpdir/bin"
  mkdir -p "$fake_bin"

  cat << 'EOF' > "$fake_bin/gh"
#!/usr/bin/env bash
echo "$GH_JSON"
EOF
  chmod +x "$fake_bin/gh"

  sanitize_path
  export PATH="$fake_bin:$PATH"
}

assert_contains() {
  local output="$1"
  local needle="$2"
  local msg="${3:-"Output does not contain '$needle'"}"

  if echo "$output" | grep -Fq -- "$needle"; then
    echo "  ✅ Assert contains passed: $needle"
  else
    echo "  ❌ ASSERTION FAILED: $msg"
    echo "     Expected needle: $needle"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_not_contains() {
  local output="$1"
  local needle="$2"
  local msg="${3:-"Output contains '$needle' but should not"}"

  if echo "$output" | grep -Fq -- "$needle"; then
    echo "  ❌ ASSERTION FAILED: $msg"
    echo "     Unexpected needle found: $needle"
    FAILURES=$((FAILURES + 1))
  else
    echo "  ✅ Assert not contains passed: $needle"
  fi
}

assert_exit() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-"Exit code $actual does not match expected $expected"}"

  if [ "$expected" -eq "$actual" ]; then
    echo "  ✅ Assert exit code passed: $actual"
  else
    echo "  ❌ ASSERTION FAILED: $msg"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_count() {
  local output="$1"
  local needle="$2"
  local expected_count="$3"
  local msg="${4:-"Needle '$needle' count does not match expected $expected_count"}"

  local actual_count
  actual_count="$(echo "$output" | grep -Fc -- "$needle" || true)"

  if [ "$actual_count" -eq "$expected_count" ]; then
    echo "  ✅ Assert count passed: '$needle' appeared $actual_count time(s)"
  else
    echo "  ❌ ASSERTION FAILED: $msg"
    echo "     Expected count: $expected_count, actual: $actual_count"
    FAILURES=$((FAILURES + 1))
  fi
}
