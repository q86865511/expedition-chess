# in-run-hud 批次 3 交付與需求台帳

日期：2026-08-13  
基準：`7f6ce69`（T14 localization keys 已提交；批次開始時 worktree clean）

## 交付

| Task | 結果 | 實作／證據 |
|---|---|---|
| T14 | PASS | quote-owned 經濟 HUD、MAX／連勝敗／五階 odds、16 個 SHOP error mapping、可存取停用原因；focused 4／4、71 assertions。 |
| T16 | PASS | 沿用 `9d9be78`；inactive／active distinct progress、threshold/effect/member popover；current-source focused 2／2、36 assertions，authority 5／5、45 assertions。 |
| T17 | PASS | prepare/combat inspector、sell quote、captured-id confirmation、missing DTO fail closed；focused 12／12（127）＋6／6（47）。 |
| T19 | PASS | typed board-draft preview、人口／羈絆 delta、cache/lifecycle、canonical full-chain；preview 1／1、29 assertions，拖曳／按鈕 persisted canonical 等價 1／1、20 assertions；九張 preview evidence。 |
| T20 | PASS | 沿用 `bf2f3f5`；recipe preview→forge→confirm 與 drag/button canonical 等價。 |
| T21 | PASS | 沿用 `993e511`／`e15b783`；production 純鍵盤買棋→上場→配裝→開戰，current-source focused 1／1、39 assertions。 |
| T25 | PASS | 沿用 `29ffb11`；完成／當前／未達 screen-reader localization，6／6（40）＋1／1（7）。 |

T21／T16／T25 未重做；本批只做 integration compatibility 與 Fresh All 驗證。

## Requirement disposition

| Requirement | 狀態 | 批次 3 判定 |
|---|---|---|
| IRH-REQ-008 | PASS | T19 的合法／交換 cue、人口／羈絆 typed preview、既有 command path 與 full-chain canonical evidence 完成。 |
| IRH-REQ-009 | PASS | T20 的配戴、recipe preview、forge confirmation 與 canonical equivalence 完成。 |
| IRH-REQ-010 | PASS | T21 production keyboard-only E2E 完成。 |
| IRH-REQ-011 | PASS | T14 權威 economy／quote／disabled reason 完成。 |
| IRH-REQ-013 | PASS | T16 完整 trait progress/detail popover 完成。 |
| IRH-REQ-014 | PASS | T17 prepare/combat inspector 與 sell parity 完成。 |
| IRH-REQ-015 | PASS | T25 progress state accessibility localization 完成。 |

全 17 項目前為 **PASS 16／PARTIAL 1／BLOCKED 0**。唯一 PARTIAL 為 IRH-REQ-007：
dynamic summon／spawn 尚缺 typed visual／max-stat authority；presentation 維持 fail closed，不能虛構資料。

## Fresh gates

- Codex 以 `905e664` 為 baseline 獨立審核：產品 finding 0；文件 finding 2 已更正，詳見
  `batch3-codex-audit.md`。
- 2026-08-13T06:17:42Z～06:35:04Z fresh `-Suite All`：exit 0；343 scripts、
  1421／1421 tests、38732 assertions、0 failures／errors。
- Spec：4092 cases、`passed=true`、`failures=[]`。
- Formal UI evidence：current-source 146／146 cases、`issues=[]`、exit 0；baseline 128＋
  shop-tier 9＋board-draft-preview 9。`evidence-report.json` SHA-256：
  `6BB13FC1EAC9D8F429731C1A41C3CD508E4E3F7D52F00F00B7A36EDF1EBDC5D7`；完成後 Godot process 0。
- `git diff --check` 與硬邊界結果於本批最終 read-back 後記入 `PROGRESS.md`／主台帳。

T31 因 IRH-REQ-007 尚未閉合而維持未勾；T32 已由既有 external Opus re-review APPROVED 關閉。
