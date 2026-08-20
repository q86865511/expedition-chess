# B-out-1 視覺核可證據

本批只涵蓋 `CAMP_WORLD` 與 `MENU_MAIN`，不包含 B-out-2 的五設施／圖鑑內容。

## 截圖矩陣

- 畫面：`CAMP_WORLD`、`MENU_MAIN`
- 視窗：1280×720、1920×1080、2560×1440
- UI scale：100%、125%、150%
- 合計：18 張 PNG
- 機器報告：`evidence-report.json`（`ok=true`、`issues=[]`）

18 張已逐張人工檢視；文字、控制項、設施標記、緊湊卡片與安全區沒有截切、重疊或超界。

- `MENU_MAIN` 已移除右側大面積底板，三個操作按鈕直接疊在 key art 的暗部；按鈕自身底色、邊框、focus texture 與 hover 邊框加粗仍保留。125%／150% 維持固定右界向左擴張，實際 hit rect 隨 accessibility scale 放大。
- `CAMP_WORLD` 環境圖佔滿上下欄間主區域；左側重複設施列已移除，五個場景標記皆為可點擊、可 focus 的正式按鈕。右側遠征資訊為半寬緊湊卡，頂欄與底欄只在 CAMP route 使用縮薄尺寸。
- 唯讀 `presentation/accessibility/keyboard_focus_graph.gd` 原已包含五個 `camp.*` 設施 action id，無缺項且不需修改。

## 資產與來源

- 營地環境：`assets/production/environment/camp.png`
- 主選單 key art：`assets/production/key_art/menu_main.png`
- ImageGen 原始輸出：`assets/production/key_art_attempts/menu_main/attempt-001/raw.png`
- 生成模式、完整 prompt 與 SHA-256：`assets/production/provenance/menu_main_key_art.json`
- production inventory 僅收錄採用版本；本批沒有未採用變體。

## 自動驗證

- `tests/unit/ui_art_refresh/`：exit 0
- `tests/integration/presentation_ui_r14_route_security/test_camp_five_facility_controls.gd`：exit 0
- `tests/integration/presentation_ui_r15_behavior/test_real_viewport_scale_and_semantics.gd`：exit 0
- `tests/integration/presentation_ui_b1r3/test_layout_geometry_audit.gd`：exit 0
- `tests/runners/presentation_b_out_1_evidence_runner.gd`：exit 0，18/18，`issues=[]`
- `tools/run-tests.ps1 -Suite All`：exit 0；GUT 1451/1451、38993 assertions，其他正式 suite 皆 exit 0（2026-08-14 13:40–13:56 Asia/Taipei）

核可前嚴格停在 B-out-1，不開始 B-out-2。
