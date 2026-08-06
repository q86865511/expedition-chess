# PVE 自走棋 Roguelite 主體架構規格

> 文件狀態：`v0.2 / Approved`
> 目標專案：`E:\ClaudeWorkingPlace\Game`  
> 單一事實來源：本索引所列的完整文件集

---

## 文件集使用方式

- 本檔是主體架構 Spec 的唯一入口；規範正文依下列順序拆分於 `game-architecture/`。
- 所有列入清單的章節共同構成同一份規格，任何單一章節都不得脫離其餘章節獨立解讀。
- REQ、DEC、ASM、RSK 與 AC 僅在正文定義一次；追溯矩陣仍是需求到驗收的權威映射。
- 外部複檢必須讀取本索引列出的全部檔案，並以 `file:line` 指向證據。
- v0.1 已完成使用者安排的外部複檢；repository 不保存不存在的複檢報告。v0.2 的 S2 戰鬥語意增補已於 2026-07-16 通過獨立 Gate A 複檢（Blocker 0／Major 0）並標為 `Approved`；機器驗證只核對本索引明列的 12 份正文。

## 文件清單

| 順序 | 主題 | 章節 | 文件 |
|---:|---|---|---|
| 1 | 文件控制與名詞表 | 0–1 | [00-document-control-and-glossary.md](game-architecture/00-document-control-and-glossary.md) |
| 2 | 產品定位、範圍與非目標 | 2–3 | [01-product-and-scope.md](game-architecture/01-product-and-scope.md) |
| 3 | 核心循環與遠征流程 | 4 | [02-core-loop.md](game-architecture/02-core-loop.md) |
| 4 | 遊戲系統 | 5 | [03-game-systems.md](game-architecture/03-game-systems.md) |
| 5 | 內容預算與局外成長 | 6–7 | [04-content-and-meta-progression.md](game-architecture/04-content-and-meta-progression.md) |
| 6 | 技術架構 | 8 | [05-technical-architecture.md](game-architecture/05-technical-architecture.md) |
| 7 | Stable ID、亂數與存檔 | 9 | [06-data-rng-and-save.md](game-architecture/06-data-rng-and-save.md) |
| 8 | 像素呈現、UI 與無障礙 | 10 | [07-pixel-presentation-and-ui.md](game-architecture/07-pixel-presentation-and-ui.md) |
| 9 | 測試策略與驗收條件 | 11 | [08-testing-and-acceptance.md](game-architecture/08-testing-and-acceptance.md) |
| 10 | 風險、決策與假設 | 12–13 | [09-risks-decisions-and-assumptions.md](game-architecture/09-risks-decisions-and-assumptions.md) |
| 11 | 需求追溯矩陣 | 14 | [10-traceability-matrix.md](game-architecture/10-traceability-matrix.md) |
| 12 | Claude 複檢、完成定義與技術參考 | 15–17 | [11-claude-review-and-references.md](game-architecture/11-claude-review-and-references.md) |

## 機器可讀 Manifest

<!-- spec-manifest:start -->
```json
{
  "manifest_schema_version": 2,
  "spec_version": "0.2",
  "status": "Approved",
  "files": [
    "game-architecture/00-document-control-and-glossary.md",
    "game-architecture/01-product-and-scope.md",
    "game-architecture/02-core-loop.md",
    "game-architecture/03-game-systems.md",
    "game-architecture/04-content-and-meta-progression.md",
    "game-architecture/05-technical-architecture.md",
    "game-architecture/06-data-rng-and-save.md",
    "game-architecture/07-pixel-presentation-and-ui.md",
    "game-architecture/08-testing-and-acceptance.md",
    "game-architecture/09-risks-decisions-and-assumptions.md",
    "game-architecture/10-traceability-matrix.md",
    "game-architecture/11-claude-review-and-references.md"
  ],
  "expected": {
    "file_count": 12,
    "section_count": 18,
    "mermaid_count": 3,
    "ids": {
      "REQ": 75,
      "AC": 79,
      "DEC": 14,
      "ASM": 6,
      "RSK": 12
    },
    "autoloads": {
      "ContentRegistry": "res://content/registry/content_registry_service.gd",
      "SaveService": "res://services/save/save_repository.gd",
      "SettingsService": "res://services/settings/settings_repository.gd",
      "AudioService": "res://services/audio/audio_coordinator.gd",
      "SceneRouter": "res://services/scene/scene_router_service.gd"
    },
    "public_apis": [
      {"class": "ContentRegistryService", "method": "resolve", "return": "ContentResolveResult"},
      {"class": "ContentRegistryService", "method": "try_resolve", "return": "ContentDefinitionView"},
      {"class": "ContentRegistryService", "method": "validate_all", "return": "ContentValidationReport"},
      {"class": "RunController", "method": "transition", "return": "RunTransitionResult"},
      {"class": "RunController", "method": "dispatch", "return": "CommandResult"},
      {"class": "RunController", "method": "view_state", "return": "RunViewState"},
      {"class": "RunController", "method": "can_transition", "return": "bool"},
      {"class": "SaveRepository", "method": "save", "return": "SaveResult"},
      {"class": "SaveRepository", "method": "load", "return": "LoadResult"},
      {"class": "SaveRepository", "method": "migrate", "return": "MigrationResult"},
      {"class": "RngService", "method": "derive_stream", "return": "RngDeriveResult"},
      {"class": "BattleSimulation", "method": "initialize", "return": "BattleInitializationResult"},
      {"class": "BattleSimulation", "method": "step", "return": "BattleStepResult"},
      {"class": "BattleSimulation", "method": "is_finished", "return": "bool"},
      {"class": "BattleSimulation", "method": "result", "return": "BattleResultQuery"},
      {"class": "EffectResolver", "method": "resolve", "return": "EffectResolutionResult"}
    ],
    "planned_public_apis": [
    ],
    "deferred_class_names": [
    ]
  },
  "aggregate_sha256": "b476e9c52af77101b4d7ab06dc2abbb5cbc3a91f1c788db20305c0feef8cfe2b"
}
```
<!-- spec-manifest:end -->

此 JSON 區塊是文件驗證器的權威輸入；路徑皆相對於本索引，順序即規格讀取順序。

## 章節導覽

| 章節 | 文件 |
|---|---|
| 0. 文件控制 | [開啟章節](game-architecture/00-document-control-and-glossary.md#section-0) |
| 1. 名詞表 | [開啟章節](game-architecture/00-document-control-and-glossary.md#section-1) |
| 2. 產品定位 | [開啟章節](game-architecture/01-product-and-scope.md#section-2) |
| 3. 範圍與非目標 | [開啟章節](game-architecture/01-product-and-scope.md#section-3) |
| 4. 核心循環與遠征流程 | [開啟章節](game-architecture/02-core-loop.md#section-4) |
| 5. 遊戲系統 | [開啟章節](game-architecture/03-game-systems.md#section-5) |
| 6. 垂直切片內容預算 | [開啟章節](game-architecture/04-content-and-meta-progression.md#section-6) |
| 7. 局外營地與水平成長 | [開啟章節](game-architecture/04-content-and-meta-progression.md#section-7) |
| 8. 技術架構 | [開啟章節](game-architecture/05-technical-architecture.md#section-8) |
| 9. Stable ID、亂數與存檔 | [開啟章節](game-architecture/06-data-rng-and-save.md#section-9) |
| 10. 像素呈現、UI 與無障礙 | [開啟章節](game-architecture/07-pixel-presentation-and-ui.md#section-10) |
| 11. 測試策略與驗收條件 | [開啟章節](game-architecture/08-testing-and-acceptance.md#section-11) |
| 12. 風險與緩解 | [開啟章節](game-architecture/09-risks-decisions-and-assumptions.md#section-12) |
| 13. 決策與假設 | [開啟章節](game-architecture/09-risks-decisions-and-assumptions.md#section-13) |
| 14. 需求追溯矩陣 | [開啟章節](game-architecture/10-traceability-matrix.md#section-14) |
| 15. Claude 複檢契約 | [開啟章節](game-architecture/11-claude-review-and-references.md#section-15) |
| 16. 文件完成定義 | [開啟章節](game-architecture/11-claude-review-and-references.md#section-16) |
| 17. 外部技術參考 | [開啟章節](game-architecture/11-claude-review-and-references.md#section-17) |

## 完整性基線

- 需求：75 個 REQ
- 驗收情境：79 個 AC
- 決策／假設／風險：14 個 DEC、6 個 ASM、12 個 RSK
- Mermaid 圖：3 張
- 12 章 aggregate SHA-256：以 Manifest 的 `aggregate_sha256` 為權威；每次正文修訂後由驗證器重算。
- 聚合雜湊只涵蓋 Manifest 依序列出的 12 份正文；索引與其他文件不納入。驗證器同時檢查檔案清單、跨檔連結、ID 唯一性、追溯完整性與內容守恆。

## 外部複檢契約與狀態

使用者已確認 v0.1 外部複檢完成；v0.2 的 S2 規格 gate 已於 2026-07-16 通過並核可。實作完成前另依 [S2 最終獨立複檢紀錄](../specs/combat-core/final-review.md) 對照 requirements；該紀錄明確標示為 Codex 實作複檢，不冒充 Claude 外部報告。複檢格式、分級、證據要求與禁止事項仍以 [Claude 複檢契約](game-architecture/11-claude-review-and-references.md#section-15) 為準。

