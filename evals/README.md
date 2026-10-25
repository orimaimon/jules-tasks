# Evals for the jules-tasks skill

Run them after every change to `SKILL.md` or `docs/`, and compare with the skill turned off to see what the skill adds.

- `evals.json`: seven task scenarios in the skill-creator format (`prompt`, `files`, `expectations`). Each one comes from a failure the skill already documents: Jules-or-local triage, writing a wave of prompts (shared files, a key in the notes, an unknown unit), reviewing a PR with planted bugs whose description overstates it, a self-reverting "empty" PR, a wave whose CI never started (billing), a session waiting on a question, and a fix that would race Jules's CI Fixer.
- `trigger-evals.json`: queries that should and should not activate the skill, for tuning the `description`.
- `files/`: the inputs. Everything in them is made up, including the API key in `wave-plan/PLAN.md` (it is there to check that prompts don't copy it). The scenarios work offline: they hand over the git and `gh` output instead of a live repository.

## Running them

The harness runs each eval in a fresh headless `claude -p` session, with and without the skill, then grades each answer blind with a separate judge session against the eval's expectations:

```bash
bash evals/harness/run_all.sh          # all evals, 3 samples per condition
bash evals/harness/run_all.sh 1 5 7    # 1 sample, evals 5 and 7 only
```

Needs `claude` (logged in) and `node`. Every run and every grade is a real model call (about $0.10–0.15 per run). Outputs go to `$EVROOT` (default `$TMPDIR/jules-tasks-evals`).

How it keeps the comparison fair:
- Each run gets a fresh workspace with the input files in `proj/`. In the with-skill condition the skill is installed one level up, in `.claude/skills/jules-tasks/`, **without `evals/`**, so it loads as a skill but the answers aren't readable and the skill isn't in the working tree.
- Tools are limited to reading (`Read`, `Glob`, `Grep`, `ls`, `cat`, `Skill`); nothing can reach GitHub.
- The judge sees the request, the input files, the answer and the expectations, never which condition produced the answer. It must quote evidence for each pass or fail.
- `meta.json` records whether the skill was actually invoked. A with-skill run that didn't invoke it measures the description, not the instructions.

Alternatively, the skill-creator plugin (`/plugin install skill-creator@claude-plugins-official`) reads `evals.json` too, and its description-tuning mode takes `trigger-evals.json`.

## Results so far (October 2026, 3 samples per condition)

| eval | with skill | without |
|---|---|---|
| 1 triage | 29/30 | 24/30 |
| 2 wave prompts | 25/27 | 14/27 |
| 3 review with planted bugs | 38/39 | 36/39 |
| 4 self-revert | 14/15 | 8/15 |
| 5 CI never ran | 14/15 | 4/15 |
| 6 session waiting | 12/12 | 9/12 |
| 7 CI Fixer race | 14/18 | 4/18 |
| **total** | **94%** | **63%** |

What the evals changed in the skill: the description now triggers on short requests about Jules PRs and sessions (before, "Jules's PR #61 … do what I asked" never loaded the skill, and an untriggered run handed out `gh pr merge` commands over a CI that never ran); "merge, never rebase" now also appears where you fix a Jules branch; a rescued self-revert PR is reviewed and merged like any other. Eval 3 barely separates the conditions (code review is strong without the skill); it stays as a regression guard.

## Adding a scenario

When a wave teaches you something new (a row added to `docs/failure-modes.md`), add an eval for it: a short prompt as the user would write it, the smallest files that reproduce the situation, and expectations that are each one checkable statement. Prefer expectations that a reply without the skill would likely miss.
