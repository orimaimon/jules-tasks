# Rules for agents working in this repository

This repository is an agent skill: `SKILL.md` and `docs/` are instructions read by coding agents, `scripts/` are bash tools they run, `evals/` measures the skill.

- Change only the files your task lists. If more are needed, STOP and explain in the PR description.
- Do not edit `SKILL.md`, `docs/`, `evals/evals.json` or this file unless the task names them.
- No new packages or dependencies. Scripts use bash, git, node and curl only.
- Never delete, skip or weaken a test.
- Tests never make real network requests or call real GitHub or Jules APIs: put fakes (`gh`, `curl`) on a temporary `PATH`, and keep every file inside a temporary directory.
- Scripts must keep working on Linux, macOS and Git Bash on Windows.

## Verify before opening a PR (all must pass)

```bash
for f in scripts/*.sh evals/harness/*.sh tests/*.sh; do [ -e "$f" ] && bash -n "$f"; done
shellcheck -S warning scripts/*.sh evals/harness/*.sh   # if missing: sudo apt-get install -y shellcheck
for t in tests/*.test.sh; do [ -e "$t" ] || continue; bash "$t" || exit 1; done
node -e 'JSON.parse(require("fs").readFileSync("evals/evals.json","utf8"))'
```
