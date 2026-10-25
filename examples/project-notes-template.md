# <Project Name>: project notes for Jules tasks

Copy this file to `references/<project>.md` (which is gitignored in the public skill repo) to keep repository-specific rules, runtime facts, and lessons learned.

## Who does what
- Planner / reviewer workflow and language preferences.
- Where start-of-session state and plans live (e.g. `PLAN-*.md`, `ROADMAP.md`).

## What Jules cannot see
- Gitignored files (`.env*`, local plans/notes, screenshots). Never reference them without inlining the relevant parts.
- Unpushed local commits and local database contents.

## Runtime facts to put in the Context section (pick what applies)
- Network constraints (closed network, shared NAT IP, unofficial upstream APIs with block risk).
- Framework versions and breaking changes (e.g. Next.js 16 `src/proxy.ts`, Python version).
- Units, data sizes, and caching guarantees.

## Standing Ground Rules (for every prompt or `AGENTS.md`)
- Change only the listed files; STOP and explain in the PR description if more are needed.
- No new packages or config changes unless requested.
- Never delete, skip, or weaken tests; assertion count must not drop.
- Exact verification commands (`npm test`, `npx tsc --noEmit`, `npm run lint`, `pytest -q`, etc.).

## CI jobs (all must pass before merging)
- List the exact GitHub Actions job names and what they check.
- How to run `scripts/local_ci.sh` if Actions is unavailable. Keep the steps file **in the project repository** (secret-free, e.g. `scripts/ci-steps.sh`, built from the CI workflow), not only here in `references/`: a cloud session can't read your machine, and every session should run the same gate.

## History & lessons learned
- Log notable PR successes and failure modes discovered in this repository.
