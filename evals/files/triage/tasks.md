# Backlog for acme/screener (Next.js + Prisma + Postgres, GitHub default branch: main)

a. Add a pure function `maxDrawdown(prices: number[]): number` with unit tests, in new files `src/lib/drawdown.ts` and `tests/drawdown.test.ts`.
b. Add a `fees` column to the `trades` table (Prisma schema + migration) and show it in the trades view.
c. Fix the 23 ESLint warnings in `src/lib/**` (no behavior change).
d. Route the live screener's quote requests through the new FMP provider instead of the old one (`src/server/quotes.ts`, the request path every page uses; FMP blocks clients that ask too often).
e. Change the dashboard cards that appear after login, and check them in the browser with my account.
f. Finish the refactor of `src/server/cache.ts` I started on my laptop yesterday (not pushed yet).
g. Read-only audit: list every place the code reads an API key or token, and whether it can reach a log or a URL. Output: a markdown report.
