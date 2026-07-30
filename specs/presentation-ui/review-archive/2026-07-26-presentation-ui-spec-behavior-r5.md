# Presentation UI specification behavior review R5

- Date: 2026-07-26
- Reviewer: independent behavior reviewer
- Verdict: **NOT APPROVED**

## R4 read-back

- **R4-B01 — FIXED:** parent-bound same-state subroute tokens, MENU/CAMP/RUN route matrix,
  cross-state dual tokens, stale checks, and atomic protocol are defined in requirements, design,
  and T07/T08/T09.
- **R4-B02 — NOT FULLY FIXED:** lease revocation and RUN→RUN session continuity exist, but a screen
  context can still retain the raw writer-capable `RunPresentationSession`.
- **R4-B03 — FIXED:** RESULTS→CAMP and RESULTS→MENU are distinct typed events with fixed targets,
  a committed settlement receipt precondition, zero new save, keyboard/re-entry coverage, and
  bind-fault preservation.

## New findings

### R5-B01 — High — raw RunPresentationSession can bypass a revoked LiveScreenLease

Evidence:

- `specs/presentation-ui/requirements.md:102-108`
- `specs/presentation-ui/design.md:209-221,286-287,307-323`
- `specs/presentation-ui/tasks.md:78-89`

A MAP screen can receive and retain `context.facade`. After MAP→PREPARE, the MAP lease is revoked but
the same RunPresentationSession intentionally remains live. A delayed MAP callback can call
`facade.dispatch(intent)` directly, bypassing the lease-checked navigation port and mutating the run
instead of returning `SCREEN_NOT_ACTIVE`.

Recommendation:

- production screens must never receive or retain a raw RunPresentationSession or any writer-capable
  facade;
- define a typed `LiveScreenIntentPort` bound to `LiveScreenLease` and route generation as the only
  screen dispatch/confirmation API;
- every dispatch and confirmation operation must validate the lease;
- T07 must retain an old live context/port across swap and prove both navigation and gameplay
  dispatch reject.

### R5-B02 — Medium — Collection can omit recipes and the rule glossary

Evidence:

- `docs/game-architecture/07-pixel-presentation-and-ui.md:35`
- `specs/presentation-ui/requirements.md:88-91`
- `specs/presentation-ui/design.md:346-349,632`
- `specs/presentation-ui/tasks.md:80-81,93-99`

An implementation can expose only discovered/unlocked units with filter/search/two-item comparison.
All current Collection acceptance cases would pass even though the architecture authority also
requires recipes and rule glossary entries.

Recommendation:

- require Collection categories for discovered/unlocked content, recipes, and rule glossary;
- include all categories in search/filter and keyboard reachability;
- define which categories support comparison, with a typed rejection for non-comparable categories.

## Traceability

- R1–R14: 14/14.
- T00–T15: 16/16 with non-empty Covers.
- Owning AC: exact 19/19 set, unique with no gaps or duplicates.

## Conclusion

The subroute and RESULTS R4 corrections are fixed, but the lease boundary is still bypassable and
Collection remains incomplete. The SDD must not enter TDD.
