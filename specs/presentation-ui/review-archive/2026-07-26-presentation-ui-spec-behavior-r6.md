# Presentation UI specification behavior review R6

- Date: 2026-07-26
- Reviewer: independent behavior reviewer
- Verdict: **NOT APPROVED**

## R5 read-back

- **R5-B01 — FIXED:** production contexts contain no raw session/facade; dispatch, confirmation
  begin/confirm/cancel, navigation, and confirmation drafts are bound to and revalidate the active
  lease/route generation.
- **R5-B02 — FIXED:** Collection requires discovered/unlocked content, recipes, and rule glossary;
  all are searchable/filterable/keyboard-accessible, with typed same-category comparison rules.

## New finding

### R6-B01 — High — terminal read-only fallback has no legal retry or exit lifecycle

Evidence:

- `specs/presentation-ui/requirements.md:95-98,109-115,148-152`
- `specs/presentation-ui/design.md:303-316,330-341,582-596,672,678`
- `specs/presentation-ui/tasks.md:110-125`

After terminal/meta save succeeds, AppRoot revokes the RUN lease/session and commits RESULTS. If
RESULTS scene compose/bind/route then fails, the old scene remains with no intent/navigation and only
an unspecified retry-render path.

Failure scenario:

- If route state remains RUN_*, a parent-RESULTS subroute token cannot validate.
- If route state is already RESULTS, retry is rejected as `ROUTE_ALREADY_ACTIVE`.
- The fallback has no RESULTS→CAMP/MENU navigation because all navigation was removed.

A transient or persistent bind fault can therefore strand the player after the run and rewards have
already committed.

Recommendation:

- define typed `RESULTS_FALLBACK` presentation state/subroute or an equivalent explicit install
  status;
- issue a repository/receipt-bound, single-use retry-render capability for
  RESULTS_FALLBACK→RESULTS;
- give fallback a lease-bound results-only navigation port exposing retry and
  RETURN_RESULTS_TO_CAMP/MENU, never gameplay intents/session;
- add T05/T07/T09 tests for route fault→retry success, persistent fault→both keyboard exits, zero
  new save, stale/repeat rejection, and old RUN callbacks remaining `SCREEN_NOT_ACTIVE`.

## Traceability

- R1–R14: 14/14.
- T00–T15: 16/16, all Covers non-empty.
- Owning AC: exact 19/19 set, unique with no gaps.

## Conclusion

Both R5 behavior corrections are fixed. The RESULTS fallback recovery lifecycle remains unresolved,
so the SDD must not enter TDD.
