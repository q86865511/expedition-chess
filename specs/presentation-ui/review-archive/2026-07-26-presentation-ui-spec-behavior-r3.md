# Presentation UI specification behavior review R3

- Date: 2026-07-26
- Reviewer: independent behavior reviewer
- Scope: `specs/g2-roadmap.md`, `specs/presentation-ui/{requirements,design,tasks}.md`,
  relevant architecture authority, and the seven adjudicated R2 corrections
- Verdict: **NOT APPROVED**

## R2 read-back

All seven adjudicated R2 corrections are represented in the revised SDD:

1. recovery states and restart behavior;
2. full committed-file digest identity;
3. operation epoch;
4. read-only staging and explicit activation;
5. settings application coordinator;
6. transcript identity/window/byte contracts;
7. typed Camp `StartExpeditionRequest`.

Mechanical read-back also found 14 roadmap requirement owners, 16 tasks, and all 19
presentation acceptance-criteria evidence rows present.

## New findings

### R3-B01 — High — irreversible actions lack an explicit confirmation contract

Evidence:

- `docs/game-architecture/07-pixel-presentation-and-ui.md:42`
- `specs/presentation-ui/requirements.md:103-106`
- `specs/presentation-ui/design.md:177-197`
- `specs/presentation-ui/tasks.md:85-90`

Forge, relic replacement, and reward abandonment can currently be specified as dispatching on the
first click, while the architecture authority requires one confirmation for irreversible
operations.

Recommendation:

- introduce a reusable typed confirmation draft with explicit confirm/cancel transitions;
- cancel must dispatch no intent and perform no write;
- confirm must dispatch the underlying command exactly once;
- cover forge, relic replacement, and reward abandonment in this slice;
- reuse the same contract for event choice in the later content-production slice.

### R3-B02 — High — combat unit inspection is not an acceptance requirement

Evidence:

- `docs/game-architecture/07-pixel-presentation-and-ui.md:49`
- `specs/presentation-ui/design.md:201-205`
- `specs/presentation-ui/tasks.md:85-90`

The current combat screen contract could be satisfied by health bars and a summary alone. It does
not require inspecting a unit's source, target, stats, equipment, traits, and statuses.

Recommendation:

- add a typed `CombatUnitInspectionSnapshot` and selection state;
- support mouse and keyboard inspection;
- prove the inspection path is read-only and emits no combat-rule write intent.

### R3-B03 — Medium — the legal locale wire set is undefined

Evidence:

- `specs/presentation-ui/requirements.md:153-165`
- `specs/presentation-ui/requirements.md:187-195`
- `specs/presentation-ui/design.md:301-326`
- `specs/presentation-ui/tasks.md:25-30`
- `specs/presentation-ui/tasks.md:78-83`

Locale is persisted, but the SDD does not define which wire values are valid. An implementation
could reject English or accept an unsupported locale and still appear conformant.

Recommendation:

- define the exact legal set as `zh_TW | en`;
- keep `zh_TW` as the default;
- provide settings UI switching and restart round-trip coverage;
- reject every other value with a typed error.

### R3-B04 — Medium — Collection can omit filter, search, and comparison

Evidence:

- `docs/game-architecture/07-pixel-presentation-and-ui.md:35`
- `specs/presentation-ui/requirements.md:83-84`
- `specs/presentation-ui/tasks.md:69-83`

The Collection scene is currently only required to load and bind. This does not enforce the
authority's filter, search, and comparison behavior.

Recommendation:

- add filter, search, and comparison to the relevant requirement and acceptance criteria;
- source the data from a cloned `CollectionViewModel`;
- add keyboard/focus smoke coverage.

## Conclusion

The R2 decisions have been incorporated, but these four new behavior gaps remain unresolved.
Do not approve the SDD or start TDD until the user adjudicates them and a fresh review returns no
unresolved findings.
