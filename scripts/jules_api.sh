#!/usr/bin/env bash
# Interact with the Jules REST API (v1alpha) directly from the terminal.
# Unlike the `jules` CLI (0.1.x), this supports:
#   - Creating sessions with automationMode="AUTO_CREATE_PR" (so Jules opens a GitHub PR automatically)
#   - Sending follow-up messages to an active/completed session (sendMessage)
#   - Approving a pending plan (approvePlan)
#   - Checking session status and PR URLs
#
# Requires: JULES_API_KEY env var (generate at https://jules.google.com/settings), curl, node.
#
# Usage:
#   JULES_API_KEY=... bash jules_api.sh new <owner/repo> <base-branch> <prompt-file> [--require-plan-approval]
#   JULES_API_KEY=... bash jules_api.sh message <session-id> <message-text-or-file>
#   JULES_API_KEY=... bash jules_api.sh approve <session-id>
#   JULES_API_KEY=... bash jules_api.sh status <session-id>
#   JULES_API_KEY=... bash jules_api.sh list [page-size]
set -euo pipefail

: "${JULES_API_KEY:?set JULES_API_KEY in your environment (from https://jules.google.com/settings)}"
API="https://jules.googleapis.com/v1alpha"
CMD="${1:-}"
shift || true

norm_id() {
  local id="$1"
  [[ "$id" == sessions/* ]] && echo "$id" || echo "sessions/$id"
}

case "$CMD" in
  new)
    REPO="${1:?usage: jules_api.sh new <owner/repo> <base-branch> <prompt-file> [--require-plan-approval]}"
    BASE="${2:?missing <base-branch>}"
    PFILE="${3:?missing <prompt-file>}"
    APPROVAL="false"
    [ "${4:-}" = "--require-plan-approval" ] && APPROVAL="true"
    [ -f "$PFILE" ] || { echo "prompt file not found: $PFILE" >&2; exit 2; }

    BODY="$(node -e '
      const fs = require("fs");
      const prompt = fs.readFileSync(process.argv[1], "utf8").trim();
      const firstLine = prompt.split(/\r?\n/)[0].slice(0, 120);
      const repo = process.argv[2];
      const base = process.argv[3];
      const requirePlanApproval = process.argv[4] === "true";
      console.log(JSON.stringify({
        title: firstLine,
        prompt,
        sourceContext: {
          source: "sources/github/" + repo,
          githubRepoContext: { startingBranch: base }
        },
        automationMode: "AUTO_CREATE_PR",
        requirePlanApproval
      }));
    ' "$PFILE" "$REPO" "$BASE" "$APPROVAL")"

    curl -sS -f -X POST "$API/sessions" \
      -H "Content-Type: application/json" \
      -H "X-Goog-Api-Key: $JULES_API_KEY" \
      -d "$BODY"
    echo
    ;;

  message)
    SID="$(norm_id "${1:?usage: jules_api.sh message <session-id> <message-text-or-file>}")"
    ARG="${2:?missing message text or file}"
    BODY="$(node -e '
      const fs = require("fs");
      const a = process.argv[1];
      const prompt = (fs.existsSync(a) && fs.statSync(a).isFile()) ? fs.readFileSync(a, "utf8").trim() : a;
      console.log(JSON.stringify({ prompt }));
    ' "$ARG")"

    curl -sS -f -X POST "$API/$SID:sendMessage" \
      -H "Content-Type: application/json" \
      -H "X-Goog-Api-Key: $JULES_API_KEY" \
      -d "$BODY"
    echo
    ;;

  approve)
    SID="$(norm_id "${1:?usage: jules_api.sh approve <session-id>}")"
    curl -sS -f -X POST "$API/$SID:approvePlan" \
      -H "Content-Type: application/json" \
      -H "X-Goog-Api-Key: $JULES_API_KEY" \
      -d '{}'
    echo
    ;;

  status)
    SID="$(norm_id "${1:?usage: jules_api.sh status <session-id>}")"
    RESP="$(curl -sS -f "$API/$SID" -H "X-Goog-Api-Key: $JULES_API_KEY")"
    node -e '
      const s = JSON.parse(process.argv[1]);
      console.log("name:  ", s.name);
      console.log("title: ", s.title || "");
      console.log("state: ", s.state || "UNKNOWN");
      console.log("url:   ", s.url || "");
      const outs = s.outputs || [];
      for (const o of outs) {
        if (o.pullRequest) console.log("pr:    ", o.pullRequest.url, "-", o.pullRequest.title);
      }
    ' "$RESP"
    ;;

  list)
    SIZE="${1:-20}"
    RESP="$(curl -sS -f "$API/sessions?pageSize=$SIZE" -H "X-Goog-Api-Key: $JULES_API_KEY")"
    node -e '
      const j = JSON.parse(process.argv[1]);
      for (const s of (j.sessions || [])) {
        const pr = ((s.outputs || []).find(o => o.pullRequest) || {}).pullRequest;
        console.log(`${s.name}\t${s.state || "?"}\t${pr ? pr.url : "(no-pr)"}\t${s.title || ""}`);
      }
    ' "$RESP"
    ;;

  *)
    echo "usage: $0 {new|message|approve|status|list} ..." >&2
    exit 2
    ;;
esac
