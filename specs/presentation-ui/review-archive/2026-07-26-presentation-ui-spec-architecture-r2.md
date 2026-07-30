# presentation-ui 規格架構審查 R2

結論：R2 仍不建議核可進 TDD；R1 的 9 項中 7 項封閉，2 項仍未形成可實作的安全契約。

| R1 | 裁決 | Read-back |
|---|---|---|
| PUI-01 | NOT FIXED | capability 已有 identity／consume／revoke 文字，但未定義 repository 級 load/write epoch 或 consume 時鎖內 fresh digest 比對。 |
| PUI-02 | NOT FIXED | opaque digest 定義互相矛盾，且既有 save rotation 無法滿足宣告的 crash matrix。 |
| PUI-03 | FIXED | candidate→transition token→swap→release 順序已明定。 |
| PUI-04 | FIXED | final save 前 transcript 私有、失敗公開 0、重載只摘要已納入。 |
| PUI-05 | FIXED | 四 bus 各自 volume/mute，preflight＋不可失敗 batch commit 已納入。 |
| PUI-06 | FIXED | no-playback typed result 與 accessor/signal deep clone 已納入。 |
| PUI-07 | FIXED | T01/T04 不碰 AppRoot，T05 單一 integration owner。 |
| PUI-08 | FIXED | T00 compile-safe scaffold 與 behavioral-red 後鎖 manifest 已明定。 |
| PUI-09 | FIXED | future schema 保留原 bytes、一般 save lock、expected digest reset 已明定。 |

| 新 finding | 嚴重度 | 檔案:行號 | 失敗情境與建議 |
|---|---|---|---|
| G2-R2-01 | Blocker | `design.md:119-123`; `tasks.md:57-61`; `services/save/save_repository.gd:145-154` | clear-run 沿用現有 save 時，crash 於 main→backup 後、tmp→main 前會留下「main 缺失＋backup old＋archive」，違反只允許 main old/new。新增真正 atomic replace primitive，或明列此中間態及 restart repair 證明與 crash 測試。 |
| G2-R2-02 | 高 | `design.md:115-123`; `HANDOFF.md:58` | opaque token 一處寫「run bytes SHA-256」，其他處要求完整 committed-file digest；profile 改變但 run bytes 相同可能讓舊 token通過。統一綁完整 committed bytes digest＋repository/generation identity。 |
| G2-R2-03 | 高 | `design.md:95-100`; `tasks.md:49-53`; `save_repository.gd:75-82,244-257` | 現有 repository 不發 load/write epoch，也不通知 prepared service；另一 caller fresh load/write 後舊 capability 仍可能可消耗。由 repository 維護世代並在 operation ownership 內 fresh 比對、使所有舊 capability 失效。 |
| G2-R2-04 | 高 | `design.md:188-197` | candidate 入樹並以含 facade 的 context bind 後才驗 transition；錯誤 screen 可在 bind dispatch gameplay command，之後 transition 失敗卻已改 save。staging context 必須 read-only／未啟用，swap 後才以 activation capability 開放 intent。 |
| G2-R2-05 | 高 | `design.md:299-305,357-360` | audio 內部雖原子，但 theme→viewport→localization→audio 跨 adapter 無全域 transaction；後段失敗會留下部分 runtime 設定。新增 SettingsApplicationCoordinator：全 adapter preflight→repository commit→不可失敗 activation，否則走明確 post-commit fallback。 |
| G2-R2-06 | 中 | `design.md:310-324` | controller 宣稱只持 cursor/speed/pause/accumulator，卻需從完整 transcript 補 4096 window；沒有事件 owner/source contract，可能外洩完整陣列或讀錯 lifecycle。定義私有 `BattleTranscriptBuffer`、typed drain-window API、clone 與釋放時機。 |

殘餘風險：archive durability 僅描述 read-back，未界定 power-loss/fsync；transcript 只有事件數上限、
沒有 byte-memory 預算；本次為只讀規格審查，未修改檔案、未執行測試。
