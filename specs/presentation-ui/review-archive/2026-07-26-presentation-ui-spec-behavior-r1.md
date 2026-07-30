# presentation-ui 規格行為審查 R1

結論：**未達 production UI 核可門檻**。R1～R14 與 T01～T15 的名義雙向覆蓋完整，
但有 8 個可使「tasks 全綠仍交付錯誤行為」的缺口，需使用者逐項裁決。

| 編號 | 嚴重度 | 檔案:行號 | 問題＋失敗情境 | 建議 |
|---|---|---|---|---|
| PUI-01 | 高 | `design.md:130-136`；`HANDOFF.md:20` | `RunPresentationIntent.Kind` 缺出售、鍛造、換裝／拆卸、遺物替換等正式操作；玩家能進備戰畫面但無法經 facade 完成必要構築，T04/T09 仍可能因只測已列 intent 而通過。 | 以現有 `RunCommandFactory` 玩家操作全集建立 intent→command 對照，逐項補 success/failure TDD；若刻意延後，明確改 R5/T09 與 slice owner。 |
| PUI-02 | 高 | `requirements.md:167-175`；`design.md:287-290,364` | R12 要求「任何」scene binding／presentation failure 都讓 committed save 不變；若選獎 command 已成功提交、下一場景 bind 才失敗，回滾 canonical 會破壞 commit-before-present／exactly-once，不回滾又違反 R12。 | 裁決並區分 pre-commit failure 與 post-commit presentation failure；後者保留新 committed state、顯示安全 fallback，另測 retry/reload。 |
| PUI-03 | 高 | `requirements.md:5-6,199-200`；`tasks.md:101-107`；`08-testing-and-acceptance.md:98-99,143` | T15 只要求 AC ledger，未把 owning AC 對到 production UI 測試；舊 domain suite 全綠時，UI 即使未列出全部非法部署原因、未顯示 12 人上限，或複製 TUNE 常數，仍可能把 AC-004/005/049 標 PASS。 | 增加「19 owning AC→task→新鮮 production evidence」矩陣，至少為 AC-004/005/049 補具名 UI／static tests；沒有新證據不得沿用 G1 PASS。 |
| PUI-04 | 高 | `requirements.md:131-137`；`design.md:224-238` | R9/T03 要四 bus 各自 mute，但 persisted model 只有單一 `muted`；只靜音 Music 後重啟時，只能變成全域靜音或遺失 Music mute。 | 裁決為四個 typed mute 欄位，或把需求明確降為單一 global mute；同步 repository、audio test 與 migration/default。 |
| PUI-05 | 中 | `requirements.md:49-50,62-64`；`HANDOFF.md:58`；`08-testing-and-acceptance.md:164` | requirements/AC-070 允許 incompatible run 進 recovery 並封存後清除；HANDOFF 明定 `INCOMPATIBLE_PRESERVED` 必須 boot failure。兩組驗收對同 fixture 期待相反結果。 | 使用者裁決單一行為；若採 AC-070 的 opaque-token recovery，先同步 HANDOFF 再實作。 |
| PUI-06 | 中 | `requirements.md:159-163`；`07-pixel-presentation-and-ui.md:56`；`tasks.md:79-83` | R11/T12 列羈絆、稀有度、傷害與危險狀態，漏掉權威基線的「敵我關係」非色彩提示；紅綠敵軍只靠色相仍可通過現有清單。 | 將敵我關係加入 R11、theme token、四色覺 screenshot 與 keyboard/visual 驗收。 |
| PUI-07 | 中 | `requirements.md:102`；`design.md:330,346`；`tasks.md:66-70` | 設計已識別 SubViewport input transform 風險，但 R6/T10 只有畫面／safe-rect 驗收；4:3 letterbox 截圖可正確，滑鼠卻點到錯格或錯營地熱區。 | 加入 720p/1080p/1440p、非 16:9、三 UI scale 的 pointer→world/UI 座標映射整合測試。 |
| PUI-08 | 中 | `requirements.md:122-126`；`design.md:224-238,250-252` | `DamageNumberDensity` 成員／default 未定義，音量只寫「clamp/validate」；例如輸入 1.2 時 clamp 與拒絕都符合文字，EARS 無法產生唯一預期。 | 明列所有 enum 成員、安全 defaults、音量 `[0,1]` 邊界與非有限值政策，決定 out-of-range 是 clamp 或 typed reject。 |

風格偏好（非必改）：可把 R1～R14 的 EARS 主句統一成「當／若／在…期間，系統應…」，
但目前措辭本身不構成失敗情境。

未發現具體問題：R1、R2、R4、R7、R10、R13 的核心行為，以及四切片順序、
640×360＋1280×720、boot 固定 MENU、倍速只動事件消費、zh_TW/en key parity、
視覺樣板核可前禁止量產，均未偏離已核可意圖。
