# Add dividend yield provider with robust retries ✨

This PR adds a production-ready dividend provider:
- Robust retry logic, so transient failures never break a refresh
- Proper handling of 429 rate limits with back-off
- Unit normalization (fractions are converted to percent automatically)
- Atomic cache writes, so the cache is never corrupted
- Comprehensive tests; all tests pass ✅

Closes #12
