# Opus closure re-review — APPROVED

- 記錄日期：2026-08-12
- 原始附件：`C:\Users\q86865511\.codex\attachments\bfd75d97-9200-48fe-a1f3-f1947d74c815\pasted-text.txt`
- 附件 SHA-256：`1C888B646C5CF1888DB64CD1CFD67906D284AF670E1F49846C83AB02A94A1129`
- 保存方式：以下正文逐字保存原始附件，未改寫 verdict、表格、行號或未重跑揭露。

---

1. Verdict
APPROVED（前次 13 項 findings closure re-review 通過）

本核可僅針對「前次 P1-1、P2-1～P2-12 是否正確 closure」。manifest 維持的 PASS 8／PARTIAL 7／BLOCKED 2 產品缺口台帳誠實且不受本核可影響（見第 4 節）。

2. 13-row decision table
ID	判定	親驗證據（檔案:行號）
P1-1	CLOSED	in_run_hud_shell.gd:77（mount_unit_inspector 保引用 reparent）、:536-552（_unit_inspector typed 引用優先）、run_prepare_screen.gd:658（改呼叫 mount，不再自行 find+remove）。test_prepare_unit_inspection_t17.gd:124 斷言整棵 screen tree 恰一份 UnitInspector、真實 selector item_selected 訊號驅動同一面板 empty→selected→empty、hover 離開還原選取或空狀態；:208 另測 target→overlay→surface→screen 的 hover-exit relay。重跑 8 tests／0 failures。
P2-1	CLOSED	world_board_overlay_mapper.gd:13（SPRITE_HEAD_WORLD_OFFSET(0,-56) 世界空間）、:58-66（頭頂點先加世界 offset 再過 world_to_screen，隨 integer_scale 縮放）；bar 尺寸維持 screen px，符合 design §5「固定像素尺寸」。
P2-2	CLOSED	mapper :37-46 以 _unit_precedes 排序（projected foot-y，與 world_board_renderer.gd:35,108-115 同鍵）；world_board_snapshot.gd:39-42 拒絕重複 logical_cell。t29 新增 test_overlay_placement_order_matches_renderer_logical_depth（:89）與 test_duplicate_logical_cells_fail_snapshot_and_overlay_closed（:121）。
P2-3	CLOSED	world_board_snapshot_factory.gd:58-70：空 inspections 一律 invalid sentinel，唯 _is_committed_summary_recovery（:107-112，typed BATTLE_RESULT_PENDING）可掛合法空世界。測試 :123（fail-closed）與 :138（recovery 空世界）。重跑 10 tests／0 failures。
P2-4	CLOSED	combat_world_event_projection.gd:17-18（_dead_entity_ids tombstones）；死後 late damage/heal/mana/move/spawn 為 no-op（move handler 對 dead/unrenderable 早退回 &""）；:51-52/74-75 維持原子回滾。重跑 12 tests 含 late-events、同 id respawn、tombstone 不外漏。
P2-5	CLOSED	run_combat_screen.gd:236（_settlement_is_blocked = paused ∨ is_background_input_blocked）同時用於 :196 initial 與 :224 retry；production_screen.gd 的 is_background_input_blocked = modal ∨ 選單任一開啟子狀態。測試 test_settle_retry_freezes_while_paused_or_system_menu_blocks_background（:237）與 test_initial_settle_waits_for_every_system_menu_state_and_confirmation_modal（:268）。
P2-6	CLOSED	system_menu_overlay.gd:391-393（background root focus_behavior_recursive 停用，結構性涵蓋 late-enabled）、:401-431（tree.node_added 監聽 late-added＋逐控制項記錄原 focus_mode）、:434-448（關閉時 disconnect＋精確還原）。契約測試 test_open_menu_traps_unlisted_late_added_and_late_enabled_background_focus（:214，斷言 late-added 開啟中 FOCUS_NONE、關閉後還原 FOCUS_ALL）。
P2-7	CLOSED（殘留＝既列產品缺口）	cost 只顯示一次權威值（production_screen.gd:1479-1487）；tier 以 pips 非文字非色彩 cue（:1549-1560）；star-up 僅為 true 時附「星級」文字＋形狀 cue，metadata 才存 0/1（:1500-1524）；inspector「星級=star、花費=cost_tier」語意正確（in_run_hud_shell.gd:140-145，catalog 查證 key 字義相符）；進度列 prepare.panel.expedition＝「遠征資訊」為正確用途；combat DangerSemantics 已移除。t17:319 另有 mislabel 防護測試。progress accessibility 文字缺口仍在 manifest 明列，非本 finding 範圍。
P2-8	ACCEPTED（partial fix，低風險殘留）	presentation_ui_static_gate.gd:1212-1248 lexical scanner：跳過註解／單引號／三引號字串、identifier 邊界、=（排除 ==）與複合賦值；豁免精確限定 :178-183 單一 metrics setter 路徑。測試 :89（真賦值必紅）、:110-121（註解／字串／讀取不誤判且後續真賦值仍攔）。新觀察（不阻擋）：scanner 不偵測 custom_minimum_size.x = ... 分量賦值——我已 grep 全 presentation/，目前零出現，屬理論盲點，建議記入殘留清單。
P2-9	CLOSED（pointer-gesture 限制已明文接受）	test_projected_drag_matches_button_canonical_layout.gd:25-96：兩次 fresh production boot、真 REFRESH_SHOP/BUY_UNIT intent、按鈕路徑按真實 action button；拖曳路徑經真 mapper＋BoardProjection 座標鏈進正式 _can_drop_data/_drop_data（:191-200），前次「直呼私有 handler、座標鏈零覆蓋」缺口已補。digest 為 persisted canonical layout（:366-376）；saved_at_utc 是唯一 publication allowlist、其餘全文件 denylist 以逐路徑 diff＋digest 雙重驗證（:16-20、:432-448）；:184-187 明文不宣稱 native pointer QA。重跑 1 test／20 assertions／0 failures。
P2-10	ACCEPTED	BoardGrid 由零次迴圈改為精確 BoardPreparationValidator.PLAYER_HALF_CAPACITY 計數斷言（test_prepare_world_board_layering.gd:283）；system-menu 契約擴為 6 tests 含四 route 與 late-focus；REWARD typed fixture 限制持續在 manifest :30-32 揭露。fixture 限制屬明列接受範圍。
P2-11	CLOSED	board_draft_move_adapter.gd:8-10、board_projection.gd:6-7、run_prepare_screen.gd:718-745,1136-1138 等全數改引用 BoardPreparationValidator 常數；grep 全 presentation/ 無殘留 range(9)／裸 8／7.5 權威複本。
P2-12	ACCEPTED NONBLOCKING	成本僅發生在 operation-boundary snapshot rebuild（非逐幀），上限五個 offer；clone＋domain merge service 是取得權威升星結果且不持 mutable reference 的合理代價。接受為效能觀察項，reopen 判準（profiler 證據）已記載。
3. OPEN findings
無 OPEN。 未發現可重現且違反既定 contract 的新 P0／P1／P2。唯一新觀察（P2-8 的 .x/.y 分量賦值盲點）目前零出現、不違反任何現行契約，建議記入 closure 文件殘留欄即可，不構成 OPEN。

4. 區分：findings closure vs 產品缺口
a. 前次 13 項 findings：全部正確 closure——11 項 FIXED 經我逐項對原始碼與測試親驗，2 項（P2-10、P2-12）與 1 項 partial（P2-8）的接受理由成立且殘留已明文記載。closure 文件未把任何 finding 修復冒充為 requirement 完成。

b. 產品缺口（不因本 re-review 改變）：manifest 維持 PASS 8／PARTIAL 7／BLOCKED 2 是正確的。正式 settings port 注入、shop odds／quote_* typed API、inactive trait／下一門檻 authority、forge recipe preview 注入、拖曳人口／羈絆 typed preview、純鍵盤完整 E2E、dynamic summon visual authority、sell quote／確認 parity、progress accessibility 文字、REWARD 自然路徑證據——均仍未完成，T10／T14／T16／T17／T19／T20／T21／T25 未勾與此一致。（另註：工作樹已出現 test_active_trait_progress_projection.gd，顯示 trait progress 方向已有前置工作，但不影響本次台帳。）

5. T32 disposition
T32 可視為僅剩一個條件：把本 re-review 的 APPROVED verdict 原文落檔（.pipeline/reviews/ 或 closure 文件指定位置，保存原始 verdict 不得改寫）。tasks.md T32 要求的兩軌——codex MCP 第二審（已落檔）＋外部 Opus review（原始 CHANGES_REQUESTED 已保存、本次 re-review 對 13 項 findings 全數 CLOSED／ACCEPTED）——在落檔後即齊備。注意：T32 關閉≠本片完成；T31 仍因第 4b 節產品缺口維持未勾，此判定正確且應維持。

6. 實際重跑的命令與結果
本次親自重跑（均以 -GodotPath 'E:\OneDrive\桌面\Godot_v4.7-stable_win64.exe'）：

命令（tools/run-tests.ps1 -Suite Gut -TestPath …）	結果
res://tests/unit/in_run_hud	exit 0；14 檔／95 tests／0 failures（t17=8、t29=12、projection=12、factory=10，均非零，無靜默跳過）
res://tests/unit/presentation_ui_static_gate	exit 0；4 檔／16 tests／0 failures
res://tests/integration/presentation_ui_in_run_system_menu	exit 0；1 檔／6 tests／0 failures
res://tests/integration/presentation_ui_in_run_drag_canonical	exit 0；1 test／20 assertions／0 failures（與宣稱一致）
每次重跑後 gut.godot.log 的 Parse Error／Failed to load script 均為 0。

讀回但未重跑（明示未驗證項）：(1) 宣稱的 final fresh All（18:27–18:49Z、326 scripts／1354 tests／37956 assertions）——我以 gut.xml 讀回核對（326 testsuites、1354 tests、全零 failures、mtime 02:49 與宣稱吻合），並確認其後無任何程式檔變動；但 All 全套未重跑，且 closure 已誠實記載 runner-execution.json 現存的是後跑的 Spec-only run，故 All 的 exit 0 是「gut.xml＋mtime＋文件宣稱」三方佐證，非本 session 直接觀測。(2) 137／137 formal evidence 與 APPDATA SHA——讀回 evidence-report.json（137 cases／issues=[]／ok=true）與宣稱一致，未重跑 evidence runner，截圖未逐張人工看圖。(3) 「完成後 Godot process 0」無法事後驗證。(4) Spec 4076 cases 未重跑，僅讀回宣稱與 all-suite-output 記錄。
