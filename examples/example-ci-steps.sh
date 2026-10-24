# Example steps file for scripts/local_ci.sh
# Usage (from inside your repository):
#   STEPS_FILE=<skill-dir>/examples/example-ci-steps.sh bash <skill-dir>/scripts/local_ci.sh <PR#...>

NEED_PG=0
# Set NEED_PG=1 if your tests require a throwaway Docker Postgres instance:
# NEED_PG=1
# PG_IMAGE="postgres:16-alpine"
# PG_DB="app_test"

STEPS=(install typecheck lint test build)

step_install()   { npm ci --no-audit --no-fund; }
step_typecheck() { npx tsc --noEmit; }
step_lint()      { npm run lint; }
step_test()      { npm test; }
step_build()     { npm run build; }
