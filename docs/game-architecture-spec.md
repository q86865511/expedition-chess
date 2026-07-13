# PVE 自走棋 Roguelite 主體架構規格

> 文件狀態：`v0.1 / Ready for external review`  
> 目標專案：`E:\ClaudeWorkingPlace\Game`  
> 單一事實來源：本索引所列的完整文件集

---

## 文件集使用方式

- 本檔是主體架構 Spec 的唯一入口；規範正文依下列順序拆分於 `game-architecture/`。
- 所有列入清單的章節共同構成同一份規格，任何單一章節都不得脫離其餘章節獨立解讀。
- REQ、DEC、ASM、RSK 與 AC 僅在正文定義一次；追溯矩陣仍是需求到驗收的權威映射。
- 外部複檢必須讀取本索引列出的全部檔案，並以 `file:line` 指向證據。
- 本次僅重構文件結構，未改變任何遊戲規則、技術決策、初始數值或驗收語意。

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
  "manifest_schema_version": 1,
  "spec_version": "0.1",
  "status": "Ready for external review",
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
  ]
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

- 需求：74 個 REQ
- 驗收情境：78 個 AC
- 決策／假設／風險：13 個 DEC、6 個 ASM、12 個 RSK
- Mermaid 圖：3 張
- 拆分前規格 SHA-256：`df629251ab6d9b945f44986c4d0290c8c58275b3e771b3258647df581196ba64`
- 拆分後的驗證必須同時檢查檔案清單、跨檔連結、ID 唯一性、追溯完整性與內容守恆。

## 外部複檢入口

複檢格式、分級、證據要求與禁止事項定義於 [Claude 複檢契約](game-architecture/11-claude-review-and-references.md#section-15)。

