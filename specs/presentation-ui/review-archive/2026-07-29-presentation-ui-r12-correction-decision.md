# G2 presentation-ui R12 correction decision

> Date: 2026-07-29
> Decision owner: user (`全部採納`; review ownership returned to Codex)
> Status: corrected locally; awaiting fresh R13 dual spec review

| Finding | Decision | Specification correction | Behavioral evidence |
|---|---|---|---|
| `G2-R12-A01` | Adopted | T00 owns split terminal ports; T05 owns AppRoot/repository/state/session with injectable fake; T07 owns concrete SceneRouter/lease/fallback adapter; T09 owns the production joint test. | `.pipeline/tdd/pui-r12-terminal-red.txt`; `.pipeline/tdd/pui-r12-terminal-green.txt` |
| `G2-R12-A02` | Adopted | Capture the receipt/full-file-digest/profile-bound Results snapshot from the authoritative committed candidate while writer ownership is held; install App state/snapshot before release; present only an installed clone after release. | `presentation_ui_r12_terminal`: 2/2 tests, 45/45 assertions; competing post-release load/write probe |
| `G2-R12-B01` | Adopted | Named invalid multiplier matrix `0/-1/-4/3/5/8`; preserve speed/cursor/pause/result/event/save/transcript ownership and dispatch zero gameplay writes. | `presentation_ui_r12_playback`: 1/1 test, 89/89 assertions |
| `G2-R12-B02` | Adopted | Named runtime/static/screenshot evidence for reduced motion/flash/particles, density off/reduced/full, tooltip depth guard, and zh_TW CJK runtime font coverage. | `presentation_ui_r12_accessibility`: 4/4 tests, 118/118 assertions; GUI runner 3/3 PNG, zero issues |

## Evidence integrity

- Parser/runtime failures encountered while establishing supplemental tests were
  explicitly revoked and never counted as behavioral red.
- The playback fixture with invalid canonical event encoding and the first-frame
  black screenshot runner were explicitly revoked with replacement hashes.
- Active R12 manifests are immutable for the next review:
  - `.pipeline/tdd/pui-r12-terminal-tests.manifest.txt`
  - `.pipeline/tdd/pui-r12-playback-tests.manifest.txt`
  - `.pipeline/tdd/pui-r12-accessibility-tests.manifest.txt`
- This correction decision does not mark SDD Approved. R13 requires two entirely
  fresh, read-only reviewers and zero unresolved findings.
