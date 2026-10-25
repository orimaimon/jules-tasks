# PLAN-S5.md (gitignored, local only)
Repo: acme/barracks, default branch master. Verify: `npm ci && npx tsc --noEmit && npm run lint && npm test`.

## J07: dispatch the weekly report (issue #240)
Every Friday the company clerk dispatches the weekly deficiencies report to the battalion commander.
Add `dispatchWeeklyReport(input)` in `src/lib/reports/dispatch.ts` (new) with tests in `tests/dispatch.test.ts` (new):
validate the input with `dispatchWeeklyReportSchema`, compute the commander for the company's unit, store the report.
Every week must be dispatched, including weeks with no deficiencies.
Commander lookup: the effective holder of the "battalion commander" function position for the unit (positions can be inherited from the parent unit).
