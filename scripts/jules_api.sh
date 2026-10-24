#!/usr/bin/env bash
# Interact with the Jules REST API (v1alpha) directly from the terminal.
# Unlike the `jules` CLI (0.1.x), this supports:
#   - Creating sessions with automationMode="AUTO_CREATE_PR" (so Jules opens a GitHub PR automatically)
#   - Sending follow-up messages to an active/completed session (sendMessage)
#   - Approving a pending plan (approvePlan)
#   - Checking session status and PR URLs, and showing the question when Jules is waiting for you
#   - Reading the plan before approving it, and the activity log
#   - Downloading the final patch (review it before anything reaches GitHub; pair with --no-auto-pr)
#
# Requires: JULES_API_KEY env var (generate at https://jules.google.com/settings), curl >= 7.76, node.
#
# Usage:
#   JULES_API_KEY=... bash jules_api.sh new <owner/repo> <base-branch> <prompt-file> [--require-plan-approval] [--no-auto-pr]
#   JULES_API_KEY=... bash jules_api.sh message <session-id> <message-text-or-file>
#   JULES_API_KEY=... bash jules_api.sh plan <session-id>        # latest plan, to check against the allowlist
#   JULES_API_KEY=... bash jules_api.sh approve <session-id>
#   JULES_API_KEY=... bash jules_api.sh status <session-id>
#   JULES_API_KEY=... bash jules_api.sh activities <session-id> [last-n]
#   JULES_API_KEY=... bash jules_api.sh patch <session-id> [out.patch]
#   JULES_API_KEY=... bash jules_api.sh list [page-size]
#   JULES_API_KEY=... bash jules_api.sh sources                  # repositories Jules can reach
set -euo pipefail

: "${JULES_API_KEY:?set JULES_API_KEY in your environment (from https://jules.google.com/settings)}"
API="https://jules.googleapis.com/v1alpha"
CMD="${1:-}"
shift || true

norm_id() {
  local id="$1"
  [[ "$id" == sessions/* ]] && echo "$id" || echo "sessions/$id"
}

# --fail-with-body: a non-2xx exits non-zero but still prints the API's error message
# (with plain -f a wrong repo name or branch just says "error: 400").
# Callers capture the output with $(...), so on failure the body goes to stderr where it is seen.
api_get() {
  local out
  out="$(curl -sS --fail-with-body "$API/$1" -H "X-Goog-Api-Key: $JULES_API_KEY")" || { echo "$out" >&2; return 1; }
  echo "$out"
}
api_post() {
  local out
  out="$(curl -sS --fail-with-body -X POST "$API/$1" \
    -H "Content-Type: application/json" \
    -H "X-Goog-Api-Key: $JULES_API_KEY" \
    -d "$2")" || { echo "$out" >&2; return 1; }
  echo "$out"
}

# All activities of a session, oldest first, as one JSON array (follows nextPageToken).
all_activities() {
  local sid="$1" token="" page acc="[]"
  while :; do
    page="$(api_get "$sid/activities?pageSize=100${token:+&pageToken=$token}")" || return 1
    { IFS= read -r token; IFS= read -r acc; } < <(node -e '
      const acc = JSON.parse(process.argv[1]), p = JSON.parse(process.argv[2]);
      const all = acc.concat(p.activities || []);
      all.sort((a, b) => String(a.createTime).localeCompare(String(b.createTime)));
      console.log(p.nextPageToken ? encodeURIComponent(p.nextPageToken) : "");
      console.log(JSON.stringify(all));
    ' "$acc" "$page")
    [ -z "$token" ] && break
  done
  echo "$acc"
}

case "$CMD" in
  new)
    REPO="${1:?usage: jules_api.sh new <owner/repo> <base-branch> <prompt-file> [--require-plan-approval] [--no-auto-pr]}"
    BASE="${2:?missing <base-branch>}"
    PFILE="${3:?missing <prompt-file>}"
    shift 3
    APPROVAL="false"; MODE="AUTO_CREATE_PR"
    for opt in "$@"; do
      case "$opt" in
        --require-plan-approval) APPROVAL="true" ;;
        --no-auto-pr) MODE="AUTOMATION_MODE_UNSPECIFIED" ;;   # finish without a PR; fetch the diff with `patch`
        *) echo "unknown option: $opt" >&2; exit 2 ;;
      esac
    done
    [ -f "$PFILE" ] || { echo "prompt file not found: $PFILE" >&2; exit 2; }

    BODY="$(node -e '
      const fs = require("fs");
      const prompt = fs.readFileSync(process.argv[1], "utf8").trim();
      const firstLine = prompt.split(/\r?\n/)[0].slice(0, 120);
      const repo = process.argv[2];
      const base = process.argv[3];
      const requirePlanApproval = process.argv[4] === "true";
      const automationMode = process.argv[5];
      console.log(JSON.stringify({
        title: firstLine,
        prompt,
        sourceContext: {
          source: "sources/github/" + repo,
          githubRepoContext: { startingBranch: base }
        },
        automationMode,
        requirePlanApproval
      }));
    ' "$PFILE" "$REPO" "$BASE" "$APPROVAL" "$MODE")"

    api_post sessions "$BODY"
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

    api_post "$SID:sendMessage" "$BODY"
    echo
    ;;

  approve)
    SID="$(norm_id "${1:?usage: jules_api.sh approve <session-id>}")"
    api_post "$SID:approvePlan" '{}'
    echo
    ;;

  status)
    SID="$(norm_id "${1:?usage: jules_api.sh status <session-id>}")"
    RESP="$(api_get "$SID")"
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
    # A session waiting on you stalls silently until you answer: show what it is waiting for.
    STATE="$(node -e 'console.log(JSON.parse(process.argv[1]).state || "")' "$RESP")"
    case "$STATE" in
      AWAITING_USER_FEEDBACK|AWAITING_PLAN_APPROVAL|FAILED)
        ACTS="$(all_activities "$SID")"
        node -e '
          const acts = JSON.parse(process.argv[1]);
          const last = (k) => [...acts].reverse().find(a => a[k]);
          const st = process.argv[2];
          if (st === "AWAITING_USER_FEEDBACK") {
            const m = last("agentMessaged");
            console.log("\nJules is waiting for your answer (reply with: message <id> \"...\"):\n" + (m ? m.agentMessaged.agentMessage : "(no agent message found)"));
          } else if (st === "AWAITING_PLAN_APPROVAL") {
            console.log("\nA plan is waiting for approval: check it with `plan <id>`, then `approve <id>` or `message <id> ...`.");
          } else {
            const f = last("sessionFailed");
            console.log("\nfailed: " + (f ? f.sessionFailed.reason : "(no reason given)"));
          }
        ' "$ACTS" "$STATE"
        ;;
    esac
    ;;

  plan)
    SID="$(norm_id "${1:?usage: jules_api.sh plan <session-id>}")"
    ACTS="$(all_activities "$SID")"
    node -e '
      const acts = JSON.parse(process.argv[1]);
      const a = [...acts].reverse().find(x => x.planGenerated);
      if (!a) { console.error("no plan generated yet"); process.exit(1); }
      const plan = a.planGenerated.plan || {};
      console.log("plan " + (plan.id || "") + " (" + a.createTime + ")");
      const steps = [...(plan.steps || [])].sort((x, y) => (x.index || 0) - (y.index || 0));
      steps.forEach((st, i) => {
        console.log(`\n${i + 1}. ${st.title || ""}`);
        if (st.description) console.log("   " + st.description.replace(/\n/g, "\n   "));
      });
    ' "$ACTS"
    ;;

  activities)
    SID="$(norm_id "${1:?usage: jules_api.sh activities <session-id> [last-n]}")"
    N="${2:-15}"
    ACTS="$(all_activities "$SID")"
    node -e '
      const acts = JSON.parse(process.argv[1]).slice(-Number(process.argv[2]));
      const kinds = ["agentMessaged","userMessaged","planGenerated","planApproved","progressUpdated","sessionCompleted","sessionFailed"];
      for (const a of acts) {
        const k = kinds.find(x => a[x]) || "activity";
        const v = a[k] || {};
        const text = v.agentMessage || v.userMessage || v.title || v.reason || a.description
          || (v.plan ? `${(v.plan.steps || []).length} steps (see: plan <id>)` : "");
        const extra = (a.artifacts || []).map(x => x.bashOutput ? `[bash exit ${x.bashOutput.exitCode}: ${x.bashOutput.command}]` : x.changeSet ? "[patch]" : x.media ? "[media]" : "").filter(Boolean).join(" ");
        console.log(`${a.createTime}  ${(a.originator || "").padEnd(6)}  ${k.padEnd(16)}  ${String(text).split("\n")[0].slice(0, 160)} ${extra}`);
      }
    ' "$ACTS" "$N"
    ;;

  patch)
    SID="$(norm_id "${1:?usage: jules_api.sh patch <session-id> [out.patch]}")"
    OUT="${2:-${SID#sessions/}.patch}"
    ACTS="$(all_activities "$SID")"
    node -e '
      const fs = require("fs");
      const acts = JSON.parse(process.argv[1]);
      let p = null;
      for (const a of acts) for (const x of (a.artifacts || [])) if (x.changeSet && x.changeSet.gitPatch) p = x.changeSet.gitPatch;
      if (!p || !p.unidiffPatch) { console.error("no patch in this session (yet)"); process.exit(1); }
      fs.writeFileSync(process.argv[2], p.unidiffPatch.endsWith("\n") ? p.unidiffPatch : p.unidiffPatch + "\n");
      console.log("wrote " + process.argv[2] + "  base: " + (p.baseCommitId || "?"));
      if (p.suggestedCommitMessage) console.log("suggested message: " + p.suggestedCommitMessage.split("\n")[0]);
      const files = (p.unidiffPatch.match(/^diff --git a\/(\S+)/gm) || []).map(l => l.replace(/^diff --git a\//, ""));
      console.log("files:\n  " + files.join("\n  "));
    ' "$ACTS" "$OUT"
    ;;

  list)
    SIZE="${1:-20}"
    RESP="$(api_get "sessions?pageSize=$SIZE")"
    node -e '
      const j = JSON.parse(process.argv[1]);
      for (const s of (j.sessions || [])) {
        const pr = ((s.outputs || []).find(o => o.pullRequest) || {}).pullRequest;
        console.log(`${s.name}\t${s.state || "?"}\t${pr ? pr.url : "(no-pr)"}\t${s.title || ""}`);
      }
    ' "$RESP"
    ;;

  sources)
    RESP="$(api_get "sources?pageSize=100")"
    node -e '
      const j = JSON.parse(process.argv[1]);
      for (const s of (j.sources || [])) console.log(s.name);
    ' "$RESP"
    ;;

  *)
    echo "usage: $0 {new|message|plan|approve|status|activities|patch|list|sources} ..." >&2
    exit 2
    ;;
esac
