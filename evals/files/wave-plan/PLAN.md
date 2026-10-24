# PLAN-quotes.md (gitignored, local only)

Repo: acme/screener, default branch main. Verify: `npm ci && npx tsc --noEmit && npm run lint && npm test`.
Open issues: #40 (J01), #41 (J02), #42 (J03), #43 (J04).

## J01: tests for number labels
Add tests for `formatLargeNumber` in `tests/format.test.ts` (existing file): 950, 1_200, 3_400_000, 1e9, negative values, 0, NaN.

## J02: FMP quote provider
New module `src/providers/fmp.ts` + `tests/fmp.test.ts`. Function `getQuotes(tickers: string[]): Promise<Quote[]>`
where Quote = { ticker, price, changePct }. Endpoint: https://financialmodelingprep.com/api/v3/quote/{tickers}.
Notes: my key is FMP_KEY=8f2c1d9e77ab41c0aa (in .env.local). The free tier allows 300 requests/minute and
returns 429 after that; our office (~40 users) is behind one NAT IP. Not sure if `changesPercentage` comes as
1.25 (=1.25%) or 0.0125. Real usage: up to 2,000 tickers per screen refresh.

## J03: billions label
`formatLargeNumber(1e9)` renders "1000M"; make it "1B". Files: `src/lib/format.ts`, `tests/format.test.ts`.

## J04: split the screener page
Move the results table out of `src/app/page.tsx` (1,400 lines, every feature edits it) into `src/app/ScreenerTable.tsx`.
