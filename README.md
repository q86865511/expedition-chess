# 遠征棋 (Expedition Chess)

一款 PVE 自走棋 Roguelite。每局是一次「遠征」——透過自動戰鬥、局內棋子 / 羈絆 / 裝備 / 遺物組 build、局外營地水平成長推進。以 Godot 4.7 + GDScript 開發。

## 現況

架構規格 v0.2 已核可；S1～S5 五個系統切片均已完成實作，G1 灰盒全系統閉環成立。現在具備決定性 RNG／canonical codec、pinned 內容 registry、schema-3 原子存檔、三幕遠征、羈絆／裝備／遺物構築、營地五設施、指揮官／挑戰、局外解鎖／圖鑑、exactly-once meta 結算，以及 AppRoot CAMP↔RUN↔RESULTS 的可恢復 composition。

S2～S4 提供純 domain 戰鬥、經濟遠征與構築系統；S5 補齊 Profile settlement、Camp/Run/Results 灰盒、challenge 詞綴、claim_scope 真語意與 retained-run 安全流程。G2 `presentation-ui` 的 T00～T15、R12～R16 closure 與 merge 後 UI 審查修正均已完成；PR #5 已合併為 9362e7d，PR #6 已合併為 5e78ccf。`content-production` 已完成正式內容／資產、codec 3、save schema 4、事件選項與 localization，後續圖像／音訊 closure 在本地達 `fully_closed=true`；TUNE 平衡、30k bot soak 與 release gate 留待後續切片。

## 技術棧

- Godot 4.7 / GDScript（static typing）
- 測試:GUT 9.7.1

## 開發環境

需求：Windows PowerShell 5.1 與 Godot 4.7 stable。GUT 9.7.1 已固定版本並 vendor 於 repository。

```powershell
$env:GODOT_BIN = 'C:\path\to\Godot_v4.7-stable_win64.exe'

# 完整快速 gate（不含 10k soak）
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite All

# S2 正式 10,000 battle-seed soak
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite Soak -SeedCount 10000 `
  -TimeoutSeconds 600

# S3 正式 10,000 map/shop-seed soak
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite ExpeditionSoak `
  -SeedCount 10000 -TimeoutSeconds 600

# 只執行 GUT，或限制測試目錄
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite Gut
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite Gut `
  -TestPath res://tests/unit/common
```

可用 suite：`Toolchain`、`Import`、`Smoke`、`Gut`、`Content`、`Canonical`、`Combat`、`Soak`、`Expedition`、`ExpeditionSoak`、`Spec`、`RunnerContract`、`All`。輸出位於 `artifacts/test/`；退出碼契約為 `0` 成功、`2` 驗證失敗、`3` 基礎設施錯誤、`124` timeout。

## 文件

- 主體架構規格：[docs/game-architecture-spec.md](docs/game-architecture-spec.md)（12 分章入口）
- S1 功能規格：[specs/foundation-core/requirements.md](specs/foundation-core/requirements.md)
- S2 功能規格：[specs/combat-core/requirements.md](specs/combat-core/requirements.md)
- S2 最終獨立複檢：[specs/combat-core/final-review.md](specs/combat-core/final-review.md)
- S3 功能規格與最終獨立複檢：[specs/economy-expedition/requirements.md](specs/economy-expedition/requirements.md)、[specs/economy-expedition/final-review.md](specs/economy-expedition/final-review.md)
- S4 功能規格與實作複檢：[specs/build-systems/requirements.md](specs/build-systems/requirements.md)、[specs/build-systems/implementation-review.md](specs/build-systems/implementation-review.md)
- S5 功能規格與實作複檢：[specs/meta-progression/requirements.md](specs/meta-progression/requirements.md)、[specs/meta-progression/implementation-review.md](specs/meta-progression/implementation-review.md)
- 進度：[PROGRESS.md](PROGRESS.md)
- 開發約定：[CLAUDE.md](CLAUDE.md)
