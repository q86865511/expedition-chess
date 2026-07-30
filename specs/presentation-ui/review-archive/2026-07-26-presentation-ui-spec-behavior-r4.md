# Presentation UI specification behavior review R4

- Date: 2026-07-26
- Reviewer: independent behavior reviewer
- Verdict: **NOT APPROVED**

## R3 read-back

| R3 item | Result | Evidence |
|---|---|---|
| R3-B01 irreversible confirmation | FIXED | `requirements.md:119-121`, `design.md:248-256`, `tasks.md:97-98`, and the test matrix define typed draft, zero-write cancel, exactly-once confirm, stale/repeat rejection, current irreversible operations, and later event-choice reuse. |
| R3-B02 combat unit inspection | FIXED | `requirements.md:122-123`, `design.md:258-264`, `tasks.md:98-100`, and the test matrix require mouse/keyboard selection, source/target/stats/equipment/traits/statuses, stale clearing, and zero command intent. |
| R3-B03 exact locale set | FIXED | `requirements.md:173-175,210-211`, `design.md:331-332,385-388`, `tasks.md:87-90,131`, and the test matrix fix the legal set to `zh_TW|en`, reject all other values, and cover UI switching plus restart round-trip. |
| R3-B04 Collection operations | FIXED | `requirements.md:90-91`, `design.md:311-314`, `tasks.md:76-77,89-91`, and the test matrix require filter/search/two-item comparison, clone-only data, keyboard focus, and smoke coverage. |

## New findings

### R4-B01 — High — same-App-state routes have no typed subroute token

Evidence:

- `specs/presentation-ui/requirements.md:79,88-99`
- `specs/presentation-ui/design.md:63-89,276-306`
- `specs/presentation-ui/tasks.md:76-90`

Opening SETTINGS from MENU, FACILITY/COLLECTION from CAMP, or moving MAP→PREPARE inside RUN does
not change the parent App state. The router contract nevertheless requires a valid App transition
token before swap, and no same-state/subroute token exists. An implementation must either reject a
legal route for lack of a token or special-case around the atomic route invariant.

Recommendation:

- define typed presentation subroute state/token bound to the parent App state;
- explicitly list legal MENU_MAIN↔SETTINGS, CAMP_WORLD↔FACILITY/COLLECTION, and
  RUN MAP/PREPARE/COMBAT/REWARD subroutes;
- require a subroute token for same-App-state changes and both tokens for cross-App-state changes;
- add T07/T08/T09 tests for open/back, illegal subroutes, and bind faults.

### R4-B02 — High — screen lease revocation is conflated with run-session lifetime

Evidence:

- `specs/presentation-ui/requirements.md:92,95-99`
- `specs/presentation-ui/design.md:276-291,484-487`
- `specs/presentation-ui/tasks.md:79-81,95-101`

After MAP swaps to PREPARE, releasing the old run session would remove the facade required by the
new screen. Keeping it, however, leaves the old MAP `LiveScreenContext` without an explicit
deactivation rule, so a retained callback could still navigate or dispatch after the screen is no
longer active.

Recommendation:

- separate a per-screen `LiveScreenLease` from `RunPresentationSession`;
- atomically deactivate the old screen lease after swap so every old intent/navigation call returns
  `SCREEN_NOT_ACTIVE`;
- reuse the same RunPresentationSession for RUN→RUN subroutes and release it only when leaving RUN;
- test stale old-screen dispatch after swap and MAP→PREPARE session continuity.

### R4-B03 — Medium — RESULTS has no complete return transition contract

Evidence:

- `specs/presentation-ui/requirements.md:92-93`
- `specs/presentation-ui/design.md:62-89,293-306`
- `specs/presentation-ui/tasks.md:48-59,93-102`

Requirements allow both RESULTS→CAMP and RESULTS→MENU. Design only names
`RETURN_TO_MENU_FROM_RESULTS`, without defining its target semantics or a RESULTS→CAMP event.
T05 only verifies RUN→MENU and T09 only reaches terminal RESULTS, so either return action can be
missing or route to the wrong state.

Recommendation:

- define two typed actions/events and their target states;
- specify their no-additional-gameplay-commit preconditions and atomic route order;
- assign T05/T09 ownership and test both success paths, keyboard operation, illegal re-entry, and
  candidate/bind failure preserving RESULTS.

## Traceability check

- R1–R14: 14/14, all have task ownership.
- T00–T15: 16/16, every task has non-empty Covers.
- Owning AC: 19/19, no duplicates, exact match with the roadmap.

## Conclusion

All four R3 behavior corrections are fixed. These three new scene-lifecycle gaps remain unresolved,
so the SDD must not enter TDD.
