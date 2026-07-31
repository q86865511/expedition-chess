# G2 content-production — 需求規格

> 建立日期：2026-07-31｜狀態：APPROVED
> 基線：`master@5e78ccf`｜分支：`codex/g2-content-production`
> 橫切 owner：REQ-PROD-001、REQ-SCOPE-002、REQ-QA-001
> 額外依賴：REQ-CONTENT-001
> Global AC：AC-015、016、018、021、022、023、033、034、038、046、047、
> 050、051、052、057、060、067、074

## R1 — 版本與相容邊界

- 最新 production generation 固定使用 content codec 3 與 save schema 4。
- codec 1／2 reader、golden 與 schema 0／1／2／3 migration 必須保持可讀。
- codec 2→3 只能使用精確 allowlist pack，不得依賴「latest」或執行期猜測。
- `5ddf80a`、`9362e7d`、`5e78ccf` 三個 schema 3／codec 2 來源 fixture
  必須可重現、可驗 hash，且相容結論有測試證據。

## R2 — 44 個正式單位

- 32 個玩家單位與 12 個怪物 UnitDef 均具備非空、可解析的 AbilityDef、
  專屬主要 EffectDef、UnitPresentationDef、正式 tooltip 與 localization。
- 每個 UnitDef 的基礎 stats、cost、trait 與既有經濟值維持不變；本片不得做
  TUNE 平衡或以測試結果調整數值。
- 技能參數是 functional provisional baseline；所有 trigger、condition、
  battle operation、stacking 與允許的 scalar run intent 均使用 typed 定義。
- commander passive 不得在同一 EffectDef 混用 battle operations 與 run operations。
- 正式 cast graph 唯一為
  `UnitDef.ability_ref → AbilityDef.effect_refs → primary EffectDef`；
  `UnitDef.effect_refs` 只可保存 innate/on-board passive，不得重複 ability primary。

## R3 — 內容數量與分布

- 玩家單位 cost 分布固定為 10／8／6／5／3。
- 玩家單位涵蓋 6 faction、6 role，且恰有 4 個三標籤單位。
- 怪物包含 12 個正式單位、6 個 elite affix 與 3 個 boss。
- 至少一個 Boss 必須有兩個以上依 HP threshold 觸發的正式 phase，phase source、
  effect 順序與預覽均為 typed content。
- ContentValidator 對每個數量、分布、引用、枚舉、operation 與 migration invariant
  提供具名錯誤，invalid content 必須非零退出。

## R4 — 事件與節點選擇

- 至少 12 個正式 event choice set，每組至少 2 個具實質代價差異的選項。
- rest 固定提供「回復最大遠征 HP 20%」與「拆解服務」兩選項。
- treasure 至少提供 3 個選項；merchant 維持既有 transaction service。
- 選項在提交前不得呈現結果；確認使用既有
  `LiveScreenIntentPort.begin_confirmation → confirm/cancel`。
- cancel 零 dispatch／零寫入；confirm exactly-once；stale、repeat、錯誤 lease、
  route generation、run identity 或 payload digest 必須具名拒絕。
- 任一 confirm／cancel 結果都要關閉 modal、恢復焦點與背景；失敗透過
  PresentationStatusView 顯示。
- pending choice 是唯一 `ResolutionState`；提交成功產生可持久化 receipt/result，
  reload 或 post-commit route failure 只重播已提交結果，不重新套用 operation。
- choice outcome 只能是 `APPLY_AND_COMPLETE`、`OPEN_DISMANTLE_SERVICE` 或
  `OPEN_REWARD_STAGE`。拆解服務可執行多次既有 transaction，只有具名 exit
  command 完成節點；取消 confirmation 不等於退出已提交的服務。

## R5 — Tooltip 與 localization

- 所有玩家可見名稱、技能、效果、選項、預覽、結果、tooltip 與 audio label
  必須使用 localization key。
- `zh_TW` 與 `en` key set 完全一致；拒絕重複、空值、缺鍵、未支援 locale
  與玩家可見硬編碼字串。
- `LocalizationCatalog` 保留既有 public API，並完整保留 PR #6 的 status、
  fallback、board、combat 與 error keys。
- production catalog 必須先經 typed load result 驗證才可建立
  `LocalizationCatalog`；emergency catalog 只供具名 boot/recovery/status keys，
  不得把 production catalog fault 轉為成功啟動。
- Tooltip 的數值必須來自 pinned compiled content 或正式 formula service，
  不得複製計算公式；runtime nesting depth 最大為 2。

## R6 — Presentation 與音訊邊界

- VFX、音效與 tooltip 只消費 committed snapshot／battle event，不得改動
  simulation entropy、canonical result、playback cursor 或 gameplay timing。
- 保留 APP_ROUTE_FALLBACK、route candidate 回收、snapshot clone fail-closed、
  visible status surface 與既有 accessibility/focus 契約。
- 保留自動 playback→SETTLE→REWARD、500ms pre-commit retry、成功或
  post-commit exactly-once，以及無 transcript resume。

## R7 — Save schema 4

- ContentSnapshotState 持久化 `catalog_schema_version` 與
  `content_codec_version`；pending node choice 以具名 DTO 寫入 save。
- schema 3→4 必須逐版執行。Profile-only 可結構升級；active run 僅能在既有
  safe-state gate 通過後套用 allowlisted generation migration。
- 不安全 active run 以 `incompatible_preserved` 回報，原 bytes 與 backup
  完整保留；schema 4／codec 3 重複載入 idempotent。

## R8 — 正式圖像資產

- 44 個單位各有一張 256×256 portrait、1024×1024 atlas 與 SpriteFrames。
- 每個單位 atlas 有 240 個具名 frame：
  `idle 2 + move 4 + attack 4 + cast 4 + hit 2 + death 4`，
  乘 4 方向與 3 星級；星級變化不得改 collision／footprint。
- 每張 5×5 source sheet 是 20 個動作 key pose 加 5 個 identity/detail reference；
  每個動作 pose 以 4 個核可方向各自產生，不以鏡射冒充方向。3 個星級由同一
  base frame 加 deterministic 非 gameplay overlay，故每個單位正好
  `20 × 4 × 3 = 240` 個 frame。不得複製靜止 cell 冒充動畫。
- 另有 trait、ability、status/damage、combat VFX、core UI 五張共用 atlas
  與一張正式 camp environment。
- 玩家單位須具不同 silhouette、palette、weapon/role；不得只靠換色區分。

## R9 — 正式音訊

- 5 個可循環 OGG：menu、camp、expedition、combat、results。
- 21 個 semantic SFX：
  ui_focus、ui_confirm、ui_cancel、ui_error、shop_buy、shop_sell、shop_refresh、
  forge、equip、reward_select、event_select、combat_melee_hit、
  combat_ranged_attack、combat_cast、combat_magic_hit、combat_heal、
  combat_shield、combat_death、combat_boss_warning、combat_victory、
  combat_defeat。
- 固定種子程序合成；encoder／libsndfile 版本、wheel hash、格式、peak、
  loop seam 與四 bus routing 均須可驗。
- production 音訊固定 48 kHz、stereo、Vorbis quality 0.5；music 20–40 秒、
  SFX 0.08–2.0 秒、true peak ≤ -1 dBFS、loop seam RMS ≤ -45 dBFS。

## R10 — Provenance 與原創性

- 每個正式圖像保存 prompt、ImageGen call ID、來源圖、處理 seed／參數、
  工具版本、來源／輸出 SHA-256 與採用狀態。
- Built-in ImageGen 未提供 model-native seed 時，精確記為
  `not_exposed_by_builtin_image_gen`，不得虛構。
- 未採用變體不進 production inventory；T13 只作核可視覺方向與 reference。
- 每單位允許多次獨立生成 attempt，直到恰一個 source adopted；每個 attempt
  必須經獨立人工 `generated → reviewed → adopted/rejected` gate。
  Reviewer只輸出decision，主流程回寫ledger；production reference/inventory
  只能含adopted，rejected保留在attempt provenance ledger。

## R11 — TDD 與回歸

- 五個 wave 均先建立有效 behavioral red tests，再鎖 SHA-256 manifest，
  實作 green 後驗證 manifest 未漂移。
- 生成資產本身免 red，但數量、格式、引用、alpha、frame map、重複度、
  provenance 與 runtime contract 的 validator 必須先紅。
- 每波執行 targeted tests 與 wave regression；最終重跑 All、Content、
  Canonical、save、runtime、asset、localization、presentation static/runtime/
  screenshot 與 10k ExpeditionSoak。
- 本片禁止 TUNE、30k bot soak 與 release external gate。

## R12 — 雙審 Gate

- SDD 與 implementation 各由兩位獨立唯讀 reviewer 審查，單一 gate 最多三輪。
- 範圍內 finding 自動修正；reviewer 衝突、public contract 變更、範圍擴張，
  或第三輪後仍有 Blocker／Major 時硬停。
- Reviewer 只讀、不修改、不 commit、不 push。

## R13 — Global AC closure

下表原樣保留上游 Given／When／Then，不得以較弱摘要替代：

| AC | Given | When | Then |
|---|---|---|---|
| 015 | 棋盤有同 ID 重複、板凳與召喚物 | 計算羈絆並有單位死亡 | 只計不同上場 ID，快照在整場不因死亡變動 |
| 016 | 6 種零件 | 枚舉含同種的所有無序配對 | 正好得到 21 個唯一成裝 |
| 018 | 已啟用五件遺物 | 取得第六件 | 必須替換或放棄；重載後選擇及槽位順序不變 |
| 021 | 基礎 profile 與三位指揮官 | 分別建立遠征 | 指揮官不上場、不佔人口，起始包與被動各自不同 |
| 022 | 任一局外解鎖 | 比較解鎖前後相同 UnitDef 的基礎 stats | 基礎生命與攻防完全一致，只增加選項或難度 |
| 023 | 正在進行的 content_snapshot | 局外解鎖新棋子後續讀 | 進行中遠征內容池不變，新遠征才套用 |
| 033 | 全部候選角色、美術、名稱及 UI | 執行原創性審查 | 無直接使用或近似重製 Riot 的受保護內容 |
| 034 | 新增一個 +1 人口來源 | 執行內容驗證與壓測選擇 | 最大人口重新計算，壓測下限同步提高 |
| 038 | 內容完整 G2 候選 | 執行資產清單驗證 | 32 隻玩家棋子各自具備第 6.3 節全部資產，無色票替代角色 |
| 046 | 事件、商人、休整、寶藏、鍛造、裝備、遺物替換各一個待提交選擇 | 在提交前後每個故障注入點終止並載入 | 不會半消耗或重領；已顯示不可逆結果必有相符的已提交狀態 |
| 047 | 一份有效內容集 | 逐次破壞每項第 11.2 節 invariant 並執行驗證器 | 每一種破壞都產生具體錯誤及非零退出碼；有效集回傳 0 |
| 050 | 固定 run seed、act、node、難度與解鎖池 | 只替換玩家 roster、羈絆及裝備後重新產生遭遇 | EncounterDef、敵隊與詞綴完全不變 |
| 051 | 含舊 stable ID 的已發布存檔 fixture | 內容 ID 改名並提供 alias 後載入 | 舊引用遷移至新 ID、資料守恆、再次 migration 不改變結果 |
| 052 | 含已刪除內容的兩份 fixture | 分別刪除非必要圖鑑內容與當前棋子／遺物 | 前者由 tombstone 安全載入；後者拒載、保留 backup 且不猜測替代 |
| 057 | 棋盤、板凳與物品庫皆滿的合法玩家 | 產生普通、事件與棋子獎勵並嘗試提交 | 每組至少有可領非棋子選項；棋子可經 unit_overflow 出售／替換／放棄完成，無軟鎖或靜默遺失 |
| 060 | 三個待合成同名棋子含超過三件裝備及相同 unique_group | 依固定主體與槽序完成合成、存檔並重載 | 主體合法裝備保持；衝突／超量裝備依序進 inventory／overflow，沒有取代、銷毀或複製 |
| 067 | 每一種 EffectDef operation 與 BattleEvent type | 執行型別掃描、codec round-trip 與戰敗／勝利結算 | battle operation 只改 local state；run intent 只在合法勝利提交；payload 無任意 Dictionary，event hash 穩定 |
| 074 | 一組戰鬥效果分別提出三種合法 scalar intent 與棋子、物品、遺物、人口等容量型 intent | 執行內容驗證並讓合法效果在 Boss 先敗後勝 | 容量型內容以非零碼拒絕；戰敗不提交 scalar，首次勝利依 claim key 提交一次並按金幣／XP／HP 上限決定性 clamp |

## R14 — 完成邊界

- 產出逐 AC acceptance JSON、implementation review、review decision table、
  fixture／asset hashes 與所有 gate 證據。
- 更新 roadmap、PROGRESS、HANDOFF 與 implementation slices。
- 完成後工作樹保持未提交，停在 Git／PR gate；不得 commit、push 或開 PR。
