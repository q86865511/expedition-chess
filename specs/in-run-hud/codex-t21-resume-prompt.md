# Codex 續作 prompt — T21 blocker 已解，自 T21 續跑批次 3

> 用法：在既有 Codex session（`codex/g2-ui-art-refresh-b`）貼入
> 「--- PROMPT 開始 ---」到「--- PROMPT 結束 ---」之間的內容。

--- PROMPT 開始 ---

你回報的 T21 存檔 blocker 已由 Claude 修復並提交為 **`e15b783`**，baseline 乾淨。
繼續批次 3：**T21 → T16 → T25 → T14 → T17 殘缺 → T19 殘缺**（批次 3 prompt 的
邊界與驗收要求全部沿用；S0 與 T20 你已完成，不重做）。

## blocker 修復摘要（你需要知道的行為變更）

- 根因確認與你的分析一致：`save_json_codec` 的 item decode 硬給
  `expected_category="item"`，migration transcoder 嚴格相等，正式裝備進 canonical
  後 read-back 判 incompatible。
- 修法：`ContentIdMigrationRequest` 改為**類別聯集**（`accepted_categories`，
  空陣列＝不檢查），item 欄位接受
  `[item_component, equipment, consumable, item]`；unit／relic 維持單值。
  encode、save schema version、alias／tombstone／receipt 檢查語意全部不變。
- 閘門仍有效：unit 類別 id 塞進 item 欄位仍會被拒（有負向測試釘住）。
- 契約測試：`tests/integration/save_repository/test_save_repository_item_categories.gd`
  （production 類別 encode→decode→SaveRepository save→load read-back 全程）。
  **此檔加入你不得修改的 Claude 契約測試清單。**
- 驗證：fresh All exit 0（337 scripts、1397/1397、38370 asserts）＋
  10k ExpeditionSoak passed（10000 cases、0 failures）＋ Spec 0 failures。

## T21 補充說明

- 你先前確認過的流程（買棋 → 上場（W）→ 配裝 → 開始戰鬥）現在配裝後的存檔
  round-trip 應直接通過；若 E2E 中再遇到 `SAVE_TMP_READBACK_INVALID` 或任何
  incompatible 標記，**停下來附完整診斷回報**（那會是新問題，不是已知殘留）。
- 其餘要求不變：只用鍵盤事件、不得直呼 screen 方法、focus graph 已補滿不需再改。

## 邊界提醒（沿用批次 3，追加一條）

不得修改：`domain/**`、`services/**`、`app/**`、`presentation/viewmodels/**`、
`presentation/run/run_presentation_session.gd`、Claude 契約測試
（批次 3 清單＋新增的 `test_save_repository_item_categories.gd`）。

## 批次尾（不變）

`-Suite All` exit 0（附 GUT 統計行）、`git diff --check`、勾選 `tasks.md` 附交付行、
回寫台帳 `irh-requirements-manifest.md`（011／013／014 應可轉 PASS，
008／009／010／015 依實況）、證據落 `specs/in-run-hud/evidence/p8-batch2/`。

--- PROMPT 結束 ---
