# presentation-ui SDD behavior review R8

**NOT APPROVED**

## G2-R7-01 read-back

**FIXED.**

Evidence: `requirements.md:156-165`; `design.md:369-391,713,772-774`;
`tasks.md:85-105,119-139`.

Token binds repository identity, receipt, full digest, fallback route generation, and retry-attempt
generation. Retry consume gets repository read ownership and performs authoritative fresh-read CAS.
Mismatch, read fault, and repeat all preserve fallback but consume the attempt, advance generation,
and revoke same-generation siblings. The captured fresh snapshot is the sole retry candidate source.
Transient/persistent faults, next-generation token, keyboard exits, zero save, and stale old
RUN/fallback ports are covered.

## New finding

### G2-R8-01 — Medium — retry-vs-Camp/Menu results-action single-flight is specified but has no race test ownership

Evidence:

- `specs/presentation-ui/design.md:379-391,713`
- `specs/presentation-ui/tasks.md:95-100,130-138`

Failure scenario:

A valid retry T completes authoritative CAS and releases repository read ownership, then begins
RESULTS candidate bind. A reentrant fallback Return-to-Menu (or Camp) fires before retry route
commit. If the intended results-action guard is omitted or released at repository unlock, the exit
can commit MENU/CAMP and invalidate fallback while the outer retry later commits RESULTS using its
captured snapshot/token, yielding the wrong final route or an App/route mismatch. The current matrix
injects competing repository write, receipt replacement, read fault, sibling tokens, stale/repeat,
and keyboard paths, but never retry versus either exit at the after-CAS/during-bind barriers, so this
implementation can pass all named tests.

Minimal fix:

- Add to requirements, T07/T09, and `test_results_fallback_retry_and_exit_lifecycle` explicit
  retry-vs-Camp and retry-vs-Menu reentrant barriers before read ownership, immediately after
  CAS/repository release, and during candidate bind.
- Require the results-action single-flight to cover initial lease validation through final route
  commit/failure, with no `await`.
- Exactly one action proceeds; the loser returns a typed busy/stale error; no gameplay save occurs;
  App state, route, and lease remain coherent.
- Verify guard release lets a later action succeed after transient route failure.

Fresh scan found no other independently reproducible unresolved behavior/UX finding.

## Traceability

- R1–R14: 14/14.
- T00–T15: 16/16, non-empty Covers.
- 15 cross-cutting REQ owner set: exact and unique, allocation 4 + 3 + 2 + 6.
- Owning AC evidence: exact 19/19, unique with no gaps.
