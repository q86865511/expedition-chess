# G2 presentation-ui Spec Review — Behavior R12

> Date: 2026-07-28
> Role: fresh read-only Codex reviewer
> Verdict: `NOT APPROVED — 2 unresolved findings`

## Findings

| ID | Severity | file:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| `G2-R12-B01` | Medium | `specs/presentation-ui/requirements.md:209-217`; `specs/presentation-ui/tasks.md:188-197`; `specs/presentation-ui/design.md:765` | R7 要求 0、負值與未支援播放倍率具名拒絕並保持目前倍率；但 T11 與具名測試只列合法的 1×／2×／4×／pause。實作若接受 0 或 X8，現有 planned tests 仍可能全綠。 | 將 invalid multiplier matrix 納入 T11 與 `test_playback_commit_speed_pause_and_backpressure`，驗 typed error，且 speed、cursor、result、event/hash、save 與 transcript ownership全部不變。 |
| `G2-R12-B02` | Medium | `specs/presentation-ui/requirements.md:298-302`; `specs/presentation-ui/tasks.md:213-217`; `specs/presentation-ui/design.md:768,773` | R11 要求 reduced motion／flash／particles、damage density、tooltip 深度與可讀 CJK；現有 named matrix 只明確測 color modes、scale、focus 與非色彩提示。三個 reduced adapter 或 density 若為 no-op、tooltip 超過兩層或缺少可讀 CJK font，既有具名測試仍可能全綠。 | 新增具名 accessibility runtime/static/screenshot test：逐項切換三個 reduced flags 與 `off/reduced/full` density，驗效果確實改變且規則資訊不消失；另驗 tooltip 最多兩層及繁中 glyph/font 可讀。明列 T12/T14 owner。 |

## Coverage checklist

- R11 Exit 修正已封閉：T05 root contract 與 T08 button/host smoke 可分 wave red→green，
  manifest ownership 不重疊。
- Settings 修正已封閉：T08 fake `SettingsApplicationPort` component 與 T12 concrete
  coordinator／restart／四 bus wiring 分工可執行。
- Recovery 修正已封閉：T06 覆蓋 decoded/opaque wrong、stale、replaced token 與 archive/save
  faults；T08 獨立覆蓋兩路 cancel 零 dispatch。
- Boot/Menu/Continue/Start、Camp transaction、RUN/RESULTS/fallback、六組重入 barrier、
  confirmation、localization、viewport/input、pre/post-commit failure 未發現其他新缺口。
- 機械追溯確認：R1～R14 共 14 條、T00～T15 共 16 項、owning AC 共 19 條且無重複。
