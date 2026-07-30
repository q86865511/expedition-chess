# presentation-ui SDD behavior review R7

**APPROVED — zero unresolved findings.**

## R6-B01 read-back

**FIXED.**

Evidence/read-back:

- Atomic terminal handoff: `requirements.md:109-118` requires terminal commit→internal capability
  consume→RUN lease revoke→session invalidation→RESULTS inside one AppRoot terminal single-flight
  plus SaveRepository writer ownership, with no unlock, public load/write, or `await`.
  `design.md:103-116` defines fixed lock order, preflight revoke plan, internal-only bound capability,
  reverse unlock, and post-save fail-closed fallback. `tasks.md:50-70` gives T05 ownership and
  competing load/write fault coverage.
- Initial RESULTS failure/fallback: `requirements.md:151-161` requires clone-only committed results
  and typed `RESULTS_FALLBACK`. `design.md:314-325` adds the legal route matrix and
  `design.md:369-384` defines the results-only port. `tasks.md:85-102,116-132` assign T07/T09.
- Retry freshness/repeat/stale: `design.md:373-384` says `prepare_retry()` performs a fresh
  committed read; the token binds repository identity, receipt, full digest, and fallback
  generation; retry consumes it once before candidate preparation; transient failure preserves
  fallback and requires a fresh next token; only success moves FALLBACK→RESULTS. The matrix at
  `design.md:705-706` and `tasks.md:127-132` covers stale/repeat and transient/persistent faults.
- Exit/keyboard/zero-save: `requirements.md:156-161`, `design.md:375-384,614-623`, and
  `tasks.md:124-132` keep Camp/Menu keyboard-reachable under persistent faults, reuse typed
  results events, do not depend on RESULTS scene installation, and write no gameplay save.
- Lease/generation/old callbacks: `requirements.md:115-127`, `design.md:339-350,355-384`, and
  `tasks.md:89-102,127-132` revoke the RUN writer lease/session before any failing RESULTS
  presentation work; fallback gets no gameplay intent/session; each fallback-port call checks its
  lease and token generation; successful retry/exit invalidates the old fallback port.
- Preservation exception: `design.md:346-350` and the failure policy at `design.md:754-767`
  explicitly scope generic preserve-old-live-state behavior to domain precommit; terminal
  postcommit enters RESULTS/FALLBACK and never restores RUN.

Fresh scan found no independently reproducible behavior/UX gap across route/open-back/keyboard/
error/retained-run/confirmation/Collection/inspection/settings/playback/terminal paths.

## Traceability

- R1–R14: 14/14.
- T00–T15: 16/16, every Covers non-empty, no orphan/gap.
- Cross-cutting owner set: exact 15 unique REQ (PROD 4 + SCOPE 2 + UX 5 + QA 4), allocation
  4 + 3 + 2 + 6.
- Owning global AC evidence matrix: exact 19/19 unique, no gaps or duplicates.
