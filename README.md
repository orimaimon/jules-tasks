# `jules-tasks` — Agent Skill for Planning, Dispatching, Reviewing & Merging Jules Tasks

An agent skill (`SKILL.md` + helper scripts) for working effectively with **Jules** (Google Labs' asynchronous cloud coding agent that works from GitHub and opens PRs).

## What's Inside

- **[`SKILL.md`](./SKILL.md)** — Complete workflow guide:
  1. Deciding whether a task belongs in Jules or a local agent
  2. Planning parallel task waves without merge conflicts
  3. Prompt template & runtime context checklist
  4. Pre-dispatch verification & dispatching via web UI, GitHub issues (`jules` label), or `jules` CLI
  5. Mechanical + manual PR review checklist (and common Jules bug classes)
  6. Safe serial merge queue workflow
  7. Table of real-world failure modes and their guards
- **[`scripts/review_pr.sh`](./scripts/review_pr.sh)** — Read-only mechanical PR reviewer (checks empty diffs, allowlist violations, sensitive files, risky patterns in added lines, test/assert count drops, branch freshness, and CI status).
- **[`scripts/merge_queue.sh`](./scripts/merge_queue.sh)** — Safe serial PR merger (fetches, merges base into PR in a scratch worktree, runs the full test suite, pushes, waits for CI, marks ready, and merges with `--match-head-commit`).
- **[`scripts/local_ci.sh`](./scripts/local_ci.sh)** — Local CI runner in a throwaway git worktree (with optional throwaway Docker Postgres) for testing a wave of PRs when GitHub Actions is unavailable.

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

You can keep project-specific context (ground rules, CI steps, past lessons) in a local `references/<project>.md` file inside the skill directory.
