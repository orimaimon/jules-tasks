# Dispatching and steering Jules from the terminal

## Contents
- Which tool to use
- `jules_api.sh` (REST API) commands
- Plan approval for risky tasks
- Answering a waiting session
- The `jules` CLI
- Reviewing a wave as patches before anything reaches GitHub

## Which tool to use

| Need | Use |
|---|---|
| Jules opens a PR when done | `jules_api.sh new` (default `AUTO_CREATE_PR`) or a `jules`-labelled issue |
| See the plan before any code | `jules_api.sh new ... --require-plan-approval`, then `plan`, then `approve` |
| Keep results off GitHub until reviewed | `jules_api.sh new ... --no-auto-pr`, then `patch`; or the `jules` CLI |
| Several attempts at one tricky bug | `jules remote new --parallel N` (up to 5), compare the patches |
| Follow-up instruction, or answer a question | `jules_api.sh message`, or a PR comment once a PR exists |

Sessions created by the `jules` CLI finish as "Completed" **without opening a PR**: the API's `automationMode` defaults to `AUTOMATION_MODE_UNSPECIFIED` ("no automation"), only `AUTO_CREATE_PR` opens a branch and PR, and the CLI has no flag for it (checked against the CLI reference; re-check `jules remote new --help` after an upgrade).

## `jules_api.sh` commands

Needs `JULES_API_KEY` (from https://jules.google.com/settings), `curl` ≥ 7.76 and `node`. The first line of the prompt file becomes the session title, so start it with a tag like `[Proj J03] …`.

```bash
API="bash <skill-dir>/scripts/jules_api.sh"
export JULES_API_KEY=...

$API sources                                        # repositories Jules can reach (sources/github/<owner>/<repo>)
$API new <owner/repo> <base-branch> prompt.txt      # opens a draft PR when done
$API new <owner/repo> <base-branch> prompt.txt --require-plan-approval --no-auto-pr
$API status <session-id>                            # state, PR link; prints the question or failure reason if any
$API plan <session-id>                              # the latest plan, step by step
$API approve <session-id>
$API message <session-id> "text"                    # or a file path; for follow-ups and answers
$API activities <session-id> 50                     # recent activity, with each command Jules ran and its exit code
$API patch <session-id> J03.patch                   # the final diff, its base commit and files
$API list 20
```

API errors print the API's own message (a wrong repo name or branch says why), and the command exits non-zero.

## Plan approval for risky tasks

For a security path, a shared file, or a spec you are unsure of, create the session with `--require-plan-approval`. It stops in `AWAITING_PLAN_APPROVAL`. Then:

1. `$API plan <id>`. Check that every file the plan names is in the task's allowlist, and that every step matches the task (no "also refactor X", no step that skips the tests).
2. If it is right, `$API approve <id>`. If not, `$API message <id> "..."` with the correction (name the exact files and the step to drop or change), and check the new plan.

A wrong plan costs one message; a wrong PR costs a review and a re-dispatch.

## Answering a waiting session

A session in `AWAITING_USER_FEEDBACK` has asked a question and stalls until someone answers. `$API status <id>` prints the question. Answer with `$API message <id> "..."`:
- Stay inside the task's allowlist. If the answer is "yes, also change file X", name X explicitly, or Jules will STOP on its own rule.
- If you couldn't answer from the task, the prompt was missing something: add it to the plan file, so the next wave's prompt has it.

## The `jules` CLI

```bash
npm install -g @google/jules && jules login
cat prompt.txt | jules remote new --repo <owner>/<repo>      # --repo . uses the current directory's repo
jules remote new --repo <owner>/<repo> --parallel 3 < prompt.txt
jules remote list --session                                  # status of your sessions
jules remote pull --session <id> > J03.patch                 # download only; do not use --apply in the user's checkout
```

## Reviewing a wave as patches before anything reaches GitHub

When sessions finish without a PR (CLI, or `--no-auto-pr`), use the gap:

1. Download each diff: `jules remote pull --session <id> > J03.patch` or `$API patch <id> J03.patch`.
2. Check each patch's files against its allowlist (`grep '^diff --git' J03.patch`).
3. Apply the whole wave **together** on a scratch worktree from the base: `git worktree add --detach <scratch> origin/<base>`, link `node_modules` with a junction or symlink, `git apply` each patch. Run tsc, lint and the tests once, and judge them by their own exit codes. A clean combined run proves the wave is conflict-free and green as a whole. (`scripts/local_ci.sh` does the worktree-and-steps part for PRs that already exist.)
4. Review each patch as in SKILL.md section 5, steps 2–7.
5. Give the user a list: which sessions to publish as they are (the GitHub icon in the session's web page opens a branch or PR), and for the rest, the follow-up to send with `$API message <id> ...` (or the exact English text to paste into the session's web page). Then review the resulting PRs with `review_pr.sh`, and merge as in SKILL.md section 6.
