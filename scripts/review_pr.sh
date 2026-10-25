#!/usr/bin/env bash
# Read-only mechanical review of a (Jules) PR. Usage:
#   bash review_pr.sh <PR#> [allowed-files.txt]
# allowed-files.txt: one path or glob per line (e.g. src/proxy.ts, tests/*.test.mjs, src/lib/**).
# Requires: git, node, and gh (authenticated) for the PR metadata. Run from inside the repository. JS/TS and Python.
# Without gh (e.g. a cloud session that has only git and GitHub MCP tools), or with NO_GH=1, it runs the
# mechanical checks on the diff and skips title, Closes and CI: check those with your GitHub tools.
# BASE (default: the repo's default branch) names the base branch in that mode.
# It fetches refs/pull/<n>/head into a local ref and reads; it never checks out, commits or pushes.
set -uo pipefail

PR="${1:-}"
ALLOW="${2:-}"
if [ -z "$PR" ]; then echo "usage: $0 <PR#> [allowed-files.txt]"; exit 2; fi

FAIL=0; WARN=0
fail() { echo "  ❌ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $*"; WARN=$((WARN+1)); }
ok()   { echo "  ✅ $*"; }

jget() { node -e "const j=JSON.parse(process.argv[1]);const f=new Function('j','return ('+process.argv[2]+')');const v=f(j);console.log(typeof v==='object'?JSON.stringify(v):v)" "$JSON" "$1"; }

NO_GH="${NO_GH:-0}"
if [ "$NO_GH" != "1" ] && ! command -v gh >/dev/null 2>&1; then NO_GH=1; fi
if [ "$NO_GH" = "1" ]; then
  BASE="${BASE:-$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')}"
  BASE="${BASE:-main}"
  echo "PR #$PR  (no gh: mechanical checks only; base: $BASE)"
  echo "  ⚠️  NOT CHECKED (no gh): title, author, draft state, \"Closes #N\", CI. They did not pass; check them with your GitHub tools (pull_request_read get / get_check_runs)."
  WARN=$((WARN+1))
else
  JSON="$(gh pr view "$PR" --json number,title,state,isDraft,baseRefName,headRefName,additions,deletions,changedFiles,files,statusCheckRollup,author,closingIssuesReferences 2>&1)" \
    || { echo "gh pr view failed: $JSON (NO_GH=1 runs the diff checks without it)"; exit 2; }
  BASE="$(jget 'j.baseRefName')"
  echo "PR #$PR: $(jget 'j.title')"
  echo "  author: $(jget 'j.author.login')  state: $(jget 'j.state')  draft: $(jget 'j.isDraft')  base: $BASE  head: $(jget 'j.headRefName')"
  # Jules PRs often omit "Closes #N", or name the wrong issue (one named an unrelated issue number).
  CLOSES="$(jget '(j.closingIssuesReferences||[]).map(i=>"#"+i.number).join(" ")')"
  if [ -z "$CLOSES" ]; then warn 'closes no issue: add "Closes #N" (the dispatched issue) to the PR body'
  else echo "  closes: $CLOSES  <- check it is the dispatched issue"; fi
fi

REF="refs/remotes/review/pr-$PR"
git fetch -q origin "+refs/pull/$PR/head:$REF" "+refs/heads/$BASE:refs/remotes/review/base" 2>/dev/null \
  || { echo "  could not fetch PR ref; later checks skipped"; exit 1; }
MB="$(git merge-base "refs/remotes/review/base" "$REF")"
FILES="$(git diff --name-only "$MB" "$REF")"

echo "== 1. Size"
if [ "$NO_GH" = "1" ]; then
  read -r NF ADD DEL < <(git diff --numstat "$MB" "$REF" | awk '{f++; a+=($1=="-"?0:$1); d+=($2=="-"?0:$2)} END {print f+0, a+0, d+0}')
else
  ADD="$(jget 'j.additions')"; DEL="$(jget 'j.deletions')"; NF="$(jget 'j.changedFiles')"
fi
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
# Empty commits: CI Fixer pushes them when Actions never starts (seen: 3 empty commits in 5 of 7 PRs). Noise, not work.
EMPTY=""
for c in $(git rev-list --no-merges "$MB..$REF"); do
  git diff --quiet "$c^" "$c" 2>/dev/null && EMPTY="$EMPTY $(git log -1 --format='%h(%an)' "$c")"
done
[ -n "$EMPTY" ] && warn "empty commit(s):$EMPTY. CI Fixer noise when Actions never ran? Review the commits that change files; don't close the PR for this."

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
# JS/TS: assert(...), assert.x(...), expect(...). Python: lines that start with "assert". Tests: def test_ / it( / test(.
count()  { git grep -hE "assert(\.[a-zA-Z]+)?\(|expect\(|^[[:space:]]*assert[[:space:](]" "$1" -- "${TESTSPEC[@]}" 2>/dev/null | wc -l | tr -d ' '; }
tcount() { git grep -hE "^[[:space:]]*(async )?def test_|^[[:space:]]*(it|test)(\.only)?\(" "$1" -- "${TESTSPEC[@]}" 2>/dev/null | wc -l | tr -d ' '; }
B="$(count "$MB")"; H="$(count "$REF")"; TB="$(tcount "$MB")"; TH="$(tcount "$REF")"
if [ "$H" -lt "$B" ]; then fail "asserts dropped: $B -> $H"; else ok "asserts $B -> $H"; fi
if [ "$TH" -lt "$TB" ]; then fail "tests dropped: $TB -> $TH"; else ok "tests $TB -> $TH"; fi
CODE="$(echo "$FILES" | grep -vE '(^|/)(tests?|__tests__)/|\.(test|spec)\.|(^|/)test_[^/]*\.py$|_test\.py$|\.(md|html|json|csv|txt)$|^$' || true)"
[ "$TH" -eq "$TB" ] && [ -n "$CODE" ] && warn "code changed but no new test"

echo "== 5. Freshness"
BEHIND="$(git rev-list --count "$REF..refs/remotes/review/base")"
if [ "$BEHIND" -gt 0 ]; then
  OVERLAP="$(git diff --name-only "$MB" refs/remotes/review/base | grep -Fxf <(echo "$FILES") || true)"
  if [ -n "$OVERLAP" ]; then warn "$BEHIND commits behind $BASE, and $BASE changed the same files: $(echo $OVERLAP). Merge $BASE in and wait for CI."
  else warn "$BEHIND commits behind $BASE (no shared files; still merge $BASE in and rerun all tests: other PRs' tests can fail on this code)"; fi
else ok "up to date with $BASE"; fi

echo "== 6. CI"
if [ "$NO_GH" = "1" ]; then
  echo "  ⚠️  NOT CHECKED (no gh): every check run on the head commit must conclude success"
else
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
fi

echo "== Summary: $FAIL fail, $WARN warn"
echo "Mechanical checks only. Still review by hand: task steps vs diff, test quality, runtime fit, and the bug classes in SKILL.md section 5."
git update-ref -d "$REF" 2>/dev/null; git update-ref -d refs/remotes/review/base 2>/dev/null
[ $FAIL -gt 0 ] && exit 1 || exit 0
