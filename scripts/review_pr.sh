#!/usr/bin/env bash
# Read-only mechanical review of a (Jules) PR. Usage:
#   bash review_pr.sh <PR#> [allowed-files.txt]
# allowed-files.txt: one path or glob per line (e.g. src/proxy.ts, tests/*.test.mjs, screener/data/fred.py).
# Requires: git, gh (authenticated), node. Run from inside the repository. Works for JS/TS and Python repos.
# It fetches refs/pull/<n>/head into a local ref and reads; it never checks out, commits or pushes.
set -uo pipefail

PR="${1:-}"
ALLOW="${2:-}"
if [ -z "$PR" ]; then echo "usage: $0 <PR#> [allowed-files.txt]"; exit 2; fi

FAIL=0; WARN=0
fail() { echo "  ❌ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $*"; WARN=$((WARN+1)); }
ok()   { echo "  ✅ $*"; }

JSON="$(gh pr view "$PR" --json number,title,state,isDraft,baseRefName,headRefName,additions,deletions,changedFiles,files,statusCheckRollup,author,closingIssuesReferences 2>&1)" \
  || { echo "gh pr view failed: $JSON"; exit 2; }

jget() { node -e "const j=JSON.parse(process.argv[1]);const f=new Function('j','return ('+process.argv[2]+')');const v=f(j);console.log(typeof v==='object'?JSON.stringify(v):v)" "$JSON" "$1"; }

BASE="$(jget 'j.baseRefName')"
echo "PR #$PR: $(jget 'j.title')"
echo "  author: $(jget 'j.author.login')  state: $(jget 'j.state')  draft: $(jget 'j.isDraft')  base: $BASE  head: $(jget 'j.headRefName')"
# Jules PRs often omit "Closes #N", or name the wrong issue (one named an unrelated issue number).
CLOSES="$(jget '(j.closingIssuesReferences||[]).map(i=>"#"+i.number).join(" ")')"
if [ -z "$CLOSES" ]; then warn 'closes no issue: add "Closes #N" (the dispatched issue) to the PR body'
else echo "  closes: $CLOSES  <- check it is the dispatched issue"; fi

echo "== 1. Size"
ADD="$(jget 'j.additions')"; DEL="$(jget 'j.deletions')"; NF="$(jget 'j.changedFiles')"
if [ "$NF" = "0" ] || [ $((ADD+DEL)) -eq 0 ]; then fail "EMPTY PR: 0 changed lines. Whatever the title claims is not in the code."; else ok "$NF files, +$ADD -$DEL"; fi

REF="refs/remotes/review/pr-$PR"
git fetch -q origin "+refs/pull/$PR/head:$REF" "+refs/heads/$BASE:refs/remotes/review/base" 2>/dev/null \
  || { echo "  could not fetch PR ref; later checks skipped"; exit 1; }
MB="$(git merge-base "refs/remotes/review/base" "$REF")"
FILES="$(git diff --name-only "$MB" "$REF")"
[ -z "$FILES" ] && echo "  (no diff against $BASE: already merged? later checks see nothing)"

echo "== 2. Files"
echo "$FILES" | sed 's/^/     /'
if [ -n "$ALLOW" ] && [ -f "$ALLOW" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    matched=0
    while IFS= read -r pat; do
      pat="${pat%%#*}"; pat="$(echo "$pat" | xargs)"; [ -z "$pat" ] && continue
      # shellcheck disable=SC2053
      if [[ "$f" == $pat ]]; then matched=1; break; fi
    done < "$ALLOW"
    [ $matched -eq 0 ] && fail "outside allowlist: $f"
  done <<< "$FILES"
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
  'test\.skip|it\.skip|\{ ?skip:' 'assert\.ok\(true\)'
  'pytest\.mark\.(skip|skipif|xfail)|pytest\.skip\(' '# ?(noqa|type: ?ignore)' 'assert True\b'
  'while True'                        # an unbounded loop around a request = endless traffic when the source fails
  'except[^:]*:[[:space:]]*pass'      # a swallowed error hides blocks and data loss
  'apiKey=|api_key=|[?&](key|token)=' # a key in a URL ends up in logs and error messages
  'verify=False'
)
for pat in "${PATTERNS[@]}"; do
  hits="$(echo "$ADDED" | grep -cE -- "$pat" || true)"
  [ "${hits:-0}" -gt 0 ] && warn "'$pat' appears in $hits added line(s)"
done
# Tests that sleep for real or reach the network: look at each hit (fine only inside a monkeypatched fake).
TADDED="$(git diff -U0 "$MB" "$REF" -- 'tests/*' 'test/*' | grep -E '^\+[^+]' || true)"
for pat in 'time\.sleep\(' 'requests\.(get|post)\(' 'urlopen\(' 'yf\.(download|screen)\(' 'fetch\(.https?:'; do
  hits="$(echo "$TADDED" | grep -cE -- "$pat" || true)"
  [ "${hits:-0}" -gt 0 ] && warn "tests: '$pat' in $hits added line(s): real sleep or network?"
done
DELTESTS="$(git diff --name-only --diff-filter=D "$MB" "$REF" | grep -E '(^|/)tests?/|\.test\.' || true)"
[ -n "$DELTESTS" ] && fail "test files deleted: $(echo $DELTESTS)"

echo "== 4. Assert and test counts (tests/)"
# JS/TS: assert(...), assert.x(...), expect(...). Python: lines that start with "assert". Tests: def test_ / it( / test(.
count()  { git grep -hE "assert(\.[a-zA-Z]+)?\(|expect\(|^[[:space:]]*assert[[:space:](]" "$1" -- 'tests/*' 'test/*' 2>/dev/null | wc -l | tr -d ' '; }
tcount() { git grep -hE "^[[:space:]]*(async )?def test_|^[[:space:]]*(it|test)\(" "$1" -- 'tests/*' 'test/*' 2>/dev/null | wc -l | tr -d ' '; }
B="$(count "$MB")"; H="$(count "$REF")"; TB="$(tcount "$MB")"; TH="$(tcount "$REF")"
if [ "$H" -lt "$B" ]; then fail "asserts dropped: $B -> $H"; else ok "asserts $B -> $H"; fi
if [ "$TH" -lt "$TB" ]; then fail "tests dropped: $TB -> $TH"; else ok "tests $TB -> $TH"; fi
CODE="$(echo "$FILES" | grep -vE '(^|/)tests?/|\.(md|html|json|csv|txt)$|^$' || true)"
[ "$TH" -eq "$TB" ] && [ -n "$CODE" ] && warn "code changed but no new test"

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
echo "Mechanical checks only. Still review by hand: task steps vs diff, test quality, runtime fit, and the bug classes in SKILL.md section 4."
git update-ref -d "$REF" 2>/dev/null; git update-ref -d refs/remotes/review/base 2>/dev/null
[ $FAIL -gt 0 ] && exit 1 || exit 0
