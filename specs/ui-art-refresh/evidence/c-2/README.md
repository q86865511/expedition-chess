# C-2 RUN_COMBAT 戰鬥呈現驗收證據

## 結果

C-2 已完成 `combat_vfx`／`status_damage` atlas 接線、傷害飄字、播放速度同步、
ImageGen 夜色戰鬥背景，以及使用者核可後追加的 PREPARE／COMBAT 共用商店卡重製。
C-2 依裁決完成提交後直接進入 C-3 音訊，不另設中間核可停點。

VFX 掛在 production world surface 的棋盤世界層。`RunCombatScreen` 先依既有順序
消費 canonical battle event，再將同一批事件交給 presentation-only renderer；傷害數字
密度只決定飄字實例預算（off 0／reduced 24／full 96），不過濾或重排事件。VFX 時鐘只在
播放未暫停時前進，並使用 1×／2×／4× 倍率；沒有讀取或回寫 gameplay RNG stream。

## 九組矩陣

| 解析度 | UI 100 | UI 125 | UI 150 |
|---|---|---|---|
| 1280×720 | [圖](./run-combat-720p-ui100.png) | [圖](./run-combat-720p-ui125.png) | [圖](./run-combat-720p-ui150.png) |
| 1920×1080 | [圖](./run-combat-1080p-ui100.png) | [圖](./run-combat-1080p-ui125.png) | [圖](./run-combat-1080p-ui150.png) |
| 2560×1440 | [圖](./run-combat-1440p-ui100.png) | [圖](./run-combat-1440p-ui125.png) | [圖](./run-combat-1440p-ui150.png) |

九張均由真實 production harness 進入 `RUN_COMBAT`，使用已提交的 battle transcript 事件；
每張驗出 1 個 world surface、戰鬥背景、4 個 active VFX、1 個傷害飄字，且已處理的事件
sequence 為 0～15。逐張人工檢視確認棋盤、角色、VFX、`-17` 飄字與控制列可辨，無互相
裁切；背景維持低對比，不搶戰鬥資訊。UI125 初次取樣曾撞到 settings 重建的暫態畫面，
runner 已增加 12-frame settle gate 後全數重拍。結構化結果見
[evidence-report.json](./evidence-report.json) 與 [visual-qa.json](./visual-qa.json)。

## 戰鬥播放序列與速度狀態

- [暫停](./battle-sequence-01-pause.png)
- [1×](./battle-sequence-02-1x.png)
- [2×](./battle-sequence-03-2x.png)
- [4×](./battle-sequence-04-4x.png)

獨立狀態證據另見 [pause](./playback-pause.png)、[1×](./playback-1x.png)、
[2×](./playback-2x.png)、[4×](./playback-4x.png)。四個狀態皆保留同一 canonical
processed sequence；差異只反映 presentation VFX 時鐘與按鈕／狀態提示。

## 共用商店卡修訂

PREPARE 與 COMBAT 都由 `ProductionScreen` 的同一個 presentation-only card builder
產生 182×108 卡片。182×108 是 `layout-reference-1920.json` 約 197×134 上限在既有
UI150 三欄底帶（商店、分組動作、固定動作）內的實測適配值。卡面以滿版 portrait 為底，
左上最多三枚「圖示＋在地化羈絆名」黑底膠囊，底部只保留單位名與金幣費用；費用階邊框、
非色彩 pips、已持有副本與升星預覽訊號均保留。文字清單式的「陣營／職業」行已移除。

| route | 1280×720 / UI100 | 1920×1080 / UI100 | 2560×1440 / UI100 |
|---|---|---|---|
| PREPARE | [圖](./shop-prepare-720p-ui100.png) | [圖](./shop-prepare-1080p-ui100.png) | [圖](./shop-prepare-1440p-ui100.png) |
| COMBAT | [圖](./shop-combat-720p-ui100.png) | [圖](./shop-combat-1080p-ui100.png) | [圖](./shop-combat-1440p-ui100.png) |

六張均逐張人工檢視：卡片完整可見、portrait 裁切置中、徽章與底列無截斷、沒有
`Frost`／`Marksman` 等英文原名漏出。evidence runner 同時驗證每張卡的 portrait、1～3 枚
徽章、固定尺寸、名稱寬度與在地化值，六組皆 `ok=true`。

### Trait 顯示值 reseal 對映

此表是依 2026-08-19 使用者單次 app 邊界例外核准執行的直譯佔位；Phase D 的正式風味命名
仍由使用者裁決，屆時只改值、不改 key。

| key | 舊值（zh_TW / en） | 新 zh_TW | 新 en |
|---|---|---|---|
| `loc.trait_faction_arcane` | 陣營：Arcane / Faction: Arcane | 奧術 | Arcane |
| `loc.trait_faction_ember` | 陣營：Ember / Faction: Ember | 燼 | Ember |
| `loc.trait_faction_frost` | 陣營：Frost / Faction: Frost | 霜 | Frost |
| `loc.trait_faction_iron` | 陣營：Iron / Faction: Iron | 鐵 | Iron |
| `loc.trait_faction_shadow` | 陣營：Shadow / Faction: Shadow | 影 | Shadow |
| `loc.trait_faction_verdant` | 陣營：Verdant / Faction: Verdant | 翠蔭 | Verdant |
| `loc.trait_role_marksman` | 職業：Marksman / Role: Marksman | 神射手 | Marksman |
| `loc.trait_role_mystic` | 職業：Mystic / Role: Mystic | 秘術師 | Mystic |
| `loc.trait_role_sentinel` | 職業：Sentinel / Role: Sentinel | 哨衛 | Sentinel |
| `loc.trait_role_trickster` | 職業：Trickster / Role: Trickster | 詭術師 | Trickster |
| `loc.trait_role_vanguard` | 職業：Vanguard / Role: Vanguard | 先鋒 | Vanguard |
| `loc.trait_role_warden` | 職業：Warden / Role: Warden | 守望者 | Warden |

exporter 重導後 `catalog.v2.csv` 與 `.raw` 皆為 941 rows、只變更上述 12 個 display rows，
共同 SHA-256 為
`619d20f2f064a03a1c84447b032ac115fa50d0ec70787ca81acfdb8d51367882`；bootstrap seal
已同步。結構化紀錄見 [localization-reseal.json](./localization-reseal.json)。

## 背景資產

ImageGen 依 `environment.run_map` 的像素語言與色盤產出兩個候選，採用低對比、乾燥石地
中央區的第一稿作三幕共用背景。共用一張可避免三幕美術差異誤導戰鬥規則，並把成本集中在
VFX 可讀性；第二稿的水面反光會干擾棋盤，未複製進 repository 或 inventory。採用稿為
1672×941，SHA-256 `98a2217bf74ee2a5eb1f049796066d1e4c65856b4700aad415763d91a948338d`。
完整 prompt、參考 SHA、輸出 SHA 與選用理由見
[run_combat_environment.json](../../../../assets/production/provenance/run_combat_environment.json)，
摘要見 [asset-sha256.json](./asset-sha256.json)。

## 測試與靜態閘門

- C-2 focused Gut：6／6 tests、44 assertions，exit 0。
- 共用商店卡／intent focused Gut：14／14 tests、314 assertions，exit 0。
- localization parity＋bootstrap reseal Gut：13／13 tests、1948 assertions，exit 0。
- 暫停／倍速 canonical 回歸：2／2 tests、52 assertions，exit 0。
- 商店卡最後修訂後 `tools/run-tests.ps1 -Suite All`：exit 0；Gut 355 scripts、
  1493／1493 tests、39458 assertions；Smoke 10 cases、failures 0。
- 最後修訂後獨立 `tools/run-tests.ps1 -Suite Combat`：exit 0；combat acceptance
  S2-AC-001～018 全 pass、`evidence_verified=true`。
- Fresh `tools/run-tests.ps1 -Suite Soak -SeedCount 10000`：exit 0；10000／10000 cases、
  failures 0、64 deterministic replays，deferred scopes 0。
- 證據 runner settle 修訂後的 final Import parse：exit 0。
- `git diff --check`：exit 0。
- C-2 差異中的 `theme_override_*`：0；presentation C-2 程式中的 `RngService`／
  `gameplay_stream` 引用：0。
- 未修改 `domain/`、`services/`、`presentation/viewmodels/`、
  `run_presentation_session.gd` 或 Claude 契約測試。`app/` 只有使用者於 2026-08-19
  明示核准的兩處例外：12 個既有 trait display key 的值，以及 bootstrap catalog SHA；
  CSV／raw 只由既有 exporter 重導，沒有手改，也沒有其他 app 差異。
- 使用者既有 `project.godot` 編輯器改寫保留，C-2 未碰該檔。

最後修訂後 All 摘要與 artifact hashes 見 [all-output-summary.json](./all-output-summary.json)；
較早 C-2 全綠 runner 的逐步記錄保留於 [all-runner-execution.json](./all-runner-execution.json)，
其後另以最後商店卡版本重跑 All 全綠。其他 runner 記錄見
[combat-runner-execution.json](./combat-runner-execution.json)、
[focused-runner-execution.json](./focused-runner-execution.json) 與
[playback-runner-execution.json](./playback-runner-execution.json)；證據 runner 的最終 parse 見
[final-import-runner-execution.json](./final-import-runner-execution.json)，10k soak 見
[soak-runner-execution.json](./soak-runner-execution.json) 與
[soak-output-summary.json](./soak-output-summary.json)。
