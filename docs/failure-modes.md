# Known failure modes, and the guard for each

Every row happened in a real wave. When something unexpected happens, look here first; when you learn a new failure, add a row (what happened, in one sentence with the concrete detail, and the guard that would have caught it).

## Topics (rows are in the order they were learned)
- Empty or misleading PRs: empty commit, self-revert, overstated description, wrong `Closes`
- Prompt and spec gaps: production assumptions, unit guesses, slow code, wrong spec followed literally
- Tests: deleted or loosened tests, focused tests, "all tests pass" without running
- Merging: stale base, green alone but red together, pipe hiding a failure, partial or failed CI, billing
- Process: duplicate dispatch, two writers on one branch, a session waiting on a question

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
| An **"empty" PR whose description claims real changes**: Jules committed the work, then a later commit with the *same message* reverted exactly those lines (net diff 0). It happened in 2 of 10 PRs in one wave | Script: empty-diff check. Then list the PR's commits with `--stat`. If commit N is canceled by commit N+1, review commit N, and if it is good, `git revert <the reverting commit>` on the PR branch to restore it, instead of re-dispatching |
| PR body **closes the wrong number** (the old closed PR of a re-dispatched task instead of the new issue) | Script: `Closes` check. Fix it with `gh pr edit --body-file` before merging |
| A fix applied to the API but **not to the sibling page** that loads the same data (a print page still put the secret token in a QR) | List every place that loads the entity (`grep` for the model) in the prompt's Files and in review |
| Merged while **CI showed partial green**, and once with **every job failing** | Merge only when every job's conclusion is `success`. Run the script even on trivial PRs |
| **Every job "failed" in about 2 seconds with 0 steps**, on every PR, even a docs-only one: Actions never started because of a billing or spending-limit problem on a private repo | When all jobs fail at once, read the job annotation (`gh api repos/<r>/check-runs/<job-id>/annotations`) before blaming the code. Billing is the user's to fix, and nothing merges until CI really runs |
| A follow-up fix needs a file **outside the original allowlist**, and Jules would STOP on its own rule | Name the extra file explicitly in the follow-up comment |
| PR says **"all tests pass"**, but the VM couldn't install or run them | A repo setup script that runs the verify commands ([repo-setup.md](repo-setup.md)); check `bash exit` lines in `jules_api.sh activities` |
| A **focused test** (`it.only`, `describe.only`) makes the suite green by running one test | Script: `.only(` pattern. SKILL.md §5 step 3 |
| **You and Jules push to the same PR branch** (CI Fixer or a comment reply runs while you fix or merge) | One writer at a time (SKILL.md §5). `merge_queue.sh` merges only the head it tested (`--match-head-commit`) |
| A session **waits forever** on a question nobody saw | `jules_api.sh status` prints the question in `AWAITING_USER_FEEDBACK`; answer with `message` |
