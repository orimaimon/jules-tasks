# `jules-tasks` — Agent Skill for Planning, Dispatching, Reviewing & Merging Jules Tasks

An agent skill (`SKILL.md` + helper scripts) for working effectively with **Jules** (Google Labs' asynchronous cloud coding agent that works from GitHub and opens PRs).

Jules is fast, free and parallel, so execution stops being the bottleneck. What costs time instead is everything around it: tasks that collide in the same files, prompts that leave out how the code runs in production, PRs whose description claims more than the diff holds, and merges that break the base branch. This skill turns your coding agent (Claude Code, Gemini CLI, Antigravity) into the planner and reviewer around Jules, using rules learned from real waves of Jules PRs.

## How it improves the workflow

Each stage below says what typically goes wrong, what the skill does about it, and what the evals measured. "3/3 vs 0/3" means the expectation was met in 3 of 3 runs with the skill and 0 of 3 without it (details in [What was tested](#what-was-tested)).

**1. Deciding what goes to Jules.** Without the skill, the agent splits work by topic. With it, the split follows Jules's limits: it sees only GitHub, not local state, and it can't make judgment calls mid-task. Schema migrations, edits to a big shared file and work that is still unpushed stay local; new modules with tests, cleanups and audits go to Jules.
- Schema change kept local: 3/3 vs 0/3. The 1,400-line shared page not sent as-is: 3/3 vs 0/3.
- Overlapping file scopes caught before dispatch (`src/lib/**` vs a new file inside it): 2/3 vs 0/3.

**2. Writing the prompts.** Jules does what the prompt says, in a world it can't see. The skill's prompt skeleton states that world: the exact files Jules may change, an order to stop and explain if more are needed, the request budget against a source that blocks clients, the units, realistic data sizes, and a mechanical acceptance check.
- Request budget (shared NAT IP, no retry loops, stop on 429) stated in the prompt: 3/3 vs 0/3.
- Unknown unit verified or left as a constant instead of guessed: 3/3 vs 1/3.
- File allowlist, stop clause, verify commands and acceptance check in every prompt: 2/3 vs 0/3.
- The API key from the plan file never copied into a prompt: met in both conditions.

**3. Dispatching and steering.** `scripts/jules_api.sh` opens sessions that create a PR automatically, shows the plan before you approve it, prints the question a stalled session is waiting on, lists the commands Jules ran with their exit codes, and downloads the diff without opening a PR. [`docs/repo-setup.md`](./docs/repo-setup.md) covers the one-time setup that makes Jules's "all tests pass" claims true (a setup script and `AGENTS.md`).
- Answering a waiting session without letting it edit a file another task in the wave owns: met in both conditions. Recording the missing fact so the next prompt includes it: 3/3 vs 0/3.

**4. Reviewing.** The PR description is treated as a claim, not as evidence. `scripts/review_pr.sh` checks the diff mechanically: an empty or self-reverting diff, files outside the allowlist, deleted or weakened tests, `.only`, unbounded loops, swallowed errors, a wrong `Closes #N`, and CI status. [`docs/bug-classes.md`](./docs/bug-classes.md) lists the bugs Jules's own tests miss.
- A PR that looks empty because commit N+1 reverted commit N: rescued with `git revert` instead of re-dispatched, 3/3 vs 2/3. Other pages loading the same data checked too: 3/3 vs 0/3.
- Finding planted bugs in a diff is strong even without the skill (38/39 vs 36/39). Here the skill adds the mechanical checks, not better reading.

**5. Merging a wave.** PRs are merged one at a time: the base branch merged into each PR, the whole test suite judged by its own exit code, every CI job green, and the merge pinned to the tested commit. `scripts/merge_queue.sh` does this and stops at the first problem.
- Every CI job "failed" in 2 seconds with no steps run (Actions never started): no merge, billing identified as the cause, 3/3 vs 0/3. Without the skill the CI result was dismissed as noise, and one run handed out `gh pr merge` commands.
- A fix requested while Jules's CI Fixer was pushing to the same branch: no concurrent push, 3/3 vs 0/3. Merge only on green CI, pinned to the tested commit: 3/3 vs 0/3.

**6. Learning between waves.** Each new failure becomes a row in [`docs/failure-modes.md`](./docs/failure-modes.md) and, ideally, a new eval, so the next wave avoids it.

## What's Inside

- **[`SKILL.md`](./SKILL.md)** — The workflow, loaded when the skill triggers: Jules or local, planning a wave, the prompt skeleton, dispatching, the review checklist, and the serial merge checklist.
- **[`docs/`](./docs/)** — Detail loaded only when needed:
  - [`repo-setup.md`](./docs/repo-setup.md): one-time repository setup (`AGENTS.md`, setup script, CI Fixer, Reactive Mode, Memory, limits)
  - [`cli-and-api.md`](./docs/cli-and-api.md): `jules_api.sh` and the `jules` CLI, plan approval, answering a waiting session, reviewing a wave as patches
  - [`bug-classes.md`](./docs/bug-classes.md): bugs Jules keeps producing that its own tests miss, and what to check in the diff
  - [`failure-modes.md`](./docs/failure-modes.md): every failure seen so far and its guard
- **[`evals/`](./evals/)** — Seven scenario evals (skill-creator `evals.json` format) with offline fixtures, plus trigger queries for tuning the description. See [`evals/README.md`](./evals/README.md).
- **[`scripts/jules_api.sh`](./scripts/jules_api.sh)** — Terminal client for the Jules `v1alpha` REST API (`new` with `automationMode: "AUTO_CREATE_PR"` or `--no-auto-pr`, `plan` to read a plan before `approve`, `message` for follow-ups and answers, `status` that shows what a waiting session asks, `activities` with the commands Jules ran and their exit codes, `patch` to download the diff, `list`, and `sources`).
- **[`scripts/review_pr.sh`](./scripts/review_pr.sh)** — Read-only mechanical PR reviewer (checks empty diffs & net-zero self-reverts, cross-platform glob allowlists, sensitive files, risky patterns in added lines (including focused `.only` tests and empty catch blocks), test/assert count drops across `tests/` and colocated test files, branch freshness, and CI status).
- **[`scripts/merge_queue.sh`](./scripts/merge_queue.sh)** — Safe serial PR merger (fetches, merges base into PR in a cleaned-up scratch worktree, runs the full test suite, pushes, verifies CI via JSON rollup, marks ready, and merges with `--match-head-commit`).
- **[`scripts/local_ci.sh`](./scripts/local_ci.sh)** — Local CI runner in a throwaway git worktree (with optional throwaway Docker Postgres) for testing a wave of PRs when GitHub Actions is unavailable.
- **[`examples/`](./examples/)** — Templates for project-specific notes (`project-notes-template.md`) and `local_ci.sh` step definitions (`example-ci-steps.sh`).

## What was tested

**The skill itself (A/B evals).** Seven scenarios, each built on a failure documented in the skill, were run in fresh headless `claude -p` sessions, 3 times with the skill installed and 3 times without it. A separate judge session graded each answer against fixed expectations. The judge didn't know which condition produced the answer and had to quote evidence for each verdict. The skill was installed without its `evals/` folder, so runs couldn't read the expected answers.

| Scenario | With skill | Without |
|---|---|---|
| 1. Triage: Jules or local | 29/30 | 24/30 |
| 2. Writing a wave of prompts from a plan | 25/27 | 14/27 |
| 3. Reviewing a PR with planted bugs | 38/39 | 36/39 |
| 4. "Empty" PR that reverted itself | 14/15 | 8/15 |
| 5. Merging when CI never ran | 14/15 | 4/15 |
| 6. A session waiting on a question | 12/12 | 9/12 |
| 7. Fix and merge during a CI Fixer run | 14/18 | 4/18 |
| **Total** | **94%** | **63%** |

The skill triggered in 21 of 21 runs where it was installed.

The evals also found problems that are now fixed:
- **Short requests didn't load the skill.** "Jules's PR #61 … do what I asked" never triggered it, so the `description` was widened.
- **A rebase instead of a merge.** One run rebased a Jules branch even after reading the skill, because the merge-never-rebase rule appeared only in the merge section.
- **A missing step after a rescue.** Nothing said to review a rescued PR and wait for CI before merging it.

Where the skill is still weaker than the baseline:
- **Keeping two tasks that share a test file in separate waves:** 2/3 vs 3/3.
- **Re-reviewing after Jules pushes a new head:** 1/3 vs 2/3.

**Caveats:**
- 3 samples per condition is a small sample.
- Three expectations were reworded after seeing answers, so they measure behavior rather than exact phrasing.
- Scenarios 1–3 ran on a slightly earlier SKILL.md: before the wider description and the one added line.

Treat 94% vs 63% as an estimate. Rerun it after every change:

```bash
bash evals/harness/run_all.sh   # needs claude (logged in) and node; about $0.10-0.15 per run, plus grading
```

Methodology and fixtures: [`evals/README.md`](./evals/README.md).

**The scripts.**
- `review_pr.sh` ran against a local fixture repository with a stubbed `gh`. It caught a file outside the allowlist, a deleted test file, dropped asserts, `.only`, a `while True` loop, swallowed errors and a junk file at the repo root.
- `jules_api.sh` ran against a stubbed `curl` serving recorded API responses. That covered pagination, plan output, waiting-question output, patch download, unknown options and error bodies.
- `merge_queue.sh` and `local_ci.sh` were syntax-checked, and their default-branch detection was tested.
- `claude plugin validate` passes on the skill directory.
- **Not tested against live services:** the real Jules API, and a real merge against GitHub.

## Installation

Clone this repository into your agent's skills directory:

### Claude Code
```bash
git clone https://github.com/orimaimon/jules-tasks.git ~/.claude/skills/jules-tasks
```

### Google Antigravity / Gemini CLI
```bash
git clone https://github.com/orimaimon/jules-tasks.git ~/.gemini/config/skills/jules-tasks
```

## Project-Specific Notes (Optional)

You can keep project-specific context (ground rules, CI steps, past lessons) in a local `references/<project>.md` file inside the skill directory (`references/` is gitignored so private repo details stay local). See [`examples/project-notes-template.md`](./examples/project-notes-template.md) to get started.
