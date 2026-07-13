# PVE 自走棋 Roguelite 主體架構規格：Claude 複檢、完成定義與技術參考

> 文件集入口：[game-architecture-spec.md](../game-architecture-spec.md)  
> 文件狀態：`v0.1 / Approved`
> 本檔範圍：第 15–17 章

---

<a id="section-15"></a>

## 15. Claude 複檢契約

### 15.1 審查目標

Claude 應只依本文件集內的需求、決策、假設與驗收證據，檢查：

1. 規則是否互相矛盾或存在無法到達的狀態。
2. 每個 MUST 是否有明確擁有者、輸入、輸出與失敗行為。
3. Resource、DTO、服務與存檔是否足以實作而沒有隱藏決策。
4. 決定性、有限卡池、升星、裝備與 Boss 重戰是否守恆。
5. AC 是否可自動化或有明確人工驗證方式。
6. 內容完整切片與三道門檻是否出現需求漂移。
7. 風險是否有可觀察觸發條件及實際緩解。

Claude 不應：

- 自行新增 PvP、連線、F2P、戰中主動操作或其他非目標。
- 把主觀風格偏好列為 blocker。
- 因平衡初值標記為 TUNE 就把已鎖定的規則語意視為未決。
- 未引用需求 ID、`TRACE-GAP` 或精確 `file:line` 證據就宣稱缺陷。

本文件集全文的規範句都可作為證據，不限於已編號句。若發現真實規範問題但無法判定 owning REQ，Claude 必須以 `Related IDs: TRACE-GAP` 回報並指出精確 `file:line`；不得為了符合格式而替文件補造需求 ID。

### 15.2 嚴重度

| 等級 | 定義 |
|---|---|
| Blocker | 無法實作、資料會遺失／複製、核心規則互斥，或無法達成垂直切片 |
| Major | 可實作但會造成明顯錯誤、不可驗收、存檔不相容或核心體驗偏離 |
| Minor | 不阻擋實作，但有局部歧義、維護成本或可讀性問題 |
| Question | 文件證據不足以判定，需原作者確認；不得假設答案 |

### 15.3 必要輸出格式

每一項意見必須使用：

```text
Severity: Blocker | Major | Minor | Question
Related IDs: REQ-... / DEC-... / ASM-... / RSK-... / AC-... / TRACE-GAP
Evidence: <relative-file>:<line>、章節與原文摘要
Issue: 具體缺陷
Failure scenario: 可重現情境
Proposed fix: 最小、符合既有範圍的修正
```

若沒有 Blocker 或 Major，必須明確寫出「未發現 Blocker／Major」，不可用籠統摘要代替。

### 15.4 可直接提供給 Claude 的審查提示

```text
請審查這份 PVE 自走棋 Roguelite 主體架構規格。

優先順序：
1. correctness 與規則矛盾
2. 資料守恆、存檔與 migration
3. 決定性與 RNG 隔離
4. 無法驗收或缺少擁有者的 MUST
5. 範圍漂移與效能風險

只能依本文件集全文作證據，不得引入文件外需求，也不得自行補造 REQ、DEC、ASM、RSK、AC。
若規範句沒有可判定的 owning ID，請使用 Related IDs: TRACE-GAP。
每項意見使用 Severity / Related IDs / Evidence / Issue /
Failure scenario / Proposed fix 格式。
Evidence 必須包含 <relative-file>:<line>；沒有精確 `file:line` 的意見視為不完整。
風格偏好放在最後的非必改建議；若沒有 Blocker 或 Major，請明說。
```

---

<a id="section-16"></a>

## 16. 文件完成定義

本文件集可由 `Ready for external review` 轉為 `Approved` 的條件：

- 所有 REQ 有唯一 ID，並出現在追溯矩陣。
- 所有 MUST 至少連到一個 Given／When／Then AC。
- 沒有未標記的 blocking open question。
- 所有服務、Resource、DTO 與存檔資料有單一擁有者。
- 三張 Mermaid 圖可解析，且不與文字規則矛盾。
- TUNE 值與固定規則可清楚區分。
- 風險包含機率、影響、緩解與觸發條件。
- Claude 複檢的 Blocker／Major 已解決，或由使用者以新 DEC 明確接受。
- 變更後重新執行 ID、連結、Markdown 與追溯檢查。

---

<a id="section-17"></a>

## 17. 外部技術參考

- [Godot 官方版本封存與 4.7 stable](https://godotengine.org/download/archive/)
- [Godot：GDScript static typing](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html)
- [Godot：Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [Godot：Saving games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)
- [Godot 4.7：FileAccess](https://docs.godotengine.org/en/4.7/classes/class_fileaccess.html)
- [Godot 4.7：DirAccess](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html)
- [GUT 9.7.1 release](https://github.com/bitwes/Gut/releases/tag/v9.7.1)

---

**文件結尾**

[← 需求追溯矩陣](10-traceability-matrix.md) · [返回文件集入口](../game-architecture-spec.md)
