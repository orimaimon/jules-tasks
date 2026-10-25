#!/usr/bin/env bash
set -euo pipefail

# Setup temporary directory for test execution
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export JULES_API_KEY="test"

BINDIR="$TMPDIR/bin"
mkdir -p "$BINDIR"

LOGFILE="$TMPDIR/curl_args.log"
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures/jules_api" && pwd)"

cat <<'EOF' > "$BINDIR/curl"
#!/usr/bin/env bash
set -euo pipefail

LOGFILE="${CURL_LOGFILE:?}"
FIXTURES_DIR="${CURL_FIXTURES_DIR:?}"

# Log all arguments
printf '%s\n' "$*" >> "$LOGFILE"

url=""
for arg in "$@"; do
  if [[ "$arg" == https://* ]]; then
    url="$arg"
    break
  fi
done

case "$url" in
  "https://jules.googleapis.com/v1alpha/sessions/s123/activities?pageSize=100&pageToken=tok%2F%3D1")
    cat "$FIXTURES_DIR/activities_page2.json"
    ;;
  "https://jules.googleapis.com/v1alpha/sessions/s123/activities?pageSize=100")
    cat "$FIXTURES_DIR/activities_page1.json"
    ;;
  "https://jules.googleapis.com/v1alpha/sessions/s123")
    cat "$FIXTURES_DIR/session.json"
    ;;
  "https://jules.googleapis.com/v1alpha/sessions/s123:approvePlan")
    echo '{}'
    ;;
  "https://jules.googleapis.com/v1alpha/sessions/s123:sendMessage")
    echo '{"name": "sessions/s123"}'
    ;;
  "https://jules.googleapis.com/v1alpha/sessions/error")
    cat "$FIXTURES_DIR/error.json"
    exit 22
    ;;
  "https://jules.googleapis.com/v1alpha/sources?pageSize=100")
    cat "$FIXTURES_DIR/sources.json"
    ;;
  "https://jules.googleapis.com/v1alpha/sessions?pageSize="*)
    echo '{"sessions":[{"name":"sessions/s123","state":"AWAITING_USER_FEEDBACK","title":"Test Session"}]}'
    ;;
  "https://jules.googleapis.com/v1alpha/sessions")
    echo '{"name": "sessions/s123"}'
    ;;
  *)
    echo "Unknown URL in fake curl: $url" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$BINDIR/curl"

export PATH="$BINDIR:$PATH"
export CURL_LOGFILE="$LOGFILE"
export CURL_FIXTURES_DIR="$FIXTURES_DIR"

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/jules_api.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# 1. status prints the waiting question
echo "Testing: status"
status_out="$(bash "$SCRIPT" status s123)"
if ! echo "$status_out" | grep -q "How would you like to proceed?"; then
  fail "status output did not contain expected question. Output:\n$status_out"
fi

# 2. plan prints the steps in index order
echo "Testing: plan"
plan_out="$(bash "$SCRIPT" plan s123)"
pos_step1="$(echo "$plan_out" | grep -n "Step One" | cut -d: -f1 || true)"
pos_step2="$(echo "$plan_out" | grep -n "Step Two" | cut -d: -f1 || true)"
if [ -z "$pos_step1" ] || [ -z "$pos_step2" ] || [ "$pos_step1" -ge "$pos_step2" ]; then
  fail "plan steps are not in index order. Output:\n$plan_out"
fi

# 3. activities shows "bash exit 0:" with the command and "[patch]"
echo "Testing: activities"
acts_out="$(bash "$SCRIPT" activities s123)"
if ! echo "$acts_out" | grep -q "bash exit 0: echo hello"; then
  fail "activities output missing 'bash exit 0: echo hello'. Output:\n$acts_out"
fi
if ! echo "$acts_out" | grep -q "\[patch\]"; then
  fail "activities output missing '[patch]'. Output:\n$acts_out"
fi

# 4. patch writes the unidiff to the given file and prints its files and base commit
echo "Testing: patch"
out_patch="$TMPDIR/out.patch"
patch_stdout="$(bash "$SCRIPT" patch s123 "$out_patch")"
if [ ! -f "$out_patch" ]; then
  fail "patch command did not create patch file $out_patch"
fi
if ! grep -q "diff --git a/file.txt b/file.txt" "$out_patch"; then
  fail "patch file content missing expected unidiff"
fi
if ! echo "$patch_stdout" | grep -q "base: basecommit123"; then
  fail "patch output missing base commit info. Output:\n$patch_stdout"
fi
if ! echo "$patch_stdout" | grep -q "file.txt"; then
  fail "patch output missing file list. Output:\n$patch_stdout"
fi

# 5. new with --no-auto-pr and --require-plan-approval
echo "Testing: new with flags"
prompt_file="$TMPDIR/prompt.txt"
printf 'My Title\nDetailed prompt text\n' > "$prompt_file"
: > "$LOGFILE"
bash "$SCRIPT" new owner/repo main "$prompt_file" --no-auto-pr --require-plan-approval > /dev/null
logged_args="$(cat "$LOGFILE")"
if ! echo "$logged_args" | grep -q '"automationMode":"AUTOMATION_MODE_UNSPECIFIED"'; then
  fail "new command did not send AUTOMATION_MODE_UNSPECIFIED. Log:\n$logged_args"
fi
if ! echo "$logged_args" | grep -q '"requirePlanApproval":true'; then
  fail "new command did not send requirePlanApproval true. Log:\n$logged_args"
fi

# 6. new with an unknown option exits 2
echo "Testing: new with unknown option"
set +e
err_out="$TMPDIR/err_unknown.txt"
bash "$SCRIPT" new owner/repo main "$prompt_file" --invalid-option 2> "$err_out"
exit_code=$?
set -e
if [ "$exit_code" -ne 2 ]; then
  fail "new with unknown option exited with $exit_code, expected 2"
fi

# 7. status on the error URL prints the error JSON on stderr and exits non-zero
echo "Testing: status on error URL"
set +e
err_status_out="$TMPDIR/err_status.txt"
bash "$SCRIPT" status error 2> "$err_status_out"
status_exit_code=$?
set -e
if [ "$status_exit_code" -eq 0 ]; then
  fail "status on error URL unexpectedly succeeded"
fi
if ! grep -q '"Session not found"' "$err_status_out"; then
  fail "status stderr did not contain API error JSON. Stderr:\n$(cat "$err_status_out")"
fi

# 8. sources prints both source names
echo "Testing: sources"
sources_out="$(bash "$SCRIPT" sources)"
if ! echo "$sources_out" | grep -q "sources/github/owner/repo1"; then
  fail "sources output missing repo1. Output:\n$sources_out"
fi
if ! echo "$sources_out" | grep -q "sources/github/owner/repo2"; then
  fail "sources output missing repo2. Output:\n$sources_out"
fi

# 9. message with a file path sends the file's contents
echo "Testing: message with file path"
msg_file="$TMPDIR/msg.txt"
echo "Message content from file" > "$msg_file"
: > "$LOGFILE"
bash "$SCRIPT" message s123 "$msg_file" > /dev/null
logged_msg_args="$(cat "$LOGFILE")"
if ! echo "$logged_msg_args" | grep -q "Message content from file"; then
  fail "message command did not send file content. Log:\n$logged_msg_args"
fi

# Additional command coverage: approve and list
echo "Testing: approve"
bash "$SCRIPT" approve s123 > /dev/null

echo "Testing: list"
list_out="$(bash "$SCRIPT" list)"
if ! echo "$list_out" | grep -q "sessions/s123"; then
  fail "list output missing session s123. Output:\n$list_out"
fi

echo "All jules_api tests passed!"
