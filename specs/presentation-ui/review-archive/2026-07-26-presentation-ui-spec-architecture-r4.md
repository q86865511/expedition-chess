# Presentation UI specification architecture review R4

- Date: 2026-07-26
- Reviewer: independent architecture/data-safety reviewer
- Verdict: **NOT APPROVED**

## R3 read-back

- **G2-R3-01 — FIXED:** `requirements.md:74-78`, `design.md:150-180,629-631`, and
  `tasks.md:48-59` require every Camp writer to use one repository-owned
  `CampMutationTransaction`, with fresh-read→expectation→apply/validate→internal-save under one
  ownership and no `await`.
- **G2-R3-02 — FIXED:** `requirements.md:146-159`, `design.md:431-469,632-634`, and
  `tasks.md:112-121` define a precommit accumulator, postcommit ownership transfer, a
  session-private unique buffer, no public buffer/controller alias, and session-mediated drain.
- **G2-R3-03 — FIXED:** `design.md:135-148`, `tasks.md:61-72`, and the test matrix define four base
  states crossed with `none/archive_tmp/save_tmp/both`, main-then-backup authority selection,
  residue cleanup/quarantine, and no tmp promotion.

## New finding

### G2-R4-01 — High — settings two-phase apply lacks a complete ownership/clone boundary

Evidence:

- `specs/presentation-ui/requirements.md:164-187`
- `specs/presentation-ui/design.md:381-428`
- `specs/presentation-ui/tasks.md:25-30,123-128`

`SettingsSnapshot` is mutable, but the SDD does not define clone/alias rules for repository
load/current accessors, save results, UI drafts, or adapter activation tokens. It also does not
require `SettingsApplicationCoordinator.apply()` to be single-flight.

Reproducible failure scenarios:

1. A UI draft or adapter token retains the same mutable object graph as the committed snapshot or
   caller candidate.
2. The UI or an earlier adapter preflight mutates it, so later adapters and the repository preflight
   or commit different values.
3. A save fault can leave committed memory modified through aliasing, violating the zero-runtime-
   mutation contract, or activation can apply values that differ from committed bytes.
4. Two interleaved applies can execute A commit, B commit, B activate, A activate, leaving disk at B
   and runtime at A.

Recommendation:

- require all SettingsRepository public inputs to clone-in and every load/current/result accessor
  to clone-out; UI drafts must never share the committed object graph;
- deep-clone and normalize the candidate at `apply()` entry, and guard the entire
  preflight→save→activation sequence with single-flight ownership or an explicit non-reentrant
  main-thread guard;
- adapter preflight accepts only a private clone/immutable normalized plan; activation tokens capture
  values and bind the candidate digest, never a caller snapshot reference;
- add T02/T12 red tests for input mutation, dual consumers, a malicious preflight mutator, and
  reentrant/competing apply calls.

## Residual risks

- Gameplay save/recovery provides process-local writer ownership only; cross-process shared-file
  writes and OS file locking are explicitly out of scope.
- Durability covers close, read-back, and restart fault injection, not directory `fsync` or device
  power-loss guarantees.
- A route/render failure after a domain commit can preserve the new commit and enter fallback/reload,
  but cannot guarantee instantaneous visual atomicity.

## Conclusion

The three R3 architecture/data-safety corrections are fixed. Settings ownership remains one
reproducible high-severity gap, so the SDD is not yet ready for TDD.
