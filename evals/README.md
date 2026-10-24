# Evals for the jules-tasks skill

Run them after every change to `SKILL.md` or `docs/`, and compare with the skill turned off to see what the skill adds.

- `evals.json`: seven task scenarios in the skill-creator format (`prompt`, `files`, `expectations`). Each one comes from a failure the skill already documents: Jules-or-local triage, writing a wave of prompts (shared files, a key in the notes, an unknown unit), reviewing a PR with planted bugs whose description overstates it, a self-reverting "empty" PR, a wave whose CI never started (billing), a session waiting on a question, and a fix that would race Jules's CI Fixer.
- `trigger-evals.json`: queries that should and should not activate the skill, for tuning the `description`.
- `files/`: the inputs. Everything in them is made up, including the API key in `wave-plan/PLAN.md` (it is there to check that prompts don't copy it). The scenarios work offline: they hand over the git and `gh` output instead of a live repository.

## Running them

With the skill-creator plugin in Claude Code:

```text
/plugin install skill-creator@claude-plugins-official
```

Then ask it to run the evals for `jules-tasks` (with and without the skill), grade them against the expectations, and open the review viewer. Its description-tuning mode takes `trigger-evals.json`.

Without the plugin: for each eval, start a fresh session in the skill's directory, paste the `prompt`, and check the reply against `expectations` by hand. For the baseline, turn the skill off in settings:

```json
{ "skillOverrides": { "jules-tasks": "off" } }
```

## Adding a scenario

When a wave teaches you something new (a row added to `docs/failure-modes.md`), add an eval for it: a short prompt as the user would write it, the smallest files that reproduce the situation, and expectations that are each one checkable statement. Prefer expectations that a reply without the skill would likely miss.
