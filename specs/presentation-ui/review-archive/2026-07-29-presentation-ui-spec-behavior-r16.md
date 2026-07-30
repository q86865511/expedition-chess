# R16 Behavior／UX／Accessibility／Evidence Implementation Review

Date: 2026-07-29
Verdict: `NOT APPROVED`
Unresolved: `4 High / 2 Medium`
Mode: fresh read-only reviewer；未修改檔案、未執行 Godot、未做 Git。

## G2-R16-B01 — High

full-rect accessibility overlay 位於 COMBAT composition 上方且攔截 input；
實際 baseline/4:3/125/150/protanopia PNG 都看不到 UnitSelector 或
InspectionPanel，只看到 probe 與通用 actions。

- Fix: 正式 typed controls 可見且可 hit；probe 不遮蔽/不攔截。
- Evidence: 真 AppRoot COMBAT mouse/keyboard select＋inspect、六欄 read-back、
  GUI hit/focus/z-order，五種 runtime captures清楚顯示 typed controls。

## G2-R16-B02 — High

正式 RUN_PREPARE wiring 固定建立 `BoardValidationReport.new(0, [])`，虛構
valid/capacity 0；AC-004/005 test直接注入 fabricated report，未驗 production。

- Fix: committed board/bench/capacity 的 authoritative clone-only report進 live context。
- Evidence: 真 AppRoot 全 illegal reasons、12-unit、removal-source over-cap、
  Start disabled/enable與零錯誤 dispatch。

## G2-R16-B03 — High

PREPARE 缺 board/bench/shop/build editor；COLLECTION 缺三類 filter/search/
compare；RESULTS/FALLBACK 未呈現 sealed receipt/reward/profile settlement。

- Fix: 三者建立 clone-only typed production composition與 lease-bound actions。
- Evidence: 真 Godot input走 prepare recovery、collection query/compare、
  terminal results read-back/reload/stale lease。

## G2-R16-B04 — High

與 A02 重疊：world SubViewport 是空殼，pointer evidence是 hard-coded算術
round-trip，不是真 target hit-test或 framebuffer。

## G2-R16-B05 — Medium

Settings focus cycle只含 Apply/Back，排除 OptionButton、CheckButton、HSlider；
鍵盤無法進入 editors。

- Fix/Evidence: production focus graph納入所有可見 enabled editor；100/125/150%
  真鍵盤 traversal。

## G2-R16-B06 — Medium

第四色覺／非色彩 PASS 只驗通用按鈕與 probe；未驗 authoritative ally/enemy、
trait、rarity、damage type、danger decision data。

- Fix/Evidence: semantic cues直接綁 typed data，四色覺 runtime report逐類列
  typed ID、visible cue與 rect，PNG顯示真單位/reward/damage資料。

## Confirmed closed

- CAMP/MAP/REWARD selectors、recovery modal trap/restore、zero-size fail-closed。
- current automation／manifest／runtime數字一致；歷史數字已標 superseded。
- 五張指定 PNG 與 runtime JSON SHA 全相符。
