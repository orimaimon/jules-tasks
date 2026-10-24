---
name: jules-tasks
description: Plan, write, dispatch and review tasks for Jules (Google Labs' asynchronous cloud coding agent that works from GitHub and opens PRs). Use this whenever the user mentions Jules, wants to hand work to a cloud agent or "the free agent", asks for prompts to paste into jules.google.com or for GitHub issues labelled `jules`, asks to split a plan into parallel PR-sized tasks, asks whether a task should go to Jules or to a local agent, or asks to review, approve or merge PRs opened by Jules or google-labs-jules[bot], one at a time or as a whole wave. Also use it when reviewing any agent-authored PR whose description claims more than its diff shows.
---

# Jules tasks: deciding, writing, dispatching, reviewing, merging

Jules is an asynchronous cloud agent. It clones the repository **from GitHub**, works in its own VM, and opens a PR. It does what the prompt literally says, quickly and in parallel, but it knows nothing about the project beyond what it can read in the repository and in the prompt. Almost every Jules failure seen so far comes from that gap: correct code for the wrong world (a rate limit that locks out a whole NAT'ed network, a unit guess that shows a 0.75% dividend as 75%, a retry loop that hammers a source that is already blocking us), or an honest-looking PR with nothing in it.

The job is therefore: pick tasks that survive the gap, write prompts that close it, check the prompt against the repository before sending it, review the result against the code (never against the PR description), and merge a wave without breaking the base branch.

If a project has its own notes in `references/<project>.md`, read them first. They hold the repository's rules, CI jobs and pitfalls.

---

## 1. Jules or a local agent?

Send to **Jules** when all of these hold:
- The change fits in one PR that a reviewer can read in a few minutes (roughly ≤ 10 files, one concern).
- The files it touches are known in advance and nobody else is editing them right now.
- It needs nothing that exists only on the local machine: no uncommitted or unpushed work, no gitignored plan or notes files, no local database contents, no local secrets.
- It needs no interactive decision mid-way (no `db push` that needs approval, no "ask me before X").
- It can be verified by commands Jules can run itself (tests, tsc, lint, build, a scenario script) or by reading the diff.

Good Jules work: **a new module with its tests in new files** (the most reliable kind: a provider, a pure calculation, a data layer with a clear API), lint and dead-code cleanup, adding or tightening tests, docs, CI configuration, small isolated bug fixes with a clear root cause, mechanical refactors in one module, read-only audits that end in a report.

Keep it **local** (a big agent in a clean window) when the task:
- edits a **big file that many features share** (a 1,400-line UI file, a router): split the file first, locally, then give Jules one page;
- wires new code into the running app at a sensitive point (the request path to a provider that can block you, auth, the update mechanism);
- changes the database schema, or needs `db push`/migrations that a person approves;
- spans many modules or needs design judgment mid-way;
- depends on local state: unpushed commits, a running database with real-ish data, or files in `.gitignore`;
- needs browser verification with logins;
- touches security-sensitive paths in more than a one-line way. Jules can do a small, well-specified fix there, but the review must be extra careful (see 5).

When in doubt, split: the module and its tests go to Jules, and wiring it into the app stays local.

---

## 2. Planning a wave of parallel tasks

Jules is free and parallel, so the bottleneck is merge conflicts and review time, not execution.

- **Disjoint files.** Each task lists the exact files it may change, and no two tasks in the same wave share a file. If they must share one, put the second task in a later wave that starts only after the first is merged.
- **Depend on contracts, not on unmerged code.** Two tasks can run in parallel even when one consumes the other's output, if the prompt fixes the interface: "input: a wide DataFrame, index = trading days, columns = tickers". Then check at review time that both sides honor it (one wave had a producer returning plain dates where the consumer expected a `DatetimeIndex`).
- **Order against local work.** Jules branches from GitHub's default branch. If a local agent is about to change the same files, merge the Jules PR first, or have the local agent merge `origin/<default>` at its start, and say which in both prompts.
- **One concern per PR.** If the prompt says "also", it is probably a second task.
- **Name the wave and the merge order** in the plan. The reviewer follows it.

---

## 3. Writing the prompt

Write the prompt in English, as one self-contained block. Jules can't see gitignored plan files, local notes or this conversation, so anything it needs must be in the block.

Use this skeleton. Every section exists because its absence caused a bad PR before.

```text
Repository: <owner>/<repo>, base branch <default>.
Task: <one sentence: the outcome, not the activity>.

Hard rules:
- Change ONLY these files: <exact paths; "(new)" for new files>. Do not touch any other file.
- <project rules that bite here: no new packages; no config changes; never delete or weaken a test; ...>.
- If the task turns out to need a change outside this list, or a rule above blocks you, STOP and explain in the PR description. Do not work around it.

Context (why this matters, and the world the code runs in):
- <the bug or goal, with file:line and the root cause, when known>
- <runtime facts Jules cannot infer: see the list below>

Do this:
1. <concrete steps, naming functions, files and the exact API (names, arguments, return shape)>
2. <for new logic: a pure function in <file> so it can be unit-tested>
3. <tests to add, with the exact cases, including negative cases and the edge cases listed in section 5>

Verify before opening the PR (all must pass): <the test command, lint, build>.
Acceptance: <a mechanical check the reviewer will run, e.g. `grep -n "apiKey" <file>` prints nothing>.
PR description must include: `Closes #<issue>`, the list of changed files, the test summary line.
```

Runtime facts worth stating (pick what applies; each one prevented or would have prevented a real bug):
- **Network:** closed network with no internet at build or run time; many users behind one NAT IP; the source is unofficial and blocks clients that ask too often.
- **Request budget:** every request goes through `<the project's guard>`; one request at a time; no retry loops; a bounded number of attempts; on 403/429 stop at once and raise an exception that carries `status_code`, so the guard can back off.
- **Data safety:** an empty or partial answer must never overwrite good cached data; caches are written atomically.
- **Units:** say the unit of every field ("percent columns hold percent numbers, 5.0 == 5%") and, if you know it, the unit the source sends. If you don't know it, check it once with a tiny live request before writing the prompt (section 4).
- **Size and speed:** the realistic size ("5,000 tickers × 500 days", "a portfolio with 300 trades over 5 years") and a speed test with a time limit. Without it, Jules writes per-row Python loops that take minutes on real data.
- **Paths and secrets:** data paths resolved at call time (tests redirect them), keys read from a file outside the repo, sent in a header and never in a URL (URLs end up in logs and error messages).
- **Keys that are not unique:** "share classes share a company id", "a ticker can appear twice in one file".

Also:
- **No secrets, no personal data, no real user identifiers** in prompts or issues. They go to a third-party service, and issues in a public repo are public.
- **Pure function plus named test cases** make the result checkable without running the app.
- **A mechanical acceptance check** tells Jules what "done" means, and the reviewer runs it.

---

## 4. Dispatching

**Before you send anything:**
- **Look for duplicates.** List open issues and PRs (`gh issue list`, `gh pr list`) and search for the same files or topic. Another session once dispatched the same task five minutes earlier, and Jules started both; close the later one (and its PR) at once.
- **Check your spec against the repository.** Jules follows a wrong spec to the letter, and it comes back in the PR as if it were Jules's idea. Before dispatching:
  - run the helpers the prompt relies on (a label formatter rendered `1e9` as "1000M"; the fix had to go into the prompt, not into the helper, because saved data stores those labels);
  - read the tests that enforce project rules, and make sure your wording passes them (a "Hebrew for every label" test rejects an English word that the prompt asked for);
  - think through what "everything else comes from X" really includes (one prompt asked for all remaining columns from a days-old snapshot, which pulled in stale technical columns that would fire false signals next to a fresh price);
  - when a fact about an external source is uncertain (a unit, a field name, an endpoint), check it with one tiny live request if the project allows it, or tell Jules to leave it as a constant to be checked before wiring.

**How to send it:**
- **Pasted into jules.google.com:** one fenced block per task in the plan file.
- **As a GitHub issue with the label that triggers Jules** (e.g. `jules`): the issue body is the prompt, followed by the project's standing "Ground rules" block (see the project notes). Jules comments "on it" with a task link, then "Ready for a review! A PR has been created" with the PR number.
- One issue per task. Title: `[Area] outcome`.

**While it runs:**
- Jules opens its PR **as a draft** and usually leaves it as a draft; "ready" is its issue comment, not the draft flag.
- If Jules fails (no PR, or it reports it could not finish): remove the label and add it back once. On a second failure, split the task or do it locally.
- Don't poll. Wait on CI with `gh pr checks <n> --watch` in the background, or schedule a check-in (a recurring prompt that says exactly what to do with each ready PR and when to stop).

---

## 5. Reviewing a Jules PR

The PR description is a claim, not evidence. Titles and descriptions have overstated what was done and announced features whose commit was empty. Review the diff and the checks, in a clean scratch worktree, never in the user's checkout (it may hold uncommitted work).

Start with the bundled script. It is read-only and only fetches the PR ref:

```bash
bash <skill-dir>/scripts/review_pr.sh <PR#> [allowed-files.txt]
```

It reports: an empty diff; files outside the allowlist; sensitive files (package/lock files, CI, requirements, launchers, `CLAUDE.md`); risky patterns in added lines (`npx`, `tsx`, `eslint-disable`, `: any`, skips and `xfail`, `while True`, `except: pass`, a key in a URL, `verify=False`); tests that sleep for real or reach the network; the change in assert and test counts (JS/TS and Python); a missing or suspicious `Closes #N`; how far behind the base it is; and the conclusion of every CI job.

Then check by hand what a script can't:
1. **Does the diff do what the task asked, all of it?** Walk the task's numbered steps against the diff.
2. **Tests:** new tests exercise the new behavior (they would fail on the old code), nothing was deleted, skipped or loosened, no placeholder tests.
3. **Runtime fit:** re-read the change against the Context facts. This is where "correct but breaks production" hides.
4. **The bug classes Jules keeps producing, which its own tests don't catch** (each one was found in a real PR):
   - **Unbounded loops around requests:** "step back until a complete period is found" with `while True` sent a request every 0.2 s forever when the source returned errors.
   - **Swallowed blocks:** an HTTP error re-raised without `status_code`, or logged and skipped, so the guard never sees the 403/429 and the run keeps requesting.
   - **Unit guesses:** "values ≤ 1 are fractions, multiply by 100" turned every yield under 1% into 100×.
   - **Good data overwritten by an empty answer** (an empty CSV replaced the cache).
   - **Partial windows treated as full:** `nanmax` over a window with missing bars gave a 30-day-old stock a "250-day breakout"; SMAs need `min_periods` = the window.
   - **Non-unique keys:** a dict keyed by company id kept one of two share classes; duplicate tickers in one file crashed a pivot.
   - **Import-time constants:** a data path captured at import, so tests (and any redirect) wrote into the real data folder.
   - **Per-row Python loops** (`iterrows` over days × tickers × trades) that pass a 3-row test and take minutes on real data. Ask for, or add, a speed test with realistic sizes.
   - **Off-by-one on dates:** a dividend on its ex-date was paid to a buy made that day (the shares held at the end of the previous day get it); a recent day returning nothing was recorded as a holiday forever (data not published yet).
   - **Only the computation is guarded:** the formatting code around it can still raise and break the page; caches without a size limit; duplicated section numbers in docs.
5. **Is a deviation from the spec a mistake, or was the spec wrong?** Before "fixing" a deviation, find out why Jules did it. Once Jules dropped an English word from a label because a project test forbids it; restoring it as the spec said broke the suite. And re-read your own spec for the bugs you asked for.
6. **Security-sensitive paths:** trace one request end to end; look for fail-open behavior and for keys or tokens that reach logs.
7. **UI changes:** look at it. Run the app with synthetic data and the external sources stubbed (no real requests), open the page in a browser, and check the new element, empty values ("—", not "None"/"nan"), and the error path.
8. **Junk:** helper scripts, prompt files, generated artifacts, lock-file noise.

Verdict:
- **Fix it yourself on the PR branch** when the problem is small and clear (most of the bugs above): commit on the branch with a message that says what and why, and add a test that fails on the old code. Push to the PR branch, never to the base branch.
- **Request changes** with a short, specific comment when the fix needs Jules's context. Jules can iterate on the same PR.
- **Close** a PR that is empty, a duplicate, built on a very old base, or describes code that no longer exists. Then re-dispatch with a better prompt.

### Sessions dispatched with the `jules` CLI (no PR yet)
`cat prompt.txt | jules new --repo <owner>/<repo>` starts a session. The first line of the prompt becomes its title, so start it with a tag like `[Proj J03] …`. These sessions finish as "Completed" **without opening a PR**. The reason: the Jules API's session field `automationMode` defaults to `AUTOMATION_MODE_UNSPECIFIED` ("no automation"), only `AUTO_CREATE_PR` opens a branch and PR, and the CLI (0.1.x) has no flag for it. To get PRs automatically, dispatch as GitHub issues labelled `jules`, or call the REST API (`sessions.create` with `automationMode: "AUTO_CREATE_PR"`) using an API key the user sets in an env var themselves. Publishing ("Publish PR") and follow-up messages only exist in the web UI, because the CLI has just `new`, `list`, `pull` and `teleport`. Use the gap to review before anything reaches GitHub:
1. `jules remote list --session` shows the status. `jules remote pull --session <id> > J03.patch` (**without** `--apply`) only downloads the diff.
2. Check each patch's files against its allowlist (`grep '^diff --git'`).
3. Apply the whole wave **together** on a scratch worktree from the base (`git worktree add --detach <scratch> origin/<base>`, link `node_modules` with a junction or symlink, `git apply` each patch). Run tsc, lint and the tests once, and judge them by their own exit codes. A clean combined run proves the wave is conflict-free and green as a whole.
4. Give the user a list: which sessions to publish as they are, and for the rest, the exact English follow-up text to paste into the session. Then review the resulting PRs with the script, and merge as in section 6.

---

## 6. Merging a wave

Merge **one PR at a time**. Each merge makes the rest stale, and tests from one PR can fail on another PR's code even when they share no file (a "no email address in the repo" test from one PR failed on a test fixture another PR had added). So for every PR, in order:

1. `git fetch` first. A stale `origin/<base>` makes a branch look up to date when it isn't.
2. In a scratch worktree: check out the PR branch and `git merge origin/<base>` (merge, never rebase, so Jules can keep working on the branch).
3. Run the **whole** test suite there. Judge it by the test command's own exit code, never through a pipe: `pytest -q | tail -1 && git push` pushed a red branch once, because the pipe's status is `tail`'s.
4. Push to the PR branch, wait for **every** CI job to conclude `success` (`gh pr checks <n> --watch`, then check each job; partly green during an Actions outage is not green).
5. Make sure the PR body says `Closes #<the dispatched issue>` (Jules often leaves it out, or names the wrong issue), mark it ready if it is a draft, and merge with the head you tested: `gh pr merge <n> --merge --match-head-commit <sha>`.

The bundled script does exactly this and stops at the first problem:

```bash
TEST_CMD="python -m pytest tests/ -q" bash <skill-dir>/scripts/merge_queue.sh 92 90 93 91
```

Run it in the background. When the wave is done: fast-forward the user's local base branch (only if it is clean), remove scratch worktrees, cancel any scheduled check-in, and record in the project notes what was merged and what was learned.

---

## 7. Known failure modes (and the guard for each)

| What happened | Guard |
|---|---|
| A PR merged with an **empty commit**, and the feature in its title doesn't exist | Script: empty-diff check. Never merge without looking at the diff |
| A "small" change **broke production assumptions** (a rate limit that 429s a NAT'ed network; `npx tsx` in the build on a closed network) | Context section in the prompt. Review step 3 |
| An **endless request loop** and **swallowed 403/429s** against an unofficial or rate-limited source | Request-budget facts in the prompt. Script: `while True`, `except: pass`. Review step 4 |
| A **unit guess** shipped (0.75% shown as 75%) | State units in the prompt; check one live sample before dispatch |
| Code that is **correct on 3 rows and takes minutes on real data** | Realistic sizes and a speed test in the prompt |
| Added an **unused dependency** or a network-fetched tool | "No new packages" plus the STOP clause. Script: sensitive files |
| Left **junk in the repo** (patch scripts, prompt files) | Allowlist. Script: stray files |
| **Tests made to pass** by deleting or loosening them, or placeholder tests | Script: assert and test counts. Review step 2 |
| Description **overstates** what was fixed | Walk the task steps against the diff |
| PR on a **stale base** | Script: behind-base count. Merge the base in, or close and re-dispatch |
| **The same task dispatched twice** by two sessions | List open issues and PRs before dispatching; close the duplicate and its PR |
| **A wrong spec followed literally** (stale columns, a forbidden English word) | Check the spec against helpers and rule-enforcing tests before dispatch (section 4); review step 5 |
| **Two PRs green alone, red together** | Merge serially: merge the base in, rerun all tests, then merge (section 6) |
| **A red branch pushed** because a pipe hid the test failure | Use the test command's own exit code (`merge_queue.sh` does) |
| **PR closes the wrong issue, or none** | Script: `Closes` check; fix the body before merging |
| **Fail-open scope**: a user with no matching grant got empty filter arrays, which the query treated as "no filter", so they saw national data. Also two grant levels were combined with AND instead of OR | For every access check ask: what does an empty or unknown scope return? Require a test where a user without a matching grant gets 403 or nothing |
| An **"empty" PR whose description claims real changes**: Jules committed the work, then a later commit with the *same message* reverted exactly those lines (net diff 0). It happened in 2 of 10 PRs in one wave | Script: empty-diff check. Then list the PR's commits with `--stat`. If commit N is canceled by commit N+1, review commit N, and if it is good, `git revert <the reverting commit>` on the PR branch to restore it, instead of re-dispatching |
| PR body **closes the wrong number** (the old closed PR of a re-dispatched task instead of the new issue) | Script: `Closes` check. Fix it with `gh pr edit --body-file` before merging |
| A fix applied to the API but **not to the sibling page** that loads the same data (a print page still put the secret token in a QR) | List every place that loads the entity (`grep` for the model) in the prompt's Files and in review |
| Merged while **CI showed partial green**, and once with **every job failing** | Merge only when every job's conclusion is `success`. Run the script even on trivial PRs |
| **Every job "failed" in about 2 seconds with 0 steps**, on every PR, even a docs-only one: Actions never started because of a billing or spending-limit problem on a private repo | When all jobs fail at once, read the job annotation (`gh api repos/<r>/check-runs/<job-id>/annotations`) before blaming the code. Billing is the user's to fix, and nothing merges until CI really runs |
| A follow-up fix needs a file **outside the original allowlist**, and Jules would STOP on its own rule | Name the extra file explicitly in the follow-up comment |
