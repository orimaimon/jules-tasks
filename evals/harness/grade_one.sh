#!/usr/bin/env bash
# grade_one.sh <cond> <id>: blind judge of one answer against the eval's expectations.
set -uo pipefail
# shellcheck source=/dev/null
source "$(dirname "$0")/isolate.sh"
COND="$1"; ID="$2"; K="$3"; S="$EVROOT"; R="$COND-$ID-$K"; SKILL="$SKILL_ROOT"
node "$(dirname "$0")/extract.js" "$S/out/$R.jsonl" > "$S/out/$R.meta.json"
GP="$(node -e '
const e = require(process.argv[1]).evals.find(x => x.id == process.argv[2]);
const ans = JSON.parse(require("fs").readFileSync(process.argv[3], "utf8")).result;
const files = e.files.map(f => "### " + f + "\n" + require("fs").readFileSync(process.argv[4] + "/" + f, "utf8")).join("\n\n");
process.stdout.write(`You are grading an AI assistant answer against a fixed list of expectations. Be strict: an expectation passes only if the answer clearly satisfies it; a vague or partial mention fails. Judge only the answer text.

## The user request
${e.prompt}

## Input files the assistant had
${files}

## The answer to grade
<answer>
${ans}
</answer>

## Expectations
${e.expectations.map((x, i) => (i + 1) + ". " + x).join("\n")}

Reply with ONLY a JSON array, one object per expectation, in order:
[{"n": 1, "pass": true|false, "evidence": "short quote or reason"}]`);
' "$SKILL/evals/evals.json" "$ID" "$S/out/$R.meta.json" "$SKILL")"
mkdir -p "$S/judge" && cd "$S/judge" && timeout 600 "${ISOLATE[@]}" claude -p "$GP" --no-session-persistence --output-format json --disallowedTools "Bash" "Read" "Glob" "Grep" "Skill" "WebSearch" "WebFetch" "Agent" \
  > "$S/out/$R.grade.raw" 2>&1
node -e '
const raw = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).result;
const m = raw.match(/\[[\s\S]*\]/); const arr = JSON.parse(m[0]);
require("fs").writeFileSync(process.argv[2], JSON.stringify(arr, null, 1));
console.log(process.argv[3], arr.filter(x => x.pass).length + "/" + arr.length);
' "$S/out/$R.grade.raw" "$S/out/$R.grade.json" "$R"
