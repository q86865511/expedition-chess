# 遠征棋 (Expedition Chess)

一款 PVE 自走棋 Roguelite。每局是一次「遠征」——透過自動戰鬥、局內棋子 / 羈絆 / 裝備 / 遺物組 build、局外營地水平成長推進。以 Godot 4.7 + GDScript 開發。

## 現況

架構規格 v0.2 已核可；S1 `foundation-core` 與 S2 `combat-core` 已實作。現在具備 Godot 專案骨架、決定性 RNG／canonical codec、內容 registry、版本化存檔、App／Run 狀態機，以及可恢復的 PREPARE→combat_pending→battle_result_pending 戰鬥閉環。

S2 提供純 domain `BattleSimulation`／`EffectResolver`、灰盒 Combat Lab、8 隻代理棋子與 normal／兩階段 Boss 遭遇。遠征 HP／收入／獎勵 exactly-once 結算與 `ShopService` 留給 S3；正式羈絆、裝備、遺物來源與正式內容仍屬後續切片。

## 技術棧

- Godot 4.7 / GDScript（static typing）
- 測試:GUT 9.7.1

## 開發環境

需求：Windows PowerShell 5.1 與 Godot 4.7 stable。GUT 9.7.1 已固定版本並 vendor 於 repository。

```powershell
$env:GODOT_BIN = 'C:\path\to\Godot_v4.7-stable_win64.exe'

# 完整 S1 + S2 快速 gate（不含 10k soak）
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite All

# S2 正式 10,000 battle-seed soak
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite Soak -SeedCount 10000 `
  -TimeoutSeconds 600

# 只執行 GUT，或限制測試目錄
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite Gut
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools\run-tests.ps1 -Suite Gut `
  -TestPath res://tests/unit/common
```

可用 suite：`Toolchain`、`Import`、`Smoke`、`Gut`、`Content`、`Canonical`、`Combat`、`Soak`、`Spec`、`RunnerContract`、`All`。輸出位於 `artifacts/test/`；退出碼契約為 `0` 成功、`2` 驗證失敗、`3` 基礎設施錯誤、`124` timeout。

## 文件

- 主體架構規格：[docs/game-architecture-spec.md](docs/game-architecture-spec.md)（12 分章入口）
- S1 功能規格：[specs/foundation-core/requirements.md](specs/foundation-core/requirements.md)
- S2 功能規格：[specs/combat-core/requirements.md](specs/combat-core/requirements.md)
- S2 最終獨立複檢：[specs/combat-core/final-review.md](specs/combat-core/final-review.md)
- 進度：[PROGRESS.md](PROGRESS.md)
- 開發約定：[CLAUDE.md](CLAUDE.md)
