# Reviewing and merging without `gh`

Some sessions have `git` (through a proxy) and GitHub MCP tools, but no `gh` CLI, for example a cloud session. `merge_queue.sh` needs `gh`, and `review_pr.sh` needs it for title, `Closes` and CI. Nothing in the review or merge rules changes; only the tools do. Don't skip a check because its script can't run: run the same check another way.

Tool names below are the GitHub MCP server's (`pull_request_read`, `update_pull_request`, `merge_pull_request`); other GitHub integrations have equivalents.

## Review

1. **Mechanical checks:** `review_pr.sh` runs without `gh`, or with `NO_GH=1`: it fetches `refs/pull/<n>/head` with `git` and runs every diff check (empty diff, empty commits, allowlist, sensitive files, risky patterns, test and assert counts, freshness). Set `BASE=<branch>` if the default branch isn't detected.
   ```bash
   NO_GH=1 BASE=master bash <skill-dir>/scripts/review_pr.sh <PR#> allowed-files.txt
   ```
   If even that can't run, do it by hand: `git fetch origin refs/pull/<n>/head:refs/remotes/review/pr-<n>`, then `git diff --stat $(git merge-base origin/<base> review/pr-<n>) review/pr-<n>`, and walk the same list.
2. **What the script skips without `gh`:**
   - `pull_request_read` method `get`: the title, the draft state, and the body. The body must say `Closes #<the dispatched issue>`; fix it with `update_pull_request` `body`.
   - `pull_request_read` method `get_check_runs`: every check run on the head commit must conclude `success`.
3. **CI that never ran:** `get_check_runs` shows every job failed within seconds. The job log may return 404 through the API (`get_job_logs` did), so you can't read the cause there. Recognize the pattern instead: every job on every PR fails within about 2 seconds with no steps, even on a docs-only PR. That points to billing or a spending limit, not the code. Turn CI Fixer off until Actions works, or it pushes empty retry commits. See [failure-modes.md](failure-modes.md).

## Merge

Two ways, both one PR at a time on GitHub. The **tree check** at the end of each is one comparison that proves what landed is exactly what you tested; if it differs, someone else pushed to the base meanwhile, or the merges weren't what you tested: stop and re-test.

**A. Per PR (what `merge_queue.sh` does).** For each PR in the wave's order:

```text
- [ ] git fetch origin; scratch worktree on the PR head; git merge origin/<base> (never rebase)
- [ ] Whole test suite (or local_ci.sh with the project's steps file), judged by its own exit code
- [ ] git push origin HEAD:<pr-branch>; note the pushed SHA
- [ ] pull_request_read get_check_runs on that SHA: every run concluded success
      (or the Actions-down exception in SKILL.md section 6)
- [ ] update_pull_request draft: false   (Jules opens drafts; the merge API refuses a draft)
- [ ] merge_pull_request merge_method: "merge", expectedHeadSha: <the full tested SHA>
- [ ] git fetch origin <base>; git rev-parse origin/<base>^{tree} equals git rev-parse <tested SHA>^{tree}
```

**B. The whole wave in one worktree** (used in a real wave when Actions was down; valid only when the wave's files are disjoint and GitHub makes plain merge commits):

```text
- [ ] For each PR: git fetch origin "+refs/pull/<n>/head:refs/remotes/review/pr<n>"; note the reviewed SHA
- [ ] Scratch worktree on origin/<base>; install once (npm ci or the steps file's install step)
- [ ] For each PR in wave order: git merge --no-ff review/pr<n>, then test, typecheck, lint,
      each judged by its own exit code; stop at the first non-zero
- [ ] Right before merging each PR: git ls-remote origin refs/pull/<n>/head equals the reviewed SHA
- [ ] update_pull_request draft: false, then merge_pull_request merge_method: "merge",
      expectedHeadSha: <the full reviewed SHA>, in the same order
- [ ] After the wave: git fetch origin <base>; git rev-parse origin/<base>^{tree} equals
      the worktree's git rev-parse HEAD^{tree}
```

In B the PR heads are never updated with the base, so the tree check is what replaces re-testing each PR on the moving base. That substitution holds only under the two conditions above.

## CI steps in the project repository

A cloud session can't read a steps file that exists only on one person's machine (`references/<project>-ci-steps.sh` is gitignored). Commit a copy without secrets to the project repository (for example `scripts/ci-steps.sh`, built from the CI workflow), so every session runs the same gate with `STEPS_FILE=scripts/ci-steps.sh bash <skill-dir>/scripts/local_ci.sh <PR#...>`.
