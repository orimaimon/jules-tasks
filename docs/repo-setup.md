# Setting up a repository for Jules (once, before the first wave)

Most of this lives in the repository's settings on jules.google.com; `AGENTS.md` lives in the repository itself.

## AGENTS.md

A root `AGENTS.md` holds the standing ground rules and the exact verify commands. Jules reads it automatically when it plans a task, so each prompt carries only what is specific to the task, and the rules don't drift between prompts. Typical content (adapt from the project notes):

```markdown
## Ground rules for agents
- Change only the files the task lists. If more are needed, STOP and explain in the PR description.
- No new packages, no config or CI changes unless the task asks for them.
- Never delete, skip or weaken a test; the assert count must not drop.
- No network calls in tests; no real sleeps.

## Verify before opening a PR (all must pass)
- `npm ci && npx tsc --noEmit && npm run lint && npm test`
```

`review_pr.sh` flags `AGENTS.md` as a sensitive file, so a Jules PR that edits its own rules gets noticed.

## Setup script

In the repo's Configuration on jules.google.com: install dependencies and run the verify commands once. Jules snapshots the environment, so later tasks start fast. Without it, "Verify before opening the PR" is a step Jules can't actually run, and the PR may still say "all tests pass".

Prove it once with a trivial task (for example, "fix one lint warning in <file>") dispatched through `jules_api.sh`, then:

```bash
JULES_API_KEY=... bash <skill-dir>/scripts/jules_api.sh activities <session-id> 50
```

Each command Jules ran shows as `[bash exit <code>: <command>]`. You want to see the verify commands with exit 0.

## Environment variables

Per repository, enabled per task, and fixed once a task starts. Test values only; never production secrets (they reach a third-party VM).

## Settings that change how a wave behaves

- **CI Fixer:** when GitHub Actions fail on a Jules PR, Jules commits a fix and pushes it. Good for lint noise, but it means Jules may push to a branch you are fixing or merging. Keep one writer per branch (SKILL.md section 5); `merge_queue.sh` merges only the head it tested.
- **PR comments:** Jules reads comments on its PRs (👀 reaction) and pushes a commit with the requested change. With **Reactive Mode** on, it acts only on comments that mention `@Jules`. Turn it on if people discuss Jules PRs among themselves, so a remark to a colleague doesn't start a commit.
- **Memory (Knowledge):** Jules keeps preferences and corrections between tasks. Useful, but a stale memory can contradict a prompt. If Jules keeps doing something the prompt forbids, check it.
- **Commit authorship:** Jules only, co-authored, or you only. Pick what the repo's history and CLA need.
- **MCP connections** (Linear, Supabase, Neon and others, via API keys in settings): only connect what tasks need. A connected database is reachable from every task in that repo.

## Limits

Your plan caps concurrent and daily tasks (see the Jules plan page; the numbers change). A wave larger than the concurrent limit queues, which is fine, but don't count on it finishing at once, and leave room for re-dispatches.

## Write it down

Record what you set up in the project notes (`references/<project>.md`, from `examples/project-notes-template.md`): the setup script, the verify commands, which settings are on.
