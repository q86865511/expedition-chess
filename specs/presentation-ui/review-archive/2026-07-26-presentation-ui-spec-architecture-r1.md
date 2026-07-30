# presentation-ui 規格架構審查 R1

結論：**不建議核可進入實作**；有 2 個 blocker、5 個高風險缺口，主要集中於 capability、
recovery 原子性與 playback 提交邊界。

| 編號 | 嚴重度 | 檔案:行號 | 問題＋失敗情境 | 建議 |
|---|---|---|---|---|
| PUI-01 | Blocker | `design.md:81-90`、`tasks.md:37-38` | boot 只允許在 BOOT 消耗 load capability，卻又要求 RUN→MENU 後 fresh load/compose；此時若保留資格會形成 stale Continue，若清除則 MENU 無 API 可重新註冊 capability。 | 定義 repository/compose 綁定、單次使用的 `PreparedRunCapability`，由 MENU→RUN 原子消耗；RETURN_TO_MENU 必須失效舊 capability。 |
| PUI-02 | Blocker | `design.md:106-110`、`save_repository.gd:207-212`、`save_storage_port.gd:31-35`、`file_save_storage.gd:99-100` | incompatible load 不回 committed digest/raw bytes；現有 quarantine 又是把 main 移到固定檔名。若沿用它做 archive，後續 clear-save fault 會讓 main 消失，甚至退回較舊 backup，違反 byte-preserving fail-closed。 | recovery 完全收進 repository mutex；fresh-read 後以完整 committed-bytes digest 比對，copy→unique tmp archive→read-back→promote，成功後才 clear；不得用現有 move-quarantine。 |
| PUI-03 | 高 | `design.md:83-84,364`、`scene_router_service.gd:19-23` | RUN→MENU 若先 transition／釋放 session，menu instantiate/bind 失敗時，舊 RUN 畫面可能仍在，但 App 已是 MENU 且 facade 為 null；若先換場，現 router 又先刪舊畫面。 | 明訂 prepare/instantiate/bind candidate → transition → atomic swap → release old session；任一步失敗保留 RUN state、scene、session。 |
| PUI-04 | 高 | `design.md:256-268`、`tasks.md:74-77`、`combat_coordinator.gd:90,122-152`、`battle_result_pending_resolution_state.gd:4-10` | 現 coordinator 在最終 save 前已 publish 非終局事件；save fault 時玩家已看到未提交戰鬥。設計又稱重入可重建 stream，但 committed pending state 沒有 setup/events，無法重播。 | 全 transcript 先私有 buffer，RecordBattleResult 提交成功後一次公開；reload 僅顯示 committed summary。加入 final-save fault 時「公開事件=0」紅燈。 |
| PUI-05 | 高 | `requirements.md:131-137`、`design.md:224-239,250-252` | R9 要求四 bus 各自 volume＋mute，但 snapshot 只有單一 `muted`；Music-only mute 無法 round-trip。若逐 bus 套用而 UI bus 缺失，前三 bus 還可能已部分變更。 | 為四 bus 定義穩定 wire key 的 mute 欄位；adapter 先 preflight 全 bus，再一次套用或零變更。 |
| PUI-06 | 高 | `design.md:71-76,124-127,361` | `playback() -> BattlePlaybackController` 在非戰鬥期有合法「不存在」狀態，只能回 null／舊 controller，直接違反 public no-silent-null；snapshot accessor 亦未保證每次 clone。 | 改成 typed result；所有 accessor 與 signal payload 每次 deep clone，測兩 consumer 互不 alias。 |
| PUI-07 | 高 | `tasks.md:10-14,27-31,111`、`app_root.gd:55,62,474,535` | wave1 宣稱 T01/T04 互不重疊，但兩者都必須移除 AppRoot 的 `BuildLab*`／`RunLabSession` production 型別；平行實作必衝 `app_root.gd`，或其中一項無法在該 wave 達成驗收。 | 明列 file ownership；先 T01，再 T04，或把兩者 AppRoot integration 明確移至單一 T05 owner。 |
| PUI-08 | 中 | `tasks.md:5,16-19,27-31,118-119` | tests-first 又禁止先建 production contract；紅燈若直接引用尚不存在的 `SettingsSnapshot`/facade class，GUT 會 parser abort，無法得到可歸因行為紅燈，鎖 manifest 後也不能補 typed tests。 | 允許 compile-safe contract scaffold 的明確 TDD 階段，再鎖 behavioral-red manifest；parser failure 不算有效紅證據。 |
| PUI-09 | 中 | `design.md:226,241-246,299-305` | settings 只有 schema 1，未定義 future-version 分流；舊版讀到 schema 2 若當 corrupt quarantine，升回新版後設定已被預設值覆寫。 | 加 `UNSUPPORTED_FUTURE_VERSION`，保留原 bytes、不 quarantine、不覆寫；corrupt 與 incompatible 分流測試。 |

殘餘風險：

- archive 的唯一命名、重複確認冪等性、當機恢復矩陣仍未規格化。
- playback buffer 上限雖有 event budget，尚未定義記憶體估算與超限 typed failure。
- settings schema 應固定 enum/string wire 值，不能直接持久化 Godot enum ordinal。
- 本次為只讀 SDD 審查，未執行測試；程式現況證據已逐檔 read-back。
