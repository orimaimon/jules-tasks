# `jules-tasks` — Agent Skill for Planning, Dispatching, Reviewing & Merging Jules Tasks

An agent skill (`SKILL.md` + helper scripts) for working effectively with **Jules** (Google Labs' asynchronous cloud coding agent that works from GitHub and opens PRs).

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
