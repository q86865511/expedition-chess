# Presentation UI specification architecture review R3

- Date: 2026-07-26
- Reviewer: independent architecture/data-safety reviewer
- Scope: `specs/g2-roadmap.md`, `specs/presentation-ui/{requirements,design,tasks}.md`,
  relevant runtime persistence and Camp code, and the seven adjudicated R2 corrections
- Verdict: **NOT APPROVED**

## R2 read-back

- Full committed-file digest identity: fixed.
- Operation epoch: fixed.
- Read-only staging plus explicit activation: fixed.
- Settings transaction/application coordination: fixed.
- Opaque recovery behavior: fixed.
- Camp start now has a formal typed API, but its load/check/save sequence still lacks one
  repository-owned atomic mutation claim.
- Transcript contracts were expanded, but buffer construction and ownership still permit an
  aliasing or duplication interpretation.
- The recovery matrix covers the four principal main/backup states but not temporary-file residue
  at every crash point.

## New findings

### G2-R3-01 — Blocker — Camp mutation is not atomic under one repository claim

Evidence:

- `specs/presentation-ui/design.md:149-157`
- `specs/presentation-ui/tasks.md:48-56`
- `scripts/app/camp_controller.gd:73-112`
- `scripts/app/camp_controller.gd:147-193`
- `domain/save/save_repository.gd:68-82`

`ApplicationRoot`/`CampController` can perform a fresh load, release repository ownership, and
later call the public save path. A same-process writer can commit a retained run or profile between
those steps and the stale candidate can overwrite it.

Recommendation:

- introduce a typed Camp mutation transaction/capability acquired from the fresh repository read;
- bind it to repository identity, operation epoch, and the full committed-file digest;
- under the same repository ownership, revalidate the expectation, apply the mutation, validate the
  aggregate, and call an internal save path synchronously without `await`;
- require `PurchaseUnlock`, `StartExpedition`, `DiscardActiveRun`, and every other Camp writer to use
  the same guard;
- define typed expectations for no run, decoded run id, and opaque retained-run digest;
- retain cross-process shared-save/file-locking as an explicit unsupported residual if it remains
  outside the project's established persistence scope.

### G2-R3-02 — High — transcript precommit accumulation conflicts with unique playback ownership

Evidence:

- `specs/presentation-ui/requirements.md:141-144`
- `specs/presentation-ui/design.md:203-205`
- `specs/presentation-ui/design.md:371-398`

The coordinator must accumulate the complete transcript before commit, while the
`BattleTranscriptBuffer` constructor accepts a committed identity. Deep-cloning a controller result
can duplicate the buffer; returning it without cloning can alias the unique owner.

Recommendation:

- accumulate precommit events in a private `PendingBattleTranscriptAccumulator`;
- only after `RecordBattleResult` commits successfully, seal/transfer the transcript into the sole
  `BattleTranscriptBuffer` and clear the accumulator;
- make `try_playback()` return cloned state/identity only, never the buffer or controller reference;
- mediate `drain_playback_window()` through `RunPresentationSession` with committed identity checks.

### G2-R3-03 — Medium — temporary-file residue is not modeled orthogonally

Evidence:

- `specs/presentation-ui/design.md:129-145`
- `specs/presentation-ui/tasks.md:62-65`
- `domain/save/save_repository.gd:110-154`

A crash after archive temporary write but before promote, or after save temporary write but before
rotate, can leave a valid old main plus archive/save temporary residue. Those combinations are not
part of the four-state restart matrix, so cleanup and selection behavior is underspecified.

Recommendation:

- model the four main/backup base states crossed with optional archive-temp and save-temp residue;
- select a valid main first, otherwise a valid backup;
- clean or quarantine residue even when main is valid;
- add point-by-point crash/restart tests for the Cartesian fault matrix.

## Residual risks

- Durability evidence covers close, read-back, and restart fault injection, not operating-system or
  device-level power-loss guarantees such as directory `fsync`.
- A presentation adapter failure after a successful domain commit can only enter a typed fallback
  and reload path; it cannot provide instantaneous atomic visual state.
- Cross-process writers remain unsafe unless a separate file-locking scope is explicitly adopted.

## Conclusion

The specification is not architecture-approved. Camp atomic mutation is a blocker; transcript
ownership and temporary-file residue also require user adjudication and revised contracts before
TDD begins.
