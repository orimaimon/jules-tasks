# This session

Claude Code cloud session for acme/barracks (default branch: master).
- `git` works through a proxy (fetch and push).
- There is no `gh` CLI (`gh: command not found`).
- GitHub MCP tools are available: pull_request_read (get, get_diff, get_files, get_commits, get_check_runs),
  update_pull_request, merge_pull_request, add_issue_comment.

Wave S4, merge order: #231, #232. Both were dispatched with allowlists:
- #231 (issue #228): src/lib/export/csv.ts (new), tests/export-csv.test.ts (new)
- #232 (issue #229): src/lib/audit/log.ts, tests/audit-log.test.ts

GitHub Actions works in this repo. Verify: `npm ci && npx tsc --noEmit && npm run lint && npm test`.
