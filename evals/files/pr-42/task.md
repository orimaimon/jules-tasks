Dispatched as issue #31 (label `jules`):

Repository: acme/screener-py, base branch main.
Task: Add a dividend-yield provider that fetches yields and caches them.

Hard rules:
- Change ONLY these files: screener/providers/dividends.py (new), tests/test_dividends.py (new). Do not touch any other file.
- No new packages. Never delete or weaken a test.
- If the task turns out to need a change outside this list, STOP and explain in the PR description.

Context:
- The source is unofficial and blocks clients that ask too often. Every request goes through `guard.request()`.
  On 403/429 raise `requests.HTTPError` with the response attached (the guard reads `status_code` and backs off). No retry loops.
- The source sends `yield` in percent: 0.75 means 0.75%. Store percent numbers.
- An empty or partial answer must never overwrite the cache (screener/data/dividends.json). Write the cache atomically.
- Data paths are resolved at call time via `screener.config.data_dir()` (tests redirect it).

Do this:
1. `fetch_yields(tickers) -> dict[str, float]` (pure apart from guard.request).
2. `refresh(tickers)`: fetch, and replace the cache only when every ticker has a value.
3. Tests: percent kept as-is (0.75 -> 0.75), 429 propagates with status_code, empty answer keeps the old cache.

Verify: `python -m pytest -q`. PR description must include `Closes #31`.
