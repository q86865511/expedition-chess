# PVE 自走棋 Roguelite 主體架構規格：需求追溯矩陣

> 文件集入口：[game-architecture-spec.md](../game-architecture-spec.md)  
> 文件狀態：`v0.2 / Approved`
> 本檔範圍：第 14 章

---

<a id="section-14"></a>

## 14. 需求追溯矩陣

| 需求 | 對應決策／假設 | 規格章節 | 驗收 | 主要測試層 |
|---|---|---|---|---|
| REQ-PROD-001 | DEC-013 | 2、3 | AC-033 | 原創性審查 |
| REQ-PROD-002、REQ-PROD-004 | DEC-003、DEC-007；ASM-004 | 2、6 | AC-032 | Playtest |
| REQ-PROD-003 | DEC-001 | 2、3 | AC-037 | 離線 end-to-end |
| REQ-SCOPE-001 | DEC-003、DEC-009 | 3、4、7 | AC-001、AC-042、AC-043 | End-to-end |
| REQ-SCOPE-002 | DEC-007；ASM-001 | 3、6 | AC-033、AC-038 | 資產驗證／審查 |
| REQ-RUN-001、REQ-RUN-002、REQ-RUN-003 | DEC-003 | 4 | AC-001、AC-002、AC-045 | Map soak |
| REQ-RUN-004、REQ-RUN-005 | DEC-012 | 4、9 | AC-003、AC-020、AC-035、AC-046、AC-073 | 存讀整合 |
| REQ-BOARD-001、REQ-BOARD-002 | DEC-004 | 5.1 | AC-004 | Domain／UI 整合 |
| REQ-BOARD-003、REQ-BOARD-004 | DEC-004 | 5.2、11 | AC-005、AC-034、AC-056 | 驗證器／壓測 |
| REQ-UNIT-001、REQ-UNIT-002 | DEC-005、DEC-007 | 5.3、5.9 | AC-013、AC-014、AC-017、AC-060 | 單元／整合 |
| REQ-TRAIT-001、REQ-TRAIT-002 | DEC-007 | 5.4 | AC-015、AC-024 | 單元／canonical |
| REQ-COMBAT-001 | DEC-002 | 5.5、10 | AC-006、AC-024 | UI／整合 |
| REQ-COMBAT-002、REQ-COMBAT-003、REQ-COMBAT-004 | DEC-011、DEC-012、DEC-014 | 5.6、5.7、8、9 | AC-007、AC-008 | Canonical／soak |
| REQ-COMBAT-005、REQ-COMBAT-006 | DEC-003、DEC-006 | 5.8 | AC-009、AC-010、AC-035 | 單元／存讀整合 |
| REQ-ECON-001 | DEC-005 | 5.9 | AC-011、AC-013、AC-048 | 單元／property |
| REQ-ECON-002 | DEC-006 | 5.9 | AC-012、AC-035 | 單元／整合 |
| REQ-ECON-003 | DEC-005；ASM-005 | 5.9、8.8 | AC-049、AC-062 | 單元／靜態分析 |
| REQ-ECON-004 | DEC-005、DEC-012 | 5.9、5.12 | AC-013、AC-058、AC-072、AC-073 | Ledger／故障注入 |
| REQ-ITEM-001、REQ-ITEM-002 | DEC-008 | 5.10 | AC-016、AC-017、AC-060、AC-072 | 驗證器／整合 |
| REQ-RELIC-001 | DEC-008 | 5.11 | AC-018 | 整合／存讀 |
| REQ-REWARD-001 | DEC-012 | 5.12、9 | AC-019、AC-020、AC-035 | 存讀整合 |
| REQ-REWARD-002 | DEC-007、DEC-012 | 5.12 | AC-057、AC-072 | Overflow 整合 |
| REQ-ENEMY-001、REQ-ENEMY-002 | DEC-002、DEC-007 | 5.5、5.13 | AC-006、AC-024、AC-050 | 內容／整合 |
| REQ-ENEMY-003 | DEC-002、DEC-012 | 4.4、5.13 | AC-050、AC-079 | 內容／整合 |
| REQ-CONTENT-001 | DEC-007、DEC-008 | 6、11 | AC-016、AC-034、AC-047 | 內容驗證 |
| REQ-META-001 | DEC-009 | 7 | AC-021、AC-042、AC-043、AC-044 | End-to-end |
| REQ-META-002、REQ-META-003 | DEC-009、DEC-012 | 7、9 | AC-022、AC-023、AC-078 | Profile／run 整合 |
| REQ-META-004 | DEC-009、DEC-012 | 7、9.9 | AC-061、AC-073 | 結算故障注入 |
| REQ-TECH-001 | DEC-010 | 8.1 | AC-036 | Build／依賴檢查 |
| REQ-TECH-002 | DEC-011 | 8.4、8.5 | AC-039 | FSM 整合 |
| REQ-TECH-003 | DEC-010、DEC-011 | 8.7 | AC-054、AC-076 | 靜態分析／API negative |
| REQ-TECH-004 | DEC-011、DEC-012 | 8.5、8.7 | AC-039、AC-065 | 交易／故障注入 |
| REQ-TECH-005 | DEC-010 | 8.5、8.7 | AC-068 | 靜態分析 |
| REQ-TECH-006 | DEC-011 | 8.7 | AC-076 | API negative／no-partial |
| REQ-DATA-001 | DEC-010、DEC-011 | 8.8 | AC-024、AC-047、AC-075 | 內容／靜態分析 |
| REQ-DATA-002 | DEC-010、DEC-011 | 8.9 | AC-040 | 序列化／靜態分析 |
| REQ-DATA-003 | DEC-012 | 9.1 | AC-025、AC-026、AC-051、AC-052 | Migration |
| REQ-DATA-004 | DEC-011 | 8.9、9.5 | AC-055 | Round-trip／ownership |
| REQ-DATA-005 | DEC-011、DEC-012、DEC-014 | 9.3 | AC-041、AC-064 | Canonical／hash |
| REQ-DATA-006 | DEC-009、DEC-012 | 9.5、9.8 | AC-023、AC-070、AC-078 | 相容性／存讀 |
| REQ-DATA-007 | DEC-011、DEC-012 | 9.1、9.5 | AC-073 | Property／存讀 |
| REQ-DATA-008 | DEC-010、DEC-011 | 8.8、8.9 | AC-024、AC-075、AC-078 | Mutation／catalog generation |
| REQ-EFFECT-001 | DEC-006、DEC-011、DEC-014 | 8.10、9.9 | AC-059、AC-067、AC-073、AC-074 | 效果／Boss 整合 |
| REQ-EFFECT-002 | DEC-011、DEC-014 | 8.8–8.10 | AC-067、AC-074 | 型別／內容驗證 |
| REQ-RNG-001 | DEC-012 | 9.2、9.3 | AC-007、AC-027、AC-041、AC-064 | Stream isolation／canonical |
| REQ-RNG-002 | DEC-012 | 9.2 | AC-063 | Golden／邊界 vectors |
| REQ-SAVE-001 | DEC-012 | 9.4、9.7 | AC-026、AC-069 | Atomic I/O |
| REQ-SAVE-002 | DEC-012 | 9.6、9.9 | AC-020、AC-035、AC-046、AC-058、AC-066 | 恢復／故障注入 |
| REQ-SAVE-003 | DEC-012 | 9.8 | AC-025、AC-051、AC-052 | Migration |
| REQ-SAVE-004 | DEC-012 | 9.6 | AC-046、AC-065 | Commit-before-present |
| REQ-SAVE-005 | DEC-012 | 9.5、9.9 | AC-035、AC-066、AC-072 | Union state／恢復 |
| REQ-SAVE-006 | DEC-012 | 9.7 | AC-026、AC-069 | I/O fault injection |
| REQ-UX-001、REQ-UX-002、REQ-UX-003 | DEC-002、DEC-010、DEC-015；ASM-006 | 10 | AC-007、AC-028、AC-029、AC-081、AC-082 | 視覺／無障礙 |
| REQ-UX-006 | DEC-015 | 10.7 | AC-080 | 呈現層整合 |
| REQ-UX-004 | ASM-003 | 10.6 | AC-031 | 效能 |
| REQ-UX-005 | ASM-006 | 10.5、11.2 | AC-077 | Localization 靜態驗證 |
| REQ-QA-001 | DEC-010、DEC-011 | 11.2 | AC-002、AC-016、AC-034、AC-047、AC-074 | 內容驗證 |
| REQ-QA-002 | DEC-011、DEC-012；ASM-004 | 11 | AC-007、AC-025、AC-030、AC-031、AC-032 | 完整 release gate |
| REQ-QA-003 | DEC-012 | 0.2、11、16 | AC-053 | 文件追溯檢查 |
| REQ-QA-004 | DEC-010、DEC-011 | 11.4 | AC-071 | CI runner contract |

矩陣中每個 REQ 至少有一個 AC。新增需求時，若未同時新增或引用可觀察 AC，文件驗證應失敗。

### 14.1 假設驗證追溯

| 假設 | 影響的需求／決策 | 證據或驗收 | 決策點 |
|---|---|---|---|
| ASM-001 | REQ-SCOPE-002、G0／G1／G2 門檻 | AC-038、各門檻實際工時 | 每個 gate 結束 |
| ASM-002 | REQ-PROD-002、REQ-PROD-004、REQ-COMBAT-001 | AC-006、AC-032 與理解率問卷 | G0 與 G1 playtest |
| ASM-003 | REQ-UX-004 | AC-031、最低規格實機資料 | G1 效能 gate |
| ASM-004 | REQ-PROD-002、REQ-PROD-004、REQ-QA-002 | AC-032 與樣本信賴區間 | G2 playtest |
| ASM-005 | REQ-ECON-003 及所有 TUNE 初值 | AC-048、AC-049、AC-062、G0 批次結果 | G0 平衡 review；改語意則新增 DEC |
| ASM-006 | REQ-UX-001、REQ-UX-003 | AC-028、AC-029 與發行規劃 | G1 localization review |

---

[← 風險、決策與假設](09-risks-decisions-and-assumptions.md) · [返回文件集入口](../game-architecture-spec.md) · [Claude 複檢、完成定義與技術參考 →](11-claude-review-and-references.md)
