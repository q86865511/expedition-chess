# G2 `presentation-ui` R15 Behavior／UX／Accessibility／Localization／Evidence Review

> Verdict: `NOT APPROVED — 2 High / 4 Medium unresolved findings`

## Findings

### G2-R15-B01

- Severity: **High**
- Exact file:line:
  - `scenes/production/camp_world.tscn:6-14`
  - `scenes/production/run_map.tscn:6-14`
  - `scenes/production/run_prepare.tscn:6-14`
  - `scenes/production/run_reward.tscn:6-14`
  - `scenes/production/results.tscn:5-10`
  - `presentation/screens/production_screen.gd:132-149,265-322,381-441`
  - `presentation/screens/camp_world_screen.gd:56-73`
  - `tests/integration/presentation_ui_r14_functional_controls/test_menu_camp_and_settings_controls.gd:31-48`
  - `tests/integration/presentation_ui_r14_functional_controls/test_run_intent_controls.gd:10-20,51-113`
- Failure scenario: production 場景除了空白 `Composition`／標題與通用 action button 外，沒有玩家可操作的 commander/challenge selector、地圖節點、棋盤／bench／shop／build editor、reward offer、Results receipt/reward 明細或 Collection filter/search/compare controls。玩家在 CAMP 按「開始」只會得到 selection-required；現有測試必須直接呼叫 `composition.select_expedition()`。Map／Reward 測試則建立 spy session，按鈕只會暗中選第一項，未呈現可選內容。Combat 的「檢視單位」實際呼叫 `try_playback()`，並未讓玩家選 unit 或呈現 typed inspection。
- Violated requirement:
  - `requirements.md:78-80,99-105,152-167`
  - `tasks.md:149-168,174-210`
  - R14 `G2-R14-A03/B01` 的「真 controls／conditional states」修正宣稱
- Proposed fix: 為每個正式 route 建立以 clone-only model 驅動的實際 controls 與 conditional visibility/enabled state；CAMP 必須可選 commander/challenge；Map、Prepare/shop/build、Combat inspection、Reward/overflow、Collection、Results 必須顯示資料並可用滑鼠／鍵盤完成規格列出的閉環。不要再以「select first」或直接呼叫 composition API 代替玩家互動。
- Required regression evidence: 從真 `ApplicationRoot→SceneRouter` boot，以 Godot input event 驅動具名 Control，走完 MENU→CAMP selection→RUN_MAP→PREPARE/shop/build→COMBAT inspection/playback→REWARD/overflow→RESULTS，並驗 conditional hidden/disabled 狀態、顯示的 typed data、exact intent、stale control rejection 與 pre/post-commit error UI。

### G2-R15-B02

- Severity: **High**
- Exact file:line:
  - `app/app_root.gd:272-283`
  - `services/settings/adapters/presentation_settings_runtime_consumer.gd:40-56`
  - `scenes/production/run_combat.tscn:7-27,29-180`
  - `tests/integration/presentation_ui_r14_accessibility_joint/r14_accessibility_joint_test_support.gd:455-468,503-520`
  - `tests/runners/presentation_r14_production_runtime_runner.gd:8-18,127-136,240-269`
- Failure scenario: production tree 沒有 R6 要求的 640×360 `SubViewport`／獨立 1280×720 UI `CanvasLayer`；AppRoot 只建立 policy/mapper 物件。runtime report 的 pointer/world/camp 結果是測試中重新建立 mapper 做算術 round-trip，不是對實際 production target 點擊。UI scale activation只在 host 寫 metadata；未套用到通用 production action buttons，實際 150% PNG 中內容文字放大但右側 action buttons 仍維持小尺寸。四色覺 `non_color_cues` 只檢查按鈕有文字/meta，未驗敵我、羈絆、稀有度等決策資料；目前 production PNG 只顯示 accessibility probe。
- Violated requirement:
  - `requirements.md:208-222,321-341`
  - `tasks.md:214-218,237-260`
  - R14 `G2-R14-B06`
- Proposed fix: 把 `WorldViewportHost`／`UiScaleRoot` 接入真 production scene tree，對真世界、camp hotspot 與 UI controls 套用 layout/scale；讓 color semantics 綁真 ally/enemy/trait/rarity/damage/danger presentation data，而不是 probe-only labels或 metadata。
- Required regression evidence: 對至少 MENU、CAMP、RUN_MAP、RUN_PREPARE、RUN_COMBAT、RUN_REWARD、RESULTS 的真 production route，分層或完整矩陣覆蓋 720/1080/1440、4:3、16:10、100/125/150%、default/protanopia/deuteranopia/tritanopia；以真 input hit-test 驗 world tile/camp hotspot/UI control，並記錄實際 control font/rect scale、裁切、敵我/trait/rarity/damage/danger 非色彩 cue。PNG 必須顯示真畫面資料，不只 probe。

### G2-R15-B03

- Severity: **Medium**
- Exact file:line:
  - `presentation/accessibility/keyboard_focus_graph.gd:5-64,67-82`
  - `presentation/screens/production_screen.gd:68-77,348-371`
  - `tests/integration/presentation_ui_r14_self_audit/test_production_ui_contracts.gd:78-87`
- Failure scenario: `KeyboardFocusGraph` 沒有任何 production consumer；測試只比較靜態陣列。實際 route 依 scene-tree 預設 tab 順序運作。Recovery dialog 開啟後只把焦點移到第一個 dialog button，沒有停用背景 Actions、focus trap、cancel 後焦點還原；鍵盤仍可巡覽或啟動背景 Start/Settings/Exit。graph 也把 recovery dialog action 與背景 MENU action放在同一列表，未實作 design 所述 active/blocked 過濾。
- Violated requirement:
  - `requirements.md:326-331`
  - `design.md:717-721`
- Proposed fix: 在 live screen activation 建立實際 focus neighbor graph；以當前可見/enabled/conditional controls產生順序。Modal confirmation 開啟時停用背景 focus/input、限制焦點於 dialog，關閉後還原 trigger control。
- Required regression evidence: 真 production keyboard event traversal，在 100/125/150% 覆蓋所有正式 routes；另測 no-run、continue、decoded/opaque recovery 狀態及 dialog open/cancel/confirm，逐步斷言實際 focus owner、背景不可觸發、關閉後焦點還原。

### G2-R15-B04

- Severity: **Medium**
- Exact file:line:
  - `presentation/accessibility/accessibility_runtime_renderer.gd:470-477`
  - `tests/integration/presentation_ui_r14_self_audit/test_accessibility_root_size_contract.gd:4-28`
  - `requirements.md:218-220`
- Failure scenario: 外層 root 有尺寸但 `UiProbe.size == Vector2.ZERO` 時，`_clipped_required_controls()` 靜默改用 1280×720；因此 clipping report 可假綠。現有 zero-size test 只讓整個 accessibility host 為零，會在較早的 `apply_settings()` fail-closed，未命中這個 helper 分支。
- Violated requirement: R6 明定 renderer 收到 zero-size root 必須回 `ACCESSIBILITY_ROOT_SIZE_INVALID`，不得假設 1280×720。
- Proposed fix: 移除 fallback；`UiProbe` 缺失或零尺寸時讓整份 runtime report typed failure，或回具名 invalid-root issue。
- Required regression evidence: 掛載有效外層 root、刻意讓 `UiProbe` 零尺寸，驗 report 非 `ok`、精確 error、不得回空 clipping list；resize 恢復有效尺寸後再驗真 bounds。

### G2-R15-B05

- Severity: **Medium**
- Exact file:line:
  - `presentation/screens/scene_router_terminal_presentation_handoff_adapter.gd:72-95`
  - `tests/integration/presentation_ui_r13_terminal/r13_terminal_test_support.gd:28-44`
  - `tests/integration/presentation_ui_r13_terminal/test_production_joint_fallback_recovers_after_results_install_fault.gd:42-58`
  - `review-log.md:240`
- Failure scenario: implementation 已把 RUN lease revoke 移到 RESULTS route 前，但所宣稱的 R14-B03 regression evidence仍只讓 RESULTS 首次失敗、RESULTS_FALLBACK成功。沒有測兩個 route都 fail，也沒有持有舊 gameplay／navigation／confirmation callback逐一驗 `SCREEN_NOT_ACTIVE`。日後把 revoke 移回 fallback成功後，現有測試仍可綠。
- Violated requirement:
  - `requirements.md:120-129,177-186`
  - R14 `G2-R14-B03` 要求的「雙 fault typed host fallback＋stale callback matrix」
- Proposed fix: 加入可同時 fault RESULTS 與 RESULTS_FALLBACK 的 production catalog/router，保留舊三類 callback並逐一驗 fail-closed。
- Required regression evidence: terminal save已提交、兩個 scene install都失敗時，App state=RESULTS、save無 active run、receipt exactly-once、active RUN lease為 null/失效，舊 gameplay dispatch、navigation、confirmation begin/confirm/cancel全回 `SCREEN_NOT_ACTIVE`；fresh host recovery仍可前進。

### G2-R15-B06

- Severity: **Medium**
- Exact file:line:
  - `.pipeline/t15/ac-evidence-ledger.md:4-7,11-29,42-67`
  - `.pipeline/t15/manifest-audit.md:8-24`
  - `.pipeline/t15/final-automation-evidence.md:8-37`
  - `.pipeline/t15/logs/gut.txt:1`
  - `.pipeline/visual/r14-production-runtime/runner.log:54-83`
  - `specs/presentation-ui/tasks.md:296-312`
  - `specs/presentation-ui/review-log.md:263-267`
- Failure scenario: 19-row ledger仍將多項 AC標為 GAP/PARTIAL/DEFERRED/CANDIDATE，沒有任何 final PASS；manifest audit與 final automation evidence仍記21 manifests/84 entries、836 tests、R12/R13 deferred，而目前只讀 audit是36 active manifests/107 entries且 hashes全符。review-log卻宣稱920/920、3694 cases與 R14全修。保存的 T15 suite log只有「Requested suites completed.」，唯一 `r14-production-runtime/runner.log`是 exit 2、零 reports的失敗執行；較新的 JSON/10 PNG hashes彼此一致，但沒有對應成功 runner log。故 R14-B07與 R14 completion evidence尚未封閉。
- Violated requirement:
  - `requirements.md:369-386`
  - `tasks.md:296-312,340-346`
  - R14 `G2-R14-B07`
- Proposed fix: 在所有行為缺口修正後重新跑 final fresh gates；保留完整 stdout/stderr、command、exit code與 artifact hash，重建19-row ledger，每列只能是具體 PASS或使用者明示裁決，並同步更新 manifest audit、final evidence、tasks、review-log、PROGRESS、HANDOFF。
- Required regression evidence: fresh 36-manifest/107-entry audit；具完整輸出的 Gut/All/Spec/soak logs；成功 runtime runner log與10 PNG/report SHA read-back；19 owning AC逐列 production anchor、owning test、fresh result、final PASS。

## 已確認封閉的 R14 findings

- `G2-R14-A01`：已封閉。
- `G2-R14-A02`：已封閉。
- `G2-R14-A04/B02` 的 observable bind-fault/Results guard 部分已封閉。
- `G2-R14-A05`：已封閉其 production screen surface。
- `G2-R14-B04`：已封閉。
- `G2-R14-B05`：AppRoot→SettingsApplicationPort→route reload joint wiring 已封閉。

`G2-R14-A03/B01`、`B03` 的必要 regression evidence、`B06`、`B07` 不視為完整封閉，原因已列於本輪 findings。

## Evidence limitations

本輪遵守唯讀限制，未執行 Godot。已 read-back production code、測試、manifests、報告與 PNG；
10 張目前 R14 PNG 的檔案 SHA-256 均與 JSON 內值相符。未把後續 `content-production`
美術量產列為 finding；上述問題皆是本片已明定的操作、viewport、accessibility與 release evidence缺口。
