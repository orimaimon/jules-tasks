# Bug classes Jules keeps producing

Jules's own tests don't catch these: it writes tests for the behavior it intended, on 3-row inputs, with the network faked to succeed. Each class below was found in a real Jules PR. During review, go through the list against the diff; when writing a prompt, turn the relevant ones into named test cases.

| Class | What it looked like | What to check in the diff |
|---|---|---|
| **Unbounded loop around requests** | "Step back until a complete period is found" with `while True` sent a request every 0.2 s forever when the source returned errors | Every loop that contains a request has a hard bound on attempts and stops on errors |
| **Swallowed blocks** | An HTTP error re-raised without `status_code`, or logged and skipped, so the guard never saw the 403/429 and the run kept requesting | 403/429 propagate as an exception carrying `status_code`; no bare `except`/empty `catch` around requests |
| **Unit guess** | "Values ≤ 1 are fractions, multiply by 100" turned every yield under 1% into 100× | No heuristic unit conversion; the unit comes from the prompt or a documented constant |
| **Good data overwritten by an empty answer** | An empty CSV replaced the cache | Empty or partial results never replace existing data; writes are atomic (temp file + rename) |
| **Partial window treated as full** | `nanmax` over a window with missing bars gave a 30-day-old stock a "250-day breakout" | Rolling windows use `min_periods` = the window; too-short history gives "no value", not a value |
| **Non-unique keys** | A dict keyed by company id kept one of two share classes; duplicate tickers in one file crashed a pivot | Every dict/index/pivot key is really unique, or duplicates are handled on purpose |
| **Import-time constants** | A data path captured at import, so tests (and any redirect) wrote into the real data folder | Paths and config are read at call time |
| **Per-row Python loops** | `iterrows` over days × tickers × trades passed a 3-row test and took minutes on real data | Vectorized or bounded work; a speed test at realistic size with a time limit |
| **Off-by-one on dates** | A dividend on its ex-date was paid to a buy made that day (the shares held at the end of the previous day get it); a recent day returning nothing was recorded as a holiday forever (data not published yet) | Inclusive/exclusive boundaries match the domain; "no data yet" is not cached as "no data ever" |
| **Only the computation is guarded** | The formatting code around a guarded calculation could still raise and break the page | The try/except or error boundary covers rendering too |
| **Unbounded caches** | A cache keyed by request with no size limit | Every cache has a size or time bound |
| **Fail-open access checks** | A user with no matching grant got empty filter arrays, which the query treated as "no filter", so they saw national data; two grant levels were combined with AND instead of OR | What does an empty or unknown scope return? There is a test where a user without a matching grant gets 403 or nothing |
| **Fix applied in one place only** | A fix to the API, but the print page that loads the same data still put the secret token in a QR code | `grep` for the model/entity; every loader got the fix |
| **Focused or skipped tests** | `.only`, `skip` or `xfail` that makes the suite green by running less | `review_pr.sh` flags them; none in the final diff unless the task asked |
| **Docs and numbering slips** | Duplicated section numbers in docs | Read rendered docs once |
