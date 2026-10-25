#!/usr/bin/env bash
# Read-only mechanical review of a (Jules) PR. Usage:
#   bash review_pr.sh <PR#> [allowed-files.txt]
# allowed-files.txt: one path or glob per line (e.g. src/proxy.ts, tests/*.test.mjs, src/lib/**).
# Requires: git, gh (authenticated), node. Run from inside the repository. Works for JS/TS and Python repos.
# It fetches refs/pull/<n>/head into a local ref and reads; it never checks out, commits or pushes.
set -uo pipefail

PR="${1:-}"
ALLOW="${2:-}"
EXP_ISSUE="${3:-}"
EXP_ISSUE="${EXP_ISSUE#\#}"
if [ -z "$PR" ]; then echo "usage: $0 <PR#> [allowed-files.txt] [expected-issue#]"; exit 2; fi

FAIL=0; WARN=0
fail() { echo "  ❌ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $*"; WARN=$((WARN+1)); }
ok()   { echo "  ✅ $*"; }

JSON="$(gh pr view "$PR" --json number,title,body,state,isDraft,baseRefName,headRefName,headRefOid,additions,deletions,changedFiles,files,statusCheckRollup,author,closingIssuesReferences 2>&1)" \
  || { echo "gh pr view failed: $JSON"; exit 2; }

jget() { node -e "const j=JSON.parse(process.argv[1]);const f=new Function('j','return ('+process.argv[2]+')');const v=f(j);console.log(typeof v==='object'?JSON.stringify(v):v)" "$JSON" "$1"; }

BASE="$(jget 'j.baseRefName')"
HEAD_BRANCH="$(jget 'j.headRefName')"
HEAD_SHA="$(jget '(j.headRefOid||"").slice(0,7)')"
echo "PR #$PR: $(jget 'j.title')"
echo "  author: $(jget 'j.author.login')  state: $(jget 'j.state')  draft: $(jget 'j.isDraft')  base: $BASE  head: $HEAD_BRANCH ($HEAD_SHA)"
# Check if a Jules session embedded in the branch name is still active (e.g. CI Fixer running):
SID="$(echo "$HEAD_BRANCH" | grep -oE '[0-9]{15,22}' | tail -n1 || true)"
if [ -n "$SID" ] && command -v jules >/dev/null 2>&1; then
  SLINE="$(jules remote list --session 2>/dev/null | grep -F "$SID" || true)"
  if echo "$SLINE" | grep -qE '(In Progress|Planning|Queued)'; then
    warn "Jules session $SID is still active ($(echo "$SLINE" | awk '{print $(NF-1), $NF}')) — CI Fixer may push new commits; re-review after it finishes"
  fi
fi
# Jules PRs often omit "Closes #N", or hallucinate a placeholder "Closes #123" at the top while the bot adds "Fixes #189" at the bottom.
CLOSES="$(jget '(j.closingIssuesReferences||[]).map(i=>"#"+i.number).join(" ")')"
CCOUNT_ISSUES="$(jget '(j.closingIssuesReferences||[]).length')"
BODY_CLOSES="$(jget '((j.body||"").match(/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#[0-9A-Za-z_-]+/gi)||[]).join(", ")')"
if [ -z "$CLOSES" ]; then
  warn "closes no issue: add \"Closes #N\" (the dispatched issue) to the PR body${BODY_CLOSES:+ (body has: $BODY_CLOSES)}"
elif [ "${CCOUNT_ISSUES:-0}" -gt 1 ]; then
  warn "closes multiple issues ($CLOSES): check for a hallucinated 'Closes #N' alongside the real issue${BODY_CLOSES:+ (body has: $BODY_CLOSES)}"
else
  echo "  closes: $CLOSES  <- check it is the dispatched issue${BODY_CLOSES:+ (body: $BODY_CLOSES)}"
fi
if [ -n "$EXP_ISSUE" ] && [ "$CLOSES" != "#$EXP_ISSUE" ]; then
  fail "expected PR to close only #$EXP_ISSUE, but closingIssuesReferences is '${CLOSES:-none}'"
fi

REF="refs/remotes/review/pr-$PR"
git fetch -q origin "+refs/pull/$PR/head:$REF" "+refs/heads/$BASE:refs/remotes/review/base" 2>/dev/null \
  || { echo "  could not fetch PR ref; later checks skipped"; exit 1; }
MB="$(git merge-base "refs/remotes/review/base" "$REF")"
FILES="$(git diff --name-only "$MB" "$REF")"

echo "== 1. Size"
ADD="$(jget 'j.additions')"; DEL="$(jget 'j.deletions')"; NF="$(jget 'j.changedFiles')"
if [ "$NF" = "0" ] || [ $((ADD+DEL)) -eq 0 ]; then
  fail "EMPTY PR: 0 changed lines. Whatever the title claims is not in the code."
  CCOUNT="$(git rev-list --count "$MB..$REF" 2>/dev/null || echo 0)"
  if [ "${CCOUNT:-0}" -gt 0 ]; then
    warn "PR has $CCOUNT commit(s) with net 0 diff (self-revert? check if commit N was reverted by N+1):"
    git log --oneline --stat "$MB..$REF" | sed 's/^/     /'
  fi
else
  ok "$NF files, +$ADD -$DEL"
fi
[ -z "$FILES" ] && echo "  (no diff against $BASE: already merged or net-zero revert? later checks see nothing)"

echo "== 2. Files"
echo "$FILES" | sed 's/^/     /'
if [ -n "$ALLOW" ] && [ -f "$ALLOW" ]; then
  OUTSIDE="$(node -e '
    const fs = require("fs");
    const files = process.argv[1].split(/\r?\n/).filter(Boolean);
    const pats = fs.readFileSync(process.argv[2], "utf8")
      .split(/\r?\n/)
      .map(l => l.replace(/#.*/, "").trim())
      .filter(Boolean);
    const toRegex = (p) => {
      let s = p.replace(/[.+^${}()|[\]\\]/g, "\\$&");
      s = s.replace(/\*\*/g, "\0").replace(/\*/g, "[^/]*").replace(/\?/g, "[^/]").replace(/\0/g, ".*");
      return new RegExp("^" + s + "$");
    };
    const regexes = pats.map(toRegex);
    for (const f of files) {
      if (!regexes.some(r => r.test(f))) console.log(f);
    }
  ' "$FILES" "$ALLOW")"
  while IFS= read -r f; do
    [ -n "$f" ] && fail "outside allowlist: $f"
  done <<< "$OUTSIDE"
elif [ -n "$ALLOW" ]; then
  fail "allowlist file not found: $ALLOW"
else
  warn "no allowlist given: pass the task's file list as the second argument"
fi
SENSITIVE='^(package\.json|package-lock\.json|tsconfig\.json|eslint\.config\.[mc]?js|\.github/workflows/|prisma/schema\.prisma|src/types/|src/proxy\.ts|src/lib/auth|Dockerfile|next\.config\.)|(^|/)(requirements[^/]*\.(txt|lock)|pyproject\.toml|uv\.lock|setup\.cfg|conftest\.py|CLAUDE\.md|AGENTS\.md|ROADMAP\.md)$|\.(bat|cmd|ps1)$'
while read -r f; do [ -n "$f" ] && warn "sensitive file touched: $f"; done < <(echo "$FILES" | grep -E "$SENSITIVE" || true)
NEWROOT="$(git diff --name-only --diff-filter=A "$MB" "$REF" | grep -vE '/' | grep -vE '^(README|CHANGELOG|LICENSE)' || true)"
[ -n "$NEWROOT" ] && warn "new files at repo root (junk?): $(echo $NEWROOT)"
while read -r f; do [ -n "$f" ] && warn "stray file: $f"; done < <(git diff --name-only --diff-filter=A "$MB" "$REF" | grep -E '^(prompts?/|tmp/|scratch/)|\.(log|bak|orig)$' || true)

echo "== 3. Risky patterns in added lines"
ADDED="$(git diff -U0 "$MB" "$REF" -- . ':(exclude)package-lock.json' ':(exclude)uv.lock' | grep -E '^\+[^+]' || true)"
PATTERNS=(
  'npx ' '\btsx\b' 'ts-node' 'eslint-disable' 'accept-data-loss' 'force-reset' ': any\b' '@ts-ignore' '@ts-expect-error'
  'test\.skip|it\.skip|describe\.skip|\bx(it|describe|test)\(|\{ ?skip:' 'assert\.ok\(true\)'
  '\.only\('                          # a focused test (it.only/describe.only) silently skips the rest of the file
  'it\.todo|test\.todo'
  'pytest\.mark\.(skip|skipif|xfail)|pytest\.skip\(' '# ?(noqa|type: ?ignore)' 'assert True\b'
  'while True|while ?\(true\)|for ?\(;;\)'   # an unbounded loop around a request = endless traffic when the source fails
  'except[^:]*:[[:space:]]*pass|catch ?(\([^)]*\))? ?\{ ?\}'   # a swallowed error hides blocks and data loss
  'apiKey=|api_key=|[?&](key|token)=' # a key in a URL ends up in logs and error messages
  'verify=False'
)
for pat in "${PATTERNS[@]}"; do
  hits="$(echo "$ADDED" | grep -cE -- "$pat" || true)"
  [ "${hits:-0}" -gt 0 ] && warn "'$pat' appears in $hits added line(s)"
done
# Test files, wherever they live: tests/ and test/ dirs, colocated *.test.* / *.spec.*, __tests__/, test_*.py, *_test.py.
TESTSPEC=('tests/*' 'test/*' '*.test.*' '*.spec.*' '*__tests__/*' '*test_*.py' '*_test.py')
# Tests that sleep for real or reach the network: look at each hit (fine only inside a monkeypatched fake).
TADDED="$(git diff -U0 "$MB" "$REF" -- "${TESTSPEC[@]}" | grep -E '^\+[^+]' || true)"
for pat in 'time\.sleep\(' 'requests\.(get|post)\(' 'urlopen\(' 'yf\.(download|screen)\(' 'fetch\(.https?:'; do
  hits="$(echo "$TADDED" | grep -cE -- "$pat" || true)"
  [ "${hits:-0}" -gt 0 ] && warn "tests: '$pat' in $hits added line(s): real sleep or network?"
done
DELTESTS="$(git diff --name-only --diff-filter=D "$MB" "$REF" -- "${TESTSPEC[@]}" || true)"
[ -n "$DELTESTS" ] && fail "test files deleted: $(echo $DELTESTS)"

echo "== 4. Assert and test counts (test files)"
# JS/TS: assert(...), assert.x(...), expect(...). Python: lines that start with "assert". Tests: def test_ / it( / test( / t.test(.
count()  { git grep -hE "assert(\.[a-zA-Z]+)?\(|expect\(|^[[:space:]]*assert[[:space:](]" "$1" -- "${TESTSPEC[@]}" 2>/dev/null | wc -l | tr -d ' '; }
tcount() { git grep -hE "^[[:space:]]*(async )?def test_|^[[:space:]]*((await[[:space:]]+)?[a-zA-Z_$][a-zA-Z0-9_$]*\.)?(it|test)(\.only)?\(" "$1" -- "${TESTSPEC[@]}" 2>/dev/null | wc -l | tr -d ' '; }
B="$(count "$MB")"; H="$(count "$REF")"; TB="$(tcount "$MB")"; TH="$(tcount "$REF")"
if [ "$H" -lt "$B" ]; then fail "asserts dropped: $B -> $H"; else ok "asserts $B -> $H"; fi
if [ "$TH" -lt "$TB" ]; then fail "tests dropped: $TB -> $TH"; else ok "tests $TB -> $TH"; fi
CODE="$(echo "$FILES" | grep -vE '(^|/)(tests?|__tests__)/|\.(test|spec)\.|(^|/)test_[^/]*\.py$|_test\.py$|\.(md|html|json|csv|txt)$|^$' || true)"
[ "$TH" -eq "$TB" ] && [ "$H" -le "$B" ] && [ -n "$CODE" ] && warn "code changed but no new test or assert"

echo "== 5. Freshness"
BEHIND="$(git rev-list --count "$REF..refs/remotes/review/base")"
if [ "$BEHIND" -gt 0 ]; then
  OVERLAP="$(git diff --name-only "$MB" refs/remotes/review/base | grep -Fxf <(echo "$FILES") || true)"
  if [ -n "$OVERLAP" ]; then warn "$BEHIND commits behind $BASE, and $BASE changed the same files: $(echo $OVERLAP). Merge $BASE in and wait for CI."
  else warn "$BEHIND commits behind $BASE (no shared files; still merge $BASE in and rerun all tests: other PRs' tests can fail on this code)"; fi
else ok "up to date with $BASE"; fi

echo "== 6. CI"
node -e '
const j=JSON.parse(process.argv[1]); const r=j.statusCheckRollup||[];
if(!r.length){console.log("  ⚠️  no checks reported");process.exit(3)}
let bad=0;
for(const c of r){const name=c.name||c.context; const concl=(c.conclusion||c.state||"").toUpperCase(); const st=(c.status||"").toUpperCase();
 const good=["SUCCESS","SKIPPED","NEUTRAL"].includes(concl);
 if(!good) bad++;
 console.log("  "+(good?"✅":"❌")+" "+name+": "+(concl||st||"PENDING"));}
process.exit(bad?1:0)' "$JSON"
case $? in 0) ok "every check concluded success";; 3) WARN=$((WARN+1));; *) fail "not every check concluded success (pending or failing)";; esac

echo "== Summary: $FAIL fail, $WARN warn"
echo "Mechanical checks only. Still review by hand: task steps vs diff, test quality, runtime fit, and the bug classes in SKILL.md section 5."
git update-ref -d "$REF" 2>/dev/null; git update-ref -d refs/remotes/review/base 2>/dev/null
[ $FAIL -gt 0 ] && exit 1 || exit 0
