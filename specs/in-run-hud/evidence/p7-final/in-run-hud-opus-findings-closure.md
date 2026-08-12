# in-run-hud — Opus findings closure

日期：2026-08-12  
狀態：**EXTERNAL OPUS RE-REVIEW APPROVED／13 FINDINGS CLOSED OR ACCEPTED／T32 CLOSED**

## 稽核來源與不可改寫紀錄

- 原始外部 review：`.pipeline/reviews/in-run-hud-opus-external-review.md`。
- 原始 verdict：`CHANGES_REQUESTED`。
- 使用者轉交附件 SHA-256：
  `8D2DFD0EF66D7FD93FA6205156A2F739F2046F5B97DC9A3564B8407CAE1DAF6B`。
- External Opus closure re-review verdict：`APPROVED`；原文保存於
  `.pipeline/reviews/in-run-hud-opus-re-review-approved.md`，並鏡像至
  `specs/in-run-hud/evidence/p7-final/in-run-hud-opus-re-review-approved.md`；附件 SHA-256：
  `1C888B646C5CF1888DB64CD1CFD67906D284AF670E1F49846C83AB02A94A1129`。
- 原始 `CHANGES_REQUESTED` review 保持不變，未被 closure 或 re-review 覆寫。

## Fresh gate read-back

- `tools/run-tests.ps1 -Suite All`：2026-08-11T18:27:27Z～18:49:46Z，exit 0。
- GUT：326 scripts、1354／1354 tests、37956／37956 assertions、0 failures、0 errors。
- Spec：4076 cases、`passed=true`、`failures=[]`、exit 0。
- Import／Smoke／Gut／Content／Canonical／Combat／Expedition／ActEliminationGate／Spec：
  全數取得預期 exit 0；runner contract negative fixtures 維持預期非 0。
- Fresh formal evidence：137／137 cases（baseline 128＋shop-tier 9）、`ok=true`、exit 0、
  `issues=[]`；`real-appdata-integrity.json` 為 `ok=true`，before／after SHA-256 均為
  `b68bfb1afb4ab0ed9b90a1089ab3b1550ea318dcd4cde3c42b58a85866b22867`，完成後 Godot process 0。
- 上述 final current-source All 已包含修正後 evidence runner contract；各 gate 與 fresh
  137／137 visual evidence 均已讀回。

## 13 項 finding decision table

| ID | 決策 | Closure 與證據 | 殘留／限制 |
|---|---|---|---|
| P1-1 | **CLOSED** | `InRunHudShell.mount_unit_inspector()` 保留唯一 typed inspector 引用；正式 `RunPrepareScreen` composition 只掛一份面板。`test_prepare_unit_inspection_t17.gd` 覆蓋真實 selector callback、empty→selected→empty，以及 projected target→overlay→surface→screen 的 hover-exit relay。 | IRH-REQ-014 仍因 sell quote／高星或帶裝出售確認而維持 PARTIAL；這不是 P1 面板失效回歸。 |
| P2-1 | **CLOSED** | `world_board_overlay_mapper.gd` 先將 `(0,-56)` sprite-head offset 套於 world foot point，再經 `WindowCoordinateMapper.world_to_screen()`；只有 bar 尺寸維持 screen px。 | 無本 finding 殘留。 |
| P2-2 | **CLOSED** | Overlay ordering 與 renderer 共用 projected foot-y→logical-x→stable id 規則；`WorldBoardSnapshot.is_valid()` 拒絕 duplicate logical cells。`test_world_board_overlay_t29.gd` 覆蓋順序與重複格 fail-closed。 | 無本 finding 殘留。 |
| P2-3 | **CLOSED** | `WorldBoardSnapshotFactory.build_combat()` 對 active `COMBAT_PENDING`＋empty inspections 回傳 typed invalid sentinel；只有 typed `BATTLE_RESULT_PENDING` committed-summary recovery 可掛合法空世界。對應 focused factory suite 為 10 tests／87 assertions／exit 0。 | 無本 finding 殘留。 |
| P2-4 | **CLOSED** | `CombatWorldEventProjection` 以 atomic dead tombstones／unrenderable lifecycle 處理 death 後 late damage/heal/mana/move/spawn；已死亡或不可渲染目標為 no-op，不再拒絕整個 event window。 | Dynamic summon 仍缺 visual/max-stat authority，故 IRH-REQ-007 保持 PARTIAL；既有單位播放凍結 finding 已 closure。 |
| P2-5 | **CLOSED** | Initial settlement 與 retry 共用 `_settlement_is_blocked()`；paused playback、system-menu 任一子狀態與 confirmation modal 都阻止 route transition。 | 無本 finding 殘留。 |
| P2-6 | **CLOSED** | System menu 開啟時停用 background root recursive focus，保存所有 descendant 原 focus mode，監聽 late `node_added`／late-enabled controls，關閉後精確還原；不再依 open-time allowlist。 | 正式 settings application port 尚未注入，故 IRH-REQ-004 仍為 PARTIAL。 |
| P2-7 | **CLOSED（DOCUMENTED RESIDUAL）** | Cost 只顯示一次 authoritative value；tier 以 non-text pips；star true/false 以 rise/flat shapes 且不冒充 0/1；移除 trait tier／relic heading 錯用；danger cue 使用目前節點型別的 localization key＋warning pattern。 | Progress completed/current/future 與 streak accessibility localization 仍是明列產品缺口，不因本 finding closure 而視為完成。 |
| P2-8 | **ACCEPTED（PARTIAL FIX／LOW-RISK RESIDUAL）** | `custom_minimum_size` 改用 lexical assignment scanner，能拒絕真 assignment 且忽略註解、字串與讀取；唯一 production setter 為 metrics helper。System-menu 關鍵行為另以 executable unit/integration tests 驗證，不再只靠 token matching。 | Static collector 仍保留部分 `source.contains` 作補充 heuristic；lexical scanner 理論上不偵測 `custom_minimum_size.x = ...`／`.y = ...` 分量賦值，但目前 `presentation/` 零匹配，且 menu correctness 不只依賴此 scanner，external re-review 判定非 OPEN。 |
| P2-9 | **CLOSED（EXPLICIT POINTER-QA LIMIT）** | `test_projected_drag_matches_button_canonical_layout.gd` 以兩次 fresh production boot 比較 button path 與 projected target DnD 的 persisted canonical layout；`saved_at_utc` 是唯一 publication-metadata allowlist，layout paths為操作 allowlist，其餘完整 document paths 全部 denylist。Focused：1 test／20 assertions／exit 0。 | 測試自 typed payload 進入正式 projected target，不宣稱 native pointer gesture 自動化；canonical command/result 等價已驗。 |
| P2-10 | **ACCEPTED（FIXTURE LIMIT）** | BoardGrid 由可能零次迴圈改為精確 `PLAYER_HALF_CAPACITY`；system-menu 補四 route、late-added／late-enabled focus 行為；shop tier fixture 仍由 pinned typed production inputs 建立。 | REWARD 九圖仍是 typed `PendingRewardState` fixture，非 fresh-profile 自然路徑；manifest 必須持續揭露。 |
| P2-11 | **CLOSED** | 全 `presentation/` 的 board／player-half／bench geometry 都改引用 `BoardPreparationValidator.BOARD_WIDTH`、`BOARD_HEIGHT`、`PLAYER_MAX_Y`、`PLAYER_HALF_CAPACITY`、`BENCH_CAPACITY` 或由其推導的 `float(size)-0.5` 半開邊界；`range(9)`、8／7.5 等權威幾何複本已收斂。BoardProjection 的 8×8 行為、basis、affine inverse 與 1e-6 round-trip 契約不變。 | 無本 finding 殘留。 |
| P2-12 | **ACCEPTED NONBLOCKING** | Shop star-up preview 只在 operation-boundary snapshot rebuild 執行，每次最多五個 offers；不是逐幀 ViewModel polling。Clone＋merge 是取得權威升星結果且不保留 domain mutable reference 的必要成本。 | 列為效能觀察項；若實測 refresh latency 超標再以 profiler 證據開新 finding。 |

## Requirement 與 task disposition

- Finding closure 不等於整片完成。需求台帳維持 **PASS 8／PARTIAL 7／BLOCKED 2**。
- T31 維持未勾：fresh visual evidence 與 final current-source All 均已綠，但既有
  PARTIAL／BLOCKED requirements 尚未 closure。
- T32 已關閉：external Opus closure re-review verdict 為 `APPROVED`，13 項 findings 為
  10 項 `CLOSED`、3 項 `ACCEPTED`、0 項 `OPEN`；原文與 SHA-256 已保存於上述雙路徑。
- 仍不得寫成完成：正式 settings port、odds／quote、inactive/distinct trait authority、
  forge recipe preview、人口／羈絆 drag preview、完整 keyboard E2E、dynamic summon authority、
  sell confirmation、progress accessibility localization，以及 REWARD 自然路徑證據。

## Re-review disposition

- Verdict：`APPROVED`。
- 前次 13 findings closure：10 項 `CLOSED`、3 項 `ACCEPTED`、0 項 `OPEN`。
- T32：`CLOSED`。
- T31：仍未完成；需求台帳仍為 **PASS 8／PARTIAL 7／BLOCKED 2**。
- 本核可只涵蓋前次 findings closure，不把仍明載的產品缺口改判為完成。
