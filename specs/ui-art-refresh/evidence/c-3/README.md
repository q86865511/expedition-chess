# C-3 音訊路由驗收證據

## 結果

C-3 將 content-production 已採用的 5 首音樂與 21 個音效接到正式 production
presentation route。`ProductionAudioDirector` 由每個 `ProductionScreen` 擁有：route
建立時播放對應音樂；焦點、按鈕結果與 run intent 在 presentation shell 接線；戰鬥
音效則消費 `RunCombatScreen` 已取得的同一批 cloned `BattleEvent`。這個 ownership 不需
新增 app singleton、session API 或 service 接線，畫面釋放時播放器也一併釋放。

音量與 mute 沿用既有 `Music`／`SFX`／`UI` bus 設定。音訊層不讀寫 canonical state，
不使用 `RngService`、`gameplay_stream` 或本地亂數。戰鬥 event 全部依輸入順序掃描；每個
window 的一般音效最多播放 12 個以避免聲音堆疊，死亡、Boss 警示與勝敗 cue 仍保留。
這個 deterministic 顯示取樣不過濾、不重排，也不改變 BattlePlayback 的事件消費順序。

結構化證據見 [audio-routing-report.json](./audio-routing-report.json)：runner 實際載入並
播放五個代表 route 與全部 21 個 SFX，結果 `ok=true`、17 routes、5 music、21 SFX、
26 assets、零 issue；同檔含每個 `.tres` 與 `.ogg` 的 SHA-256、bus、loop 旗標與戰鬥
sequence probe。

## 5 軌音樂路由

| cue | production routes | bus | OGG SHA-256 |
|---|---|---|---|
| `audio.menu` | `MENU_MAIN`、`SETTINGS`、`APP_ROUTE_FALLBACK` | Music | `9c2a9d7ecc36d54f2d7ee415d4304502508498dfd20c2e0407791d6bb324953d` |
| `audio.camp` | `CAMP_WORLD`、五個 facility／collection routes | Music | `a82dd02c1acebc0547aed2943abccfd0f7d1dbfb1c1cfc5e4788063a06403275` |
| `audio.expedition` | `RUN_CONTAINER`、`RUN_MAP`、`RUN_PREPARE`、`RUN_REWARD`、`RUN_ROUTE_FALLBACK` | Music | `8819d5a378351160944efebb6c98bdeadfa19de442ea6d724f964d318054adbf` |
| `audio.combat` | `RUN_COMBAT` | Music | `ad37e42de519500738c7a35984219655df086fc90d4d0cb9952cf0944e65a42e` |
| `audio.results` | `RESULTS`、`RESULTS_FALLBACK` | Music | `f1157e62def6455bf1e26179b4385513984d2919f10aa96e258805e0d930ea7e` |

五個檔案皆為 48 kHz stereo OGG Vorbis、24 秒、loop=true；規格與原始
content-production provenance 保持不變，C-3 沒有重製或修改音檔。

## 21 個 SFX 對映

| cue | 具名觸發 | bus | OGG SHA-256 |
|---|---|---|---|
| `audio.ui_confirm` | 一般 action／intent 成功、開啟系統選單 | UI | `81220e0bf3d228679646e77463a8c745c3ce5d6dfe03a30b699b87fc77ab7cc3` |
| `audio.ui_cancel` | `*.cancel`、關閉 popup／modal／系統選單 | UI | `e8b6e559bc4b801c956b29d8ce316a6233af4436e935f1720425cab96bca51b6` |
| `audio.ui_focus` | `Viewport.gui_focus_changed`，且焦點屬於當前 screen | UI | `59079ea05e1be6131f69f64da8e2d01ed23ca2e782118d6570ab1b360c75f138` |
| `audio.ui_error` | action／intent 失敗、`summon_failure` | UI | `9652269ce20c64d72c419d91308705522f1e6973f2b01be8d42ce3c1707fbf27` |
| `audio.shop_buy` | `BUY_UNIT`、`BUY_XP` | SFX | `16ba6b47261a67e3c78b19c5059ae2e379e7e5ac5d4d4bb498e6ff034bf9ccc1` |
| `audio.shop_sell` | `SELL_UNIT` | SFX | `30343ea23d74cf9b394903a8601bf29a746bcfd7c9a7c53b3dab4e53f9f5ccd0` |
| `audio.shop_refresh` | `REFRESH_SHOP` | SFX | `e3728a81a1e1fff0d07caf7aa305ab0bfb612462ff272b830857feddb3c2ec73` |
| `audio.forge` | `FORGE_EQUIPMENT` | SFX | `166de9f28a51701d2bb49715cf4efca0ecdc4bca445d6af4a851889fa8f8f32b` |
| `audio.equip` | `EQUIP_ITEM`、兩種 dismantle | SFX | `0a0d1d90b7eb6f9a4fd0c1d4a44920350b06dfffc6d28068939d540ac8f5c986` |
| `audio.reward_select` | 選擇／解決 reward、overflow、relic 取代或放棄 | SFX | `8113e003c502dbe06f59dc030955964170de3409b522a176d5f2874023f4c74e` |
| `audio.event_select` | 進節點、非戰鬥解決、node choice commit／ack、離開 node service | SFX | `a89178394ac9f4d09f98f68f349c2f52628fae5c3fd2abf287032ff8a59c813d` |
| `audio.combat_cast` | `cast`、`basic.magic_projectile` attack | SFX | `79db7f470aa843df290ed3909e218fe186e931c881697de6cd86167da63baaf7` |
| `audio.combat_melee_hit` | physical／true `damage` | SFX | `75c29bb33f2c2c4d33a8e3f464c8bbfb9e1fe2691f71fa10026496a5108f33ff` |
| `audio.combat_defeat` | `battle_finished.player_loss` | SFX | `cd4cf7222fc6c868fef7829a48b040a7cb1ab3125b384a7f708879255d320df6` |
| `audio.combat_shield` | `shield` | SFX | `be98ea47059d8a90e688892e3c9b27513c99e34df86634089aeb56b5bea07980` |
| `audio.combat_heal` | `heal` | SFX | `930956b23fb47c6a078d7e806bcbde02216268a50dae0f329e81441174cf86dc` |
| `audio.combat_death` | `death` | SFX | `ef05f6dca372fcf2be802a2b037ebe12bd025311d7e0f4da40a41bc003c9d91b` |
| `audio.combat_ranged_attack` | `basic.ranged` attack | SFX | `4126361a1d932dab0f2c710e1e37132815bc4cf8510c699f774ae921cf873cfb` |
| `audio.combat_magic_hit` | magical `damage` | SFX | `423aacb4de68f97417c45ab15a7165443c2959224373e127964b5eb77903f7ab` |
| `audio.combat_boss_warning` | `boss_phase` | SFX | `aeb6e6e3c13ac275d1b85c93e6e361809f120b5c69cdf2aed3aa3b1d3d10adf2` |
| `audio.combat_victory` | `battle_finished.player_win` | SFX | `c47dc2a93eb35118718eaeac1d287f9a22993a6da64696be7cdfc46d8328c29d` |

## 驗證

- C-3 focused GUT：6／6 tests、288 assertions，exit 0。
- evidence runner：`ok=true`；17 route mappings、5 music cues、21 SFX mappings、
  26 asset/resource pairs，runtime playback probe 全數成功。
- `tools/run-tests.ps1 -Suite All`：exit 0；GUT 356 scripts、1499／1499 tests、
  39746 assertions、0 failures／errors／orphans；Smoke 10 cases、Combat step exit 0、
  S2 acceptance 18／18、Spec 4100 cases／0 failures。
- `git diff --check`：exit 0；新檔 trailing whitespace 0、C-3 新增
  `theme_override_*` 0、presentation RNG findings 0、禁止邊界差異 0。
- 詳細輸出與 SHA 見 [all-output-summary.json](./all-output-summary.json)、
  [static-checks.json](./static-checks.json)、[all-runner-execution.json](./all-runner-execution.json)
  與 [focused-runner-execution.json](./focused-runner-execution.json)。
- 使用者既有 `project.godot` 編輯器改寫保留；C-3 不修改該檔。
