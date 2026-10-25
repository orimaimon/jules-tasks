---
name: jules-tasks
description: Plan, write, dispatch and review tasks for Jules (Google Labs' asynchronous cloud coding agent that works from GitHub and opens PRs). Use this whenever the user mentions Jules, wants to hand work to a cloud agent or "the free agent", asks for prompts to paste into jules.google.com or for GitHub issues labelled `jules`, asks to split a plan into parallel PR-sized tasks, asks whether a task should go to Jules or to a local agent, asks to review, approve, fix or merge PRs opened by Jules or google-labs-jules[bot] (one at a time or as a whole wave), or asks to answer or steer a running Jules session. Use it even when the request is short ("merge them", "do what I asked") and the details are in a file or earlier in the conversation. Also use it when reviewing any agent-authored PR whose description claims more than its diff shows.
---

# Jules tasks: deciding, writing, dispatching, reviewing, merging

Jules is an asynchronous cloud agent. It clones the repository **from GitHub**, works in its own VM, and opens a PR. It does what the prompt literally says, quickly and in parallel, but it knows nothing about the project beyond what it can read in the repository and in the prompt. Almost every Jules failure seen so far comes from that gap: correct code for the wrong world (a rate limit that locks out a whole NAT'ed network, a unit guess that shows a 0.75% dividend as 75%, a retry loop that hammers a source that is already blocking us), or an honest-looking PR with nothing in it.

The job is therefore: pick tasks that survive the gap, write prompts that close it, check the prompt against the repository before sending it, review the result against the code (never against the PR description), and merge a wave without breaking the base branch.

**Rules that hold in every step:**
- The PR description is a claim, not evidence. Judge the diff, the tests and the CI jobs.
- No two tasks in one wave touch the same file.
- No secrets, personal data or real user identifiers in prompts or issues.
- Review and merge in a scratch worktree, never in the user's checkout.
- Merge one PR at a time, on a green suite judged by the test command's own exit code.
- One writer per PR branch: you or Jules, never both at once.

**Files in this skill** (`<skill-dir>` is this directory; in Claude Code it is `${CLAUDE_SKILL_DIR}`):
- `references/<project>.md`: the user's private notes for a repository (rules, CI jobs, pitfalls). If one exists for the current project, read it first.
- [docs/repo-setup.md](docs/repo-setup.md): one-time setup of a repository for Jules (`AGENTS.md`, setup script, settings that change how a wave behaves). Read before the first wave in a repo.
- [docs/cli-and-api.md](docs/cli-and-api.md): dispatching and steering sessions from the terminal (`jules_api.sh`, the `jules` CLI), plan approval, and reviewing a whole wave as patches before anything reaches GitHub.
- [docs/bug-classes.md](docs/bug-classes.md): the bugs Jules keeps producing that its own tests don't catch. Read during every review (step 4 in section 5).
- [docs/without-gh.md](docs/without-gh.md): reviewing and merging when there is no `gh` CLI (a cloud session with only `git` and GitHub tools).
- [docs/failure-modes.md](docs/failure-modes.md): every failure seen so far and the guard for it. Read when something unexpected happens, and add a row when you learn a new one.
- `scripts/`: `review_pr.sh` (read-only mechanical review), `merge_queue.sh` (serial merge), `jules_api.sh` (REST client), `local_ci.sh` (CI stand-in when Actions can't run). Run them; don't read them into context.
- `evals/`: test scenarios for this skill (see `evals/README.md`).

---

## 1. Jules or a local agent?

Plan files are usually gitignored. If you don't have the plan, ask the user for it before triage instead of reconstructing it from issues and commits.

Send to **Jules** when all of these hold:
- The change fits in one PR that a reviewer can read in a few minutes (roughly ≤ 10 files, one concern).
- The files it touches are known in advance and nobody else is editing them right now.
- It needs nothing that exists only on the local machine: no uncommitted or unpushed work, no gitignored plan or notes files, no local database contents, no local secrets.
- It needs no interactive decision mid-way (no `db push` that needs approval, no "ask me before X").
- It can be verified by commands Jules can run itself (tests, tsc, lint, build, a scenario script) or by reading the diff.

Good Jules work: **a new module with its tests in new files** (the most reliable kind: a provider, a pure calculation, a data layer with a clear API), lint and dead-code cleanup, adding or tightening tests, docs, CI configuration, small isolated bug fixes with a clear root cause, mechanical refactors in one module, read-only audits that end in a report (one file or one question per audit: a single audit over a whole set of docs found three issues and missed a contradiction).

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
- **Order against local work.** Jules branches from GitHub's default branch. Keep files a local session is about to edit out of the wave: Jules writes the module in a new file, and the local session wires it in. If both must touch a file, merge the Jules PR first, or have the local agent merge `origin/<default>` at its start, and say which in both prompts.
- **Product decisions before prompts.** List the cases the plan leaves open (a week with nothing to report, records from before a rule existed, an export's date range) and ask the user. Jules guesses otherwise, and the guess comes back as code.
- **One concern per PR.** If the prompt says "also", it is probably a second task.
- **Name the wave and the merge order** in the plan. The reviewer follows it.
- **Size the wave to the plan's concurrent-task limit** (see [docs/repo-setup.md](docs/repo-setup.md)). Extra tasks queue.

---

## 3. Writing the prompt

Write the prompt in English, as one self-contained block. Jules can't see gitignored plan files, local notes or this conversation, so anything it needs must be in the block, or in the repository's root `AGENTS.md`, which Jules reads automatically. Standing rules belong in `AGENTS.md`; the prompt carries what is specific to the task.

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
3. <tests to add, with the exact cases, including negative cases and the edge cases in docs/bug-classes.md>

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
- **Every place that loads the entity:** a fix to the API that skips a sibling page loading the same data leaves the bug there. `grep` for the model and list every hit in the files.

Also:
- **No secrets, no personal data, no real user identifiers** in prompts or issues. They go to a third-party service, and issues in a public repo are public. If the plan or notes contain a key, leave it out and describe where the code reads it from.
- **Pure function plus named test cases** make the result checkable without running the app.
- **A mechanical acceptance check** tells Jules what "done" means, and the reviewer runs it.
- **When two rules interact, give exact fixture values.** "Only positions of the same level" plus a test for "an inherited position" contradict each other unless the prompt says the custom position has `level: "BATTALION"`. Spell out the fixture, or Jules writes a test that can't pass.
- **When Jules might "fix" code the task doesn't own**, tell it to test the current behavior, mark the assertion `# BUG?: <why>`, and explain in the PR description instead of changing that code. One wave's Jules flagged a "bug" that was intended behavior and, because of this rule, didn't touch the script.
- **No backticks inside inline code** in an issue body: `` `${a}: ${b}` `` breaks the markdown. Write placeholders such as `"<label>: <detail>"`, or use a fenced block.

---

## 4. Dispatching

First time in this repository? Do [docs/repo-setup.md](docs/repo-setup.md) first. Without a setup script Jules can't run the verify commands, and the PR may still say "all tests pass".

**Before you send anything:**
- **Look for duplicates.** List open issues and PRs (`gh issue list`, `gh pr list`) and search for the same files or topic. Another session once dispatched the same task five minutes earlier, and Jules started both; close the later one (and its PR) at once.
- **Check your spec against the repository.** Jules follows a wrong spec to the letter, and it comes back in the PR as if it were Jules's idea:
  - run the helpers the prompt relies on (a label formatter rendered `1e9` as "1000M"; the fix had to go into the prompt, not into the helper, because saved data stores those labels);
  - read the tests that enforce project rules, and make sure your wording passes them (a "Hebrew for every label" test rejects an English word that the prompt asked for);
  - think through what "everything else comes from X" really includes (one prompt asked for all remaining columns from a days-old snapshot, which pulled in stale technical columns that would fire false signals next to a fresh price);
  - when a fact about an external source is uncertain (a unit, a field name, an endpoint), check it with one tiny live request if the project allows it, or tell Jules to leave it as a constant to be checked before wiring;
  - read the schemas and validators the task goes through: a `.min(1)` on a report's items would have left a week with no defects stuck forever, and Jules would have built it exactly so;
  - search for the helpers the task needs: if one exists (`resolveEffectiveFunctionPositions` did), name it in the prompt so Jules reuses it instead of writing a second one.

**How to send it** (one issue or session per task; title `[Area] outcome`):
- **Pasted into jules.google.com:** one fenced block per task in the plan file.
- **As a GitHub issue with the label that triggers Jules** (e.g. `jules`): the issue body is the prompt, followed by the project's standing "Ground rules" block if they are not in `AGENTS.md`. Inside its VM, Jules doesn't know its own issue number unless the literal number is in the prompt; with a placeholder like `Closes #<issue>` it guesses one (`Closes #123`, `Closes #12`) at the top of the PR body, which can close an unrelated real issue on merge, while its GitHub bot appends the real `Fixes #<N>` at the bottom. So dispatch in two steps: create the issue **without** the label, replace the placeholder with the issue's real number, and only then add the label (`gh issue edit <N> --add-label jules`, or your GitHub tools): Jules starts the moment the label lands. Measured: guessed `Closes` in 7 of 7 PRs with the placeholder (2 of them real, unrelated issues); with the two steps, correct in 4 of 4, 7 of 7 and 3 of 3 in later waves. Jules comments "on it" with a task link, then "Ready for a review! A PR has been created" with the PR number.
- **From the terminal** with `scripts/jules_api.sh` (opens a PR automatically, can require plan approval, answers questions) or the `jules` CLI (no PR; review the patch first). Commands and the patch-review workflow: [docs/cli-and-api.md](docs/cli-and-api.md).
- For a **risky task** (security path, shared file, a spec you are unsure of), require plan approval and check the plan's files and steps before approving. A wrong plan costs one message; a wrong PR costs a review and a re-dispatch.

**While it runs:**
- Jules opens its PR **as a draft** and usually leaves it as a draft; "ready" is its issue comment, not the draft flag.
- A session in `AWAITING_USER_FEEDBACK` has asked a question and **stalls until you answer** (`jules_api.sh status <id>` prints it). If you can't answer it from the task, the prompt was missing something: add it to the plan file too.
- If Jules fails (no PR, or it reports it could not finish): remove the label and add it back once. On a second failure, split the task or do it locally.
- Don't poll. Wait on CI with `gh pr checks <n> --watch` in the background, or schedule a check-in (a recurring prompt that says exactly what to do with each ready PR and when to stop).

---

## 5. Reviewing a Jules PR

Titles and descriptions have overstated what was done and announced features whose commit was empty. Review the diff and the checks, in a clean scratch worktree.

**Before starting the review, verify the session is idle (`Completed`), and always re-review if `headRefOid` changes.** When **CI Fixer** is on and any GitHub check fails (even a 2-second billing failure), Jules wakes the session back up (`In Progress` / `Planning`) ~10 seconds after opening the PR and pushes up to 3 retry commits—which can change or even self-revert the PR after your first look. `review_pr.sh` prints the reviewed short SHA and checks `jules remote list --session` for the session ID embedded in the branch name; if a new commit lands later, re-run `review_pr.sh` and inspect the new diff before merging.

Copy this checklist into your reply and tick it off:

```text
Review #<n>:
- [ ] 1. review_pr.sh with the task's allowlist: every ❌ explained
- [ ] 2. Task steps walked against the diff, all of them
- [ ] 3. Tests: new behavior covered, nothing deleted/skipped/loosened, no .only, verify commands really ran
- [ ] 4. docs/bug-classes.md checked against the diff
- [ ] 5. Runtime fit against the prompt's Context facts
- [ ] 6. Deviations from the spec: Jules's mistake or the spec's?
- [ ] 7. Security path traced / UI looked at / junk removed (where they apply)
- [ ] Verdict: fix on branch | request changes | close
```

**Step 1, the script.** It is read-only and only fetches the PR ref:

```bash
bash <skill-dir>/scripts/review_pr.sh <PR#> [allowed-files.txt] [expected-issue#]
```

No `gh` in this session? The script still runs the diff checks (`NO_GH=1`); get the title, `Closes`, draft state and CI from your GitHub tools ([docs/without-gh.md](docs/without-gh.md)).

It reports: an empty diff (and a self-reverting commit pair); files outside the allowlist; sensitive files (package/lock files, CI, requirements, launchers, `CLAUDE.md`, `AGENTS.md`); risky patterns in added lines (`npx`, `tsx`, `eslint-disable`, `: any`, skips, `.only`, `xfail`, unbounded loops, swallowed errors, a key in a URL, `verify=False`); tests that sleep for real or reach the network; the change in assert and test counts (JS/TS and Python); a missing or suspicious `Closes #N`; how far behind the base it is; and the conclusion of every CI job. If every job failed within seconds with no steps, read [docs/failure-modes.md](docs/failure-modes.md) before blaming the code.

Then by hand, what a script can't see:
2. **Does the diff do what the task asked, all of it?** Walk the task's numbered steps against the diff.
3. **Tests** exercise the new behavior (they would fail on the old code); nothing was deleted, skipped or loosened; no placeholder tests. Prove "would fail" cheaply: break one behavior the test claims to check (a scratch-worktree edit), run it, and see it fail; a test that still passes is checking the wrong thing. For API sessions, `jules_api.sh activities <id> 50` shows whether the verify commands really ran in Jules's VM, with their exit codes.
4. **Bug classes:** go through [docs/bug-classes.md](docs/bug-classes.md) against the diff. Jules's own tests don't catch these.
5. **Runtime fit:** re-read the change against the Context facts. This is where "correct but breaks production" hides.
6. **Is a deviation from the spec a mistake, or was the spec wrong?** Before "fixing" a deviation, find out why Jules did it. Once Jules dropped an English word from a label because a project test forbids it; restoring it as the spec said broke the suite. And re-read your own spec for the bugs you asked for.
7. **Where it applies:** for security-sensitive paths, trace one request end to end and look for fail-open behavior (what does an empty or unknown scope return?) and for keys or tokens that reach logs. For UI changes, run the app with synthetic data and external sources stubbed, open the page, and check the new element, empty values ("—", not "None"/"nan") and the error path. Remove junk: helper scripts, prompt files, generated artifacts, lock-file noise.

**Verdict:**
- **Fix it yourself on the PR branch** when the problem is small and clear (most bug classes): commit on the branch with a message that says what and why, and add a test that fails on the old code. Push to the PR branch, never to the base branch.
- **Request changes** with a short, specific comment on the PR when the fix needs Jules's context (start it with `@Jules` if Reactive Mode is on). Jules reacts with 👀 and pushes a commit to the same PR. If the fix needs a file outside the original allowlist, name it in the comment, or Jules will STOP on its own rule.
- **Never both at once.** Before pushing your own fix, make sure Jules isn't working on the branch (a fresh 👀 on a comment, a CI Fixer run after a red check, or the session `IN_PROGRESS`). Otherwise one push is rejected, or Jules's commit silently undoes yours. When Jules is done, fetch, put your commit on top of its latest head (merge, never rebase or force-push a Jules branch), and review what Jules changed before merging.
- **Close** a PR that is empty, a duplicate, built on a very old base, or describes code that no longer exists. Then re-dispatch with a better prompt. Exception: an "empty" PR whose commit N was reverted by commit N+1 (see [docs/failure-modes.md](docs/failure-modes.md)) can be rescued with `git revert` of the reverting commit; then review it and merge it like any other PR (every CI job green on the new head).

---

## 6. Merging a wave

Merge **one PR at a time**. Each merge makes the rest stale, and tests from one PR can fail on another PR's code even when they share no file (a "no email address in the repo" test from one PR failed on a test fixture another PR had added). For every PR, in the wave's order:

```text
Merge #<n>:
- [ ] git fetch (a stale origin/<base> makes a branch look up to date)
- [ ] Scratch worktree: PR branch + `git merge origin/<base>` (merge, never rebase)
- [ ] Whole test suite, judged by its own exit code (never through a pipe)
- [ ] Pushed to the PR branch; every CI job concluded success
- [ ] PR body says `Closes #<the dispatched issue>`; marked ready
- [ ] `gh pr merge <n> --merge --match-head-commit <tested sha>`
- [ ] Tree check: `git rev-parse origin/<base>^{tree}` equals `git rev-parse <tested sha>^{tree}`
```

Why each line: `pytest -q | tail -1 && git push` pushed a red branch once, because the pipe's status is `tail`'s. Partly green during an Actions outage is not green. Jules often omits `Closes #N` or names the wrong issue. If Jules pushes meanwhile (CI Fixer, a comment reply), your push is rejected or the head changes; start that PR again.

The tree check proves in one line that what landed is exactly what you tested. Without `gh`, do the same steps with your GitHub tools ([docs/without-gh.md](docs/without-gh.md)): mark the draft ready first, because the merge API refuses a draft.

**When GitHub Actions can't run**, the default is to wait. The sign: every job on every PR fails within about 2 seconds with no steps, even on a docs-only PR, so the code is not the cause. On a private repo that is almost always billing or a spending limit: read a job's annotation (`gh api repos/<owner>/<repo>/check-runs/<job-id>/annotations`); if the API returns 404, the pattern is the evidence. Fixing billing is the user's job; tell them. Merge before it runs only with all three: the user's explicit approval **for this wave** (never a standing default), `local_ci.sh` or the same steps green on the serially merged wave (a copy of the steps file committed to the project, so any session can run it), and the tree check after the merges. If a tree differs, stop and re-test. Say in each PR what replaced CI, and turn CI Fixer off until Actions works.

The bundled script does exactly this and stops at the first problem:

```bash
TEST_CMD="python -m pytest tests/ -q" bash <skill-dir>/scripts/merge_queue.sh 92 90 93 91
```

Run it in the background. When the wave is done:
- fast-forward the user's local base branch (only if it is clean), remove scratch worktrees, cancel any scheduled check-in;
- write a **self-contained prompt for the next local session**: `git pull` first, the API of each new module (names, arguments, return shapes), and the decisions made during the wave. The local plan file doesn't update itself, so without this the next session works from a stale plan;
- record in the project notes what was merged and what was learned. A new kind of failure also gets a row in [docs/failure-modes.md](docs/failure-modes.md).
