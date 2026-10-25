# Known failure modes, and the guard for each

Every row happened in a real wave. When something unexpected happens, look here first; when you learn a new failure, add a row (what happened, in one sentence with the concrete detail, and the guard that would have caught it).

## Topics (rows are in the order they were learned)
- Empty or misleading PRs: empty commit, self-revert, overstated description, wrong `Closes`
- Prompt and spec gaps: production assumptions, unit guesses, slow code, wrong spec followed literally
- Tests: deleted or loosened tests, focused tests, "all tests pass" without running
- Merging: stale base, green alone but red together, pipe hiding a failure, partial or failed CI, billing
- Process: duplicate dispatch, two writers on one branch, a session waiting on a question, no `gh` in the session, CI steps only on one machine
- Spec checks: a schema that blocks a valid case, an existing helper, interacting rules, issue-body formatting

| What happened | Guard |
|---|---|
| A PR merged with an **empty commit**, and the feature in its title doesn't exist | Script: empty-diff check. Never merge without looking at the diff |
| A "small" change **broke production assumptions** (a rate limit that 429s a NAT'ed network; `npx tsx` in the build on a closed network) | Context section in the prompt. SKILL.md §5 step 5 |
| An **endless request loop** and **swallowed 403/429s** against an unofficial or rate-limited source | Request-budget facts in the prompt. Script: `while True`, `except: pass`. [bug-classes.md](bug-classes.md) |
| A **unit guess** shipped (0.75% shown as 75%) | State units in the prompt; check one live sample before dispatch |
| Code that is **correct on 3 rows and takes minutes on real data** | Realistic sizes and a speed test in the prompt |
| Added an **unused dependency** or a network-fetched tool | "No new packages" plus the STOP clause. Script: sensitive files |
| Left **junk in the repo** (patch scripts, prompt files) | Allowlist. Script: stray files |
| **Tests made to pass** by deleting or loosening them, or placeholder tests | Script: assert and test counts. SKILL.md §5 step 3 |
| Description **overstates** what was fixed | Walk the task steps against the diff |
| PR on a **stale base** | Script: behind-base count. Merge the base in, or close and re-dispatch |
| **The same task dispatched twice** by two sessions | List open issues and PRs before dispatching; close the duplicate and its PR |
| **A wrong spec followed literally** (stale columns, a forbidden English word) | Check the spec against helpers and rule-enforcing tests before dispatch (SKILL.md §4); SKILL.md §5 step 6 |
| **Two PRs green alone, red together** | Merge serially: merge the base in, rerun all tests, then merge (SKILL.md §6) |
| **A red branch pushed** because a pipe hid the test failure | Use the test command's own exit code (`merge_queue.sh` does) |
| **PR closes the wrong issue, or none** | Script: `Closes` check; fix the body before merging |
| **Fail-open scope**: a user with no matching grant got empty filter arrays, which the query treated as "no filter", so they saw national data. Also two grant levels were combined with AND instead of OR | For every access check ask: what does an empty or unknown scope return? Require a test where a user without a matching grant gets 403 or nothing |
| An **"empty" PR whose description claims real changes**: Jules committed the work, then a later commit with the *same message* reverted those lines (net diff 0). Root cause observed live on `#208`: when GitHub Actions fails (e.g. 2s billing failure), **CI Fixer** wakes the session up for up to 3 retry cycles after the PR opens, and a retry commit (`9d72d6c`) can revert the initial commit (`82a1fad`). Even worse: if you ran `review_pr.sh` right when commit 1 opened the PR, it saw `+467 -0`, and 60s later CI Fixer pushed the revert | Turn **CI Fixer off** when GitHub Actions is broken at the repo/account level. Wait until `jules remote list --session` shows `Completed` before reviewing (`review_pr.sh` and `merge_queue.sh` check the session ID in the branch name). Script: empty-diff check + `git log --oneline --stat`. If commit N is canceled by N+1, restore commit N with `git revert <the reverting commit>` on the PR branch instead of re-dispatching (never force-push a Jules branch: Jules may still write to it) |
| **PR body closes a hallucinated issue alongside the real one** (`Closes #123` or `Closes #12` at the top, `Fixes #189` at the bottom, or the old closed PR of a re-dispatched task) | Inside the VM, Jules doesn't know its GitHub issue number unless it is literally in the prompt; when the prompt says `Closes #<issue>` without a real number, Jules guesses one while the bot appends `Fixes #<real>`. Dispatch in 2 steps (`gh issue create` without label → inject the real `#N` → `gh issue edit <N> --add-label jules`), pass `[expected-issue#]` to `review_pr.sh`, and fix the body with `gh pr edit --body-file` before merging |
| A fix applied to the API but **not to the sibling page** that loads the same data (a print page still put the secret token in a QR) | List every place that loads the entity (`grep` for the model) in the prompt's Files and in review |
| Merged while **CI showed partial green**, and once with **every job failing** | Merge only when every job's conclusion is `success`. Run the script even on trivial PRs |
| **Every job "failed" in about 2 seconds with 0 steps**, on every PR, even a docs-only one: Actions never started because of a billing or spending-limit problem on a private repo | When all jobs fail at once, read the job annotation (`gh api repos/<r>/check-runs/<job-id>/annotations`) before blaming the code. Billing is the user's to fix. If the job log returns 404 through the API, rely on the pattern: all jobs, all PRs, about 2 seconds. Nothing merges until CI runs, except under the Actions-down exception (SKILL.md §6: explicit approval for this wave, local CI green on the merged wave, tree check) |
| A follow-up fix needs a file **outside the original allowlist**, and Jules would STOP on its own rule | Name the extra file explicitly in the follow-up comment |
| PR says **"all tests pass"**, but the VM couldn't install or run them | A repo setup script that runs the verify commands ([repo-setup.md](repo-setup.md)); check `bash exit` lines in `jules_api.sh activities` |
| A **focused test** (`it.only`, `describe.only`) makes the suite green by running one test | Script: `.only(` pattern. SKILL.md §5 step 3 |
| **You and Jules push to the same PR branch** (CI Fixer or a comment reply runs while you fix or merge) | One writer at a time (SKILL.md §5). `merge_queue.sh` merges only the head it tested (`--match-head-commit`) |
| A session **waits forever** on a question nobody saw | `jules_api.sh status` prints the question in `AWAITING_USER_FEEDBACK`; answer with `message` |
| While Actions was down, **CI Fixer pushed 3 empty retry commits** (same message, about 2 minutes apart) to 5 of 7 PRs in one wave; the other 2 got none, cause unknown (seen once, don't generalize) | `review_pr.sh` flags empty commits. `git diff <first-commit> <head>` empty means the extra commits are noise: review the real commit, don't close or "rescue" the PR. Turn CI Fixer off while Actions is broken |
| A **schema in the task's path blocked a valid case**: `.min(1)` on a weekly report's items meant a week with no defects could never be dispatched, and the prompt would have had Jules build exactly that | Read the schemas and validators the task goes through before dispatch (SKILL.md §4); put the schema change into the task's files explicitly |
| A prompt would have **re-specified a helper that already existed** (`resolveEffectiveFunctionPositions`) | Search for the helpers a task needs before writing it; name the existing one in the prompt |
| **Two rules in one prompt contradicted each other in the tests** ("same level only" plus "an inherited custom position") | Give the fixture's exact field values when rules interact (`level: "BATTALION"`) (SKILL.md §3) |
| **A nested backtick broke the issue body** (`` `${a}: ${b}` `` inside inline code) | Placeholders like `"<label>: <detail>"`, or a fenced block (SKILL.md §3) |
| **No `gh` in a cloud session**, so `review_pr.sh` and `merge_queue.sh` couldn't run as they were | `review_pr.sh` runs the diff checks without `gh` and marks the rest NOT CHECKED; merge with the GitHub tools ([without-gh.md](without-gh.md)) |
| The **CI steps file lived only on one machine** (`references/`), so a cloud session rebuilt the steps from the workflow file | Commit a secret-free copy of the steps file to the project repo (e.g. `scripts/ci-steps.sh`) |
| **`gh` was installed but blocked**: `gh pr view` failed with HTTP 403 (GraphQL not available in a cloud session), and `review_pr.sh` stopped instead of reviewing | `review_pr.sh` falls back to the no-`gh` checks when `gh pr view` fails; get CI and the PR body from the GitHub tools ([without-gh.md](without-gh.md)) |
| **Tests passed but didn't check severity**: a Jules test asserted a check's message text, so downgrading that check from fail to warn still passed (found only by breaking the script on purpose) | Review step 3: break one checked behavior and confirm the test fails; assert the ❌/⚠️ prefix, not just the text |
