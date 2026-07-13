# PVE 自走棋 Roguelite 主體架構規格：文件控制與名詞表

> 文件集入口：[game-architecture-spec.md](../game-architecture-spec.md)  
> 文件狀態：`v0.1 / Ready for external review`  
> 本檔範圍：第 0–1 章

---

<a id="section-0"></a>

## 0. 文件控制

| 欄位 | 值 |
|---|---|
| 文件名稱 | PVE 自走棋 Roguelite 主體架構規格 |
| 文件版本 | 0.1 |
| 狀態 | Ready for external review |
| 建立日期 | 2026-07-13 |
| 目標引擎 | Godot 4.7 stable |
| 主要語言 | 型別化 GDScript |
| 首發平台 | PC |
| 首發語言 | 繁體中文（架構預留英文） |
| 遊戲模式 | 單人離線 PVE |
| 商業模式 | 單機買斷 |
| 主要審查者 | Claude |

### 0.1 文件目的

本文件集定義遊戲的產品邊界、核心玩法規則、內容預算、技術架構、資料契約、存檔策略與驗收方式。它的目標是讓後續實作者不需重新決定架構或核心規則，即可依階段建立灰盒原型、全系統切片與內容完整垂直切片。

本文件集不是完整角色設定集、數值平衡表、美術 bible、逐事件劇本或行銷計畫。這些內容應在本架構通過外部審查後另立文件，並引用本文件集中的 stable ID 與系統契約。

### 0.2 規範詞

- **MUST／必須**：垂直切片不可省略；違反即不符合規格。
- **SHOULD／應該**：預設實作；若偏離，必須新增決策紀錄並說明驗證方式。
- **MAY／可以**：可選擴充，不得阻擋垂直切片。
- **TUNE**：已給定初始值，但允許在不改變規則語意的前提下透過資料調整。

每個頂層 MUST 都使用需求 ID。需求所在小節中的規則表、順序、公式與限制，視為該小節 REQ 的具名細節條款，而不是未追蹤的新需求；若一段規範無法明確判定由哪個 REQ 擁有，審查者必須回報 `TRACE-GAP`。本文件集全文皆可作為需求證據，需求 ID 用於追溯，不得用來忽略未正確編號的規範。

ID 格式如下：

| 類型 | 格式 | 用途 |
|---|---|---|
| 需求 | `REQ-<領域>-NNN` | 可實作、可驗收的規則 |
| 決策 | `DEC-NNN` | 已鎖定的產品或架構選擇 |
| 假設 | `ASM-NNN` | 尚無實證但用於規劃的前提 |
| 風險 | `RSK-NNN` | 需監控與緩解的失敗可能 |
| 驗收 | `AC-NNN` | Given／When／Then 驗收情境 |

### 0.3 變更紀錄

| 版本 | 日期 | 狀態 | 摘要 |
|---|---|---|---|
| 0.1 | 2026-07-13 | Ready for external review | 建立產品、玩法、內容、架構、測試與複檢基線；同版本改為主索引加 12 份主題文件，規則語意不變 |

### 0.4 章節導覽

[0 文件控制](00-document-control-and-glossary.md#section-0) · [1 名詞表](00-document-control-and-glossary.md#section-1) · [2 產品定位](01-product-and-scope.md#section-2) · [3 範圍與非目標](01-product-and-scope.md#section-3) · [4 核心循環與遠征流程](02-core-loop.md#section-4) · [5 遊戲系統](03-game-systems.md#section-5) · [6 垂直切片內容預算](04-content-and-meta-progression.md#section-6) · [7 局外營地與水平成長](04-content-and-meta-progression.md#section-7) · [8 技術架構](05-technical-architecture.md#section-8) · [9 Stable ID、亂數與存檔](06-data-rng-and-save.md#section-9) · [10 像素呈現、UI 與無障礙](07-pixel-presentation-and-ui.md#section-10) · [11 測試策略與驗收條件](08-testing-and-acceptance.md#section-11) · [12 風險與緩解](09-risks-decisions-and-assumptions.md#section-12) · [13 決策與假設](09-risks-decisions-and-assumptions.md#section-13) · [14 需求追溯矩陣](10-traceability-matrix.md#section-14) · [15 Claude 複檢契約](11-claude-review-and-references.md#section-15) · [16 文件完成定義](11-claude-review-and-references.md#section-16) · [17 外部技術參考](11-claude-review-and-references.md#section-17)

---

<a id="section-1"></a>

## 1. 名詞表

| 名詞 | 定義 |
|---|---|
| 遠征／Run | 從選擇指揮官進入第一幕，到通關第三幕或遠征生命歸零的一次遊戲 |
| 幕／Act | 遠征中的大型階段，共三幕，各有獨立節點圖、基礎傷害與 Boss |
| 層／Layer | 節點圖中沿前進方向的一列候選節點；玩家每層只能選擇一個可達節點 |
| 節點／Node | 戰鬥、菁英、商人、事件、休整、寶藏或 Boss 的一次遭遇 |
| 備戰／Prepare | 玩家可購買、出售、刷新、升級、佈陣、鍛造與檢視敵情的階段 |
| 棋子／Unit | 可購買、升星、上陣或放置板凳的玩家戰鬥單位 |
| 敵方單位 | 由遭遇定義產生、不可由該遭遇直接購買的戰鬥實體 |
| 人口／Capacity | 玩家可同時部署的棋子數；常規由玩家等級決定 |
| 羈絆／Trait | 依上場的不同棋子 ID 計數，達門檻後生效的隊伍規則 |
| 零件／Component | 兩兩鍛造成完整裝備的素材 |
| 完整裝備／Equipment | 裝到單一棋子、最多三件且裝上後綁定的物品 |
| 遺物／Relic | 影響整隊、經濟或遠征規則的局內物品，最多啟用五件 |
| 指揮官／Commander | 局外選擇、本人不上場，提供起始內容與規則型被動的角色 |
| Stable ID | 不隨顯示名稱、檔名或排序改變的命名空間識別碼 |
| 內容版本 | 用於辨識資料定義集合的版本，與程式版本、存檔 schema 分離 |
| 戰鬥摘要 | 為決定性驗證保存的結果、tick 數、存活者與事件雜湊 |

---

[返回文件集入口](../game-architecture-spec.md) · [產品定位、範圍與非目標 →](01-product-and-scope.md)
