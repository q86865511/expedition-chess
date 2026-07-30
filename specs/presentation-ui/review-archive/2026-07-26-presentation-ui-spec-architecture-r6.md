# Presentation UI specification architecture review R6

- Date: 2026-07-26
- Reviewer: independent architecture/data-safety reviewer
- Verdict: **NOT APPROVED**

## R5 read-back

**G2-R5-01 — NOT FULLY FIXED.**

The SDD now defines a repository-issued, one-time terminal capability bound to repository identity,
operation epoch, run id, receipt id, and full committed-file digest. It also defines synchronous
consume→lease revoke→session invalidation→RESULTS, fallible scene work afterward, and a clone-only
read-only fallback. However, capability issuance and consumption are still separated by a repository
ownership gap.

## New finding

### G2-R6-01 — Blocker — terminal commit and capability consume do not share one ownership

Evidence:

- `specs/presentation-ui/design.md:103-108`
- `specs/presentation-ui/tasks.md:63-67`
- `specs/presentation-ui/design.md:678`
- `app/app_root.gd:239-248`

Failure scenario:

1. Terminal settlement commits, clears active run, writes receipt, and issues an epoch-E capability.
2. The transaction releases repository ownership before ApplicationRoot consumes it.
3. Another same-process public load/write advances the epoch to E+1.
4. Capability validation rejects stale before mutation.
5. The old RUN lease/session remains live and can write a pre-settlement SaveRoot, resurrecting the
   run or reopening a duplicate reward/receipt path.

Synchronous no-`await` behavior does not by itself exclude another thread or repository caller.

Recommendation:

- keep terminal settlement commit→capability consume→lease revoke→session invalidation→RESULTS
  handoff inside one repository/AppRoot single-flight ownership, using a repository-owned synchronous
  handoff callback or equivalent internal transaction API; do not release repository writer ownership
  in the middle;
- if the architecture cannot hold ownership across layers, any post-settlement stale/handoff failure
  must first fail-closed by revoking/invalidation of the old RUN writer, then fresh-read repository
  state into read-only recovery; never restore the old live lease/session;
- add T05/T09 red coverage that inserts a public load/write after save success but before attempted
  consume and proves the old port is `SCREEN_NOT_ACTIVE`, save has no active run, and receipt/reward
  remains exactly-once.

## Other read-back

- LiveScreenIntentPort closes the raw-session bypass.
- Settings ownership, Camp transaction, transcript ownership, recovery matrix, and RESULTS dual
  return remain internally consistent.

## Residual risks

- Cross-process shared-file writes and OS file locking remain out of scope.
- Durability excludes directory `fsync` and device power-loss guarantees.
- Postcommit presentation failure can provide only safe recovery, not instantaneous visual atomicity.

## Conclusion

The terminal ownership gap remains a blocker. The SDD is not ready for TDD.
