# R16 Findings Closure（非新一輪 review）

Date: 2026-07-30  
Status: `ALL R16 FINDINGS ADOPTED AND VERIFIED`  
Review transition: 使用者明示「R16 審查結束直接進下一步，不再次雙審」；因此沒有
R17，也不把本文件冒充 fresh reviewer 的 zero-finding report。

R16 原始 architecture／behavior 報告維持 `NOT APPROVED` 歷史原文。本文件只記錄使用者
全部採納後的 production 修正、behavioral red→green 與 final gate read-back。

| Finding | 修正 | Fresh evidence | Closure |
|---|---|---|---|
| G2-R16-A01 | 移除公開 split `prepare_retry/retry(capability)`；只保留 root-owned `retry_installed()` | R16 architecture：direct AppRoot Camp/Menu 在 ownership entry、CAS consume、candidate bind 共六次皆回 `RESULTS_ACTION_IN_PROGRESS`；R13/R15 terminal regression 綠 | CLOSED |
| G2-R16-A02 / B04 | `WorldViewport` 掛入真 `ProductionWorld`、tile/hotspot targets；mapper 對齊 fixed Canvas transform | R16 viewport 真 `SubViewport.push_input()` 命中 `world.board_tile`；100/150% mapper 不重複縮放 | CLOSED |
| G2-R16-A03 | committed combat projection 建立 player-first 雙方 serial、target、equipment、traits、statuses、side；port 每次 fresh clone | R16 architecture 真 session＋lease port 驗六欄、跨陣營 target、clone isolation、stale lease | CLOSED |
| G2-R16-B01 | COMBAT composition 提升 z-order；accessibility runtime 全樹 mouse-ignore，probe background 不再遮蔽 | R16 viewport 驗 typed composition 位於 probe 上方、background hidden、pointer passthrough | CLOSED |
| G2-R16-B02 | `RunCommandFactory.board_validation_report()` 與正式 commit 共用 population sources；snapshot clone-only 帶入 report；缺 report fail closed | R16 formal、R14 functional controls／route security／same-route refresh、完整 Gut 綠 | CLOSED |
| G2-R16-B03 | PREPARE 補完整 selectors/actions；COLLECTION 改三分類並接 pinned recipe/glossary projection；RESULTS/FALLBACK 綁 sealed settlement controls | R16 formal 5/5；live AppRoot COLLECTION recipe/glossary 非空；nonterminal composition regression 綠 | CLOSED |
| G2-R16-B05 | Settings focus cycle納入 15 個 OptionButton／CheckButton／HSlider editors | R16 formal 驗 15/15 editor IDs；accessibility joint 與完整 Gut 綠 | CLOSED |
| G2-R16-B06 | ally/enemy/trait/rarity/danger cues 綁 typed IDs＋stable patterns；drained damage event 產生 localized damage cue；第四色覺只換 palette、不移除文字／圖樣 | R16 viewport 驗 `damage.magic`、`magic-spark`、數值、tritanopia palette 與 pattern/text preservation；static gate zero issues | CLOSED |

## Final verification

- R16 targeted：
  - architecture 4 tests，green；
  - formal 5 tests，green；
  - viewport 4 tests，green。
- Final Gut：243 scripts、945/945 tests、16,295 assertions、
  0 failures／errors／orphans。
- Final Spec：3,696 cases、0 failures。
- Smoke、Content、Canonical、Combat、Expedition、All：全部 exit 0。
- ExpeditionSoak：10,000 seeds、10,000 pool checks、64 deterministic replays、
  40,000 build operations、0 failures。
- Production static gate：`ok=true`、`issues=[]`。
- Active test manifests：42 files、155/155 references match、138 unique paths、
  0 missing／mismatch／format issue／hash conflict。

## Gate decision

依使用者明示 override，R16 findings closure 後直接進 T15 文件／Git handoff，不啟動
R17 或再次雙審。這不等於修改 R16 reviewer 的歷史 verdict；最終完成依據是使用者裁決、
本 closure decision table 與 fresh production evidence。Git 尚未授權；不得 stage、
commit、push、PR 或 merge，`content-production` 仍須等本片合併後才可開始。
