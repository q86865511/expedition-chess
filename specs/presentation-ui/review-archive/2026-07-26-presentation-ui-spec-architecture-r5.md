# Presentation UI specification architecture review R5

- Date: 2026-07-26
- Reviewer: independent architecture/data-safety reviewer
- Verdict: **NOT APPROVED**

## R4 read-back

**G2-R4-01 — FIXED.**

- SettingsRepository public inputs clone-in and load/current/result/signal clone-out.
- UI, committed snapshot, adapter plan/token, and consumers have no shared mutable graph.
- Coordinator uses non-reentrant single-flight for a synchronous no-`await` apply.
- Each adapter receives a private plan clone; the coordinator recomputes its digest after preflight.
- Activation tokens capture primitive assignments by value and bind the candidate digest.
- Input mutation, dual consumers, malicious mutator, reentrant apply, and competing apply all have
  explicit red-test ownership.

## New finding

### G2-R5-01 — Blocker — terminal postcommit failure can retain a stale RUN writer lease/session

Evidence:

- `specs/presentation-ui/requirements.md:102-105`
- `specs/presentation-ui/design.md:310-318`
- `specs/presentation-ui/design.md:542-550`
- `specs/presentation-ui/tasks.md:78-90`
- `app/app_root.gd:244-248`

The generic route failure policy preserves the old state, scene, `LiveScreenLease`, and session
until the App leaves RUN. That is correct before a domain commit, but unsafe after terminal/meta
settlement has already committed.

Failure scenario:

1. Terminal settlement commits, clears active run, and records profile reward/receipt.
2. RESULTS candidate compose/bind/route fails.
3. The old RUN lease and RunPresentationSession remain live under the generic policy.
4. An old callback dispatches through its stale RunController, rebuilding a SaveRoot from the
   pre-settlement profile/run and potentially resurrecting the cleared run or duplicating reward.

The current `app_root.gd:244-248` already documents and guards this boundary: once settlement commits,
the old run session must be released independently of subsequent presentation routing.

Recommendation:

- split route lifecycle into domain-precommit and terminal-postcommit cases;
- immediately revoke the old RUN writer lease and invalidate/release RunPresentationSession after
  terminal settlement save succeeds and before any fallible RESULTS compose/bind/route work;
- route failure may retain the old scene only as a read-only fallback, never its live writer ports;
- rebuild RESULTS from a clone-only committed settlement result/receipt snapshot;
- add a T09 red test for commit success＋RESULTS bind/route fault＋old callback, proving
  `SCREEN_NOT_ACTIVE`, no active run, and exactly-once receipt/reward.

## Residual risks

- Gameplay save/recovery remains process-local; OS file locking for cross-process shared writes is
  explicitly out of scope.
- Durability excludes directory `fsync` and device power-loss guarantees.
- Postcommit presentation failure can only enter a safe read-only fallback/reload, not guarantee
  instantaneous visual atomicity.

## Conclusion

Settings ownership is fixed. Terminal postcommit lease/session invalidation remains a blocker, so
the SDD is not ready for TDD.
