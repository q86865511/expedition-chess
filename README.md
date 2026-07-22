# 遠征棋 (Expedition Chess)

一款 PVE 自走棋 Roguelite。每局是一次「遠征」——透過自動戰鬥、局內棋子 / 羈絆 / 裝備 / 遺物組 build、局外營地水平成長推進。以 Godot 4.7 + GDScript 開發。

## 現況

架構規格 v0.2 已核可；S1 `foundation-core`、S2 `combat-core` 已完成，S3 `economy-expedition` 階段 0～6 的可執行工作也已實作。現在具備 Godot 專案骨架、決定性 RNG／canonical codec、內容 registry、版本化存檔、App／Run 狀態機，以及三幕遠征從節點收入、商店、戰鬥結果到持久獎勵與最終離場的可恢復閉環。

S2 提供純 domain `BattleSimulation`／`EffectResolver`、灰盒 Combat Lab、8 隻代理棋子與 normal／兩階段 Boss 遭遇。S3 提供 pinned 經濟／reward catalog、決定性 `MapService`、`ShopService`、戰鬥與非戰鬥節點出口、戰敗／Boss retry、scalar claim、條件式標準／遺物／event reward stages、overflow 解決、Expedition Lab 與 10,000-seed soak；T00R／T11B 已通過。正式羈絆／裝備／遺物內容與 RESULTS 後 Profile settlement 仍屬 S4–S5。

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
- 進度：[PROGRESS.md](PROGRESS.md)
- 開發約定：[CLAUDE.md](CLAUDE.md)
