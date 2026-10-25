# Consistency Audit Report

| Severity | Location | Statement | What is true | Suggested fix |
| --- | --- | --- | --- | --- |
| stale | AGENTS.md:16 | `shellcheck -S warning scripts/*.sh evals/harness/*.sh` | `.github/workflows/ci.yml:23` includes `tests/*.sh` and `tests/**/*.sh` in the ShellCheck file array (`files=(scripts/*.sh scripts/**/*.sh evals/harness/*.sh evals/harness/**/*.sh tests/*.sh tests/**/*.sh)`). | Update `AGENTS.md:16` to include `tests/*.sh` in the `shellcheck` command. |
| stale | AGENTS.md:18 | `node -e 'JSON.parse(require("fs").readFileSync("evals/evals.json","utf8"))'` | `.github/workflows/ci.yml:63` validates both `evals/evals.json` and `evals/trigger-evals.json` and checks that all referenced files exist. | Update `AGENTS.md:18` to validate `evals/trigger-evals.json` as well. |
| unclear | README.md:43 | `scripts/jules_api.sh — Terminal client for the Jules v1alpha REST API (new with automationMode: "AUTO_CREATE_PR" or --no-auto-pr, plan to read a plan before approve, message for follow-ups and answers, status that shows what a waiting session asks, activities with the commands Jules ran and their exit codes, patch to download the diff, list, and sources).` | `scripts/jules_api.sh:17,123,240` implements `approve` as a top-level subcommand alongside `new`, `message`, `plan`, `status`, `activities`, `patch`, `list`, and `sources`. | Include `approve` explicitly in the list of subcommands in `README.md:43`. |

## Summary by Category

- Commands, flags, arguments, environment variables, defaults and file paths: 3 findings
- References: none found
- Contradictions: none found
- Numbers: none found

Total: 3 findings
