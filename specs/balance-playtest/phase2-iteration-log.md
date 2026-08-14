# Phase 2 平衡迭代日誌

## R1（2026-08-14 發動）

- 基線：R0 後首輪（driver 已含 reroll/sell 觸發並凍結；candidate 待 screening 產生）。
  R0 前基線訊號：tempo 65.7%／economy 23.5%／synergy 84.1%；act2 淘汰 0。
- 改值：
  1. `slice_default.tres` 新增覆寫 `interest_per_step = 2`（原預設 1）——假設：economy
     23.5% 過弱主因收入不足；利息翻倍最直接受益的是囤金策略，對 tempo/synergy 影響小。
  2. `combat_default.tres` `act2_enemy_stat_bps` 13000→14000——假設：act2 淘汰 0 表示
     幕二縮放不足，上調一級製造過濾（act3 已 16000，維持遞增）。
- 一輪兩值的理由：兩者作用面正交（經濟收入 vs 戰鬥難度），歸因不互相污染。
- 預期：economy 勝率上移、act2 淘汰 >0；convergence WARN 欄位對照。
- 結果：（screening 後回填）

- R1 連鎖備忘：act2 golden 分佈於 test_act_scaling/test_encounter_compiler（已同步 14000）；
  domain battle_rules_snapshot.gd:34 預設仍 13000（實際縮放走 pinned config，不影響行為，
  改動涉 canonical 位元組——留待收斂後與 golden 動態化一併裁決）。
