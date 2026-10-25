#!/usr/bin/env bash
# run_one.sh <with|without> <eval-id> <sample>: one isolated headless run in a fresh workspace.
# The skill sits in the workspace root; the run starts in proj/, so it loads as a skill but is not in the working tree.
set -uo pipefail
# shellcheck source=/dev/null
source "$(dirname "$0")/isolate.sh"
COND="$1"; ID="$2"; K="$3"; S="$EVROOT"; SKILL="$SKILL_ROOT"
WS="$S/ws/$COND-$ID-$K"; rm -rf "$WS"; mkdir -p "$WS/proj/evals"
cp -r "$SKILL/evals/files" "$WS/proj/evals/files"
if [ "$COND" = with ]; then
  mkdir -p "$WS/.claude/skills/jules-tasks"
  cp -r "$SKILL/SKILL.md" "$SKILL/docs" "$SKILL/scripts" "$SKILL/examples" "$WS/.claude/skills/jules-tasks/"
fi
PROMPT="$(node -e 'const e=require(process.argv[1]).evals.find(x=>x.id==process.argv[2]);process.stdout.write(e.prompt)' "$SKILL/evals/evals.json" "$ID")"
cd "$WS/proj" && timeout 900 "${ISOLATE[@]}" claude -p "$PROMPT" --no-session-persistence --output-format stream-json --verbose \
    --allowedTools "Read" "Glob" "Grep" "Skill" "Bash(ls:*)" "Bash(cat:*)" \
  > "$S/out/$COND-$ID-$K.jsonl" 2> "$S/out/$COND-$ID-$K.err"
echo "$COND-$ID-$K exit $?"
