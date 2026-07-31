# G2 content-production — 技術設計

> 建立日期：2026-07-31｜狀態：APPROVED
> 對照：[requirements.md](requirements.md) R1～R14

## 1. 版本化 content pipeline

- 保留 `ContentCanonicalCodecV1/V2` 與 `ContentDefinitionCompiler/V2`。
- 新增 `ContentCanonicalCodecV3` 與 `ContentDefinitionCompilerV3`；
  V3 沿用既有 canonical value encoding，只新增 category／field schema。
- 最新 tuple 固定為 `(catalog_schema_version=2, content_codec_version=3)`。
  `CCM1` manifest record 仍為 `0x0101`、fields `1..7`、kinds
  `[U32,U32,STRING,SET,SET,SET,LIST]`，但 field 1/2 必須為 3/2。
  Entry/catalog magic `CCE1`/`CCC1` 與 primitive encoding 不變。
- UnitDef/EffectDef resource schema 升為 2；新三類為 1；其餘類別仍為 1。
  Registry 必須由 persisted
  `(catalog_schema_version,content_codec_version,manifest_digest)` 精確選擇
  `(1,1)`、`(1,2)` 或 `(2,3)` reader/compiler；`latest` 只供建立新 run。
- 新 category code：
  - `UNIT_PRESENTATION = 0x1011`
  - `NODE_CHOICE_SET = 0x1012`
  - `AUDIO_CUE = 0x1013`
- 新 nested record `NodeChoiceDef = 0x2010`。Record field IDs 必須嚴格遞增、
  完整且唯一；unknown/missing/duplicate/wrong-kind/wrong-child-type fail-closed。
  SET 依 child canonical bytes 排序且拒絕 duplicate；LIST 保留 author order。

### V3 exact category schema

所有 category 先有 common fields：
`1:STRING display_name_key, 2:SET<STABLE_ID> unlock_refs,
3:SET<PATH> asset_refs`。完整追加欄如下：

| Record / resource schema | Exact additional fields（hex field ID: kind） |
|---|---|
| Unit `0x1001` / 2 | `0100:U32 cost_tier, 0101:SET<STABLE_ID> trait_refs, 0102:RECORD<2000> base_stats, 0103:SET<RECORD<200f>> star_scalings, 0104:OPTIONAL<STABLE_ID> ability_ref, 0105:ENUM ai_profile, 0106:ENUM basic_attack_profile, 0107:ENUM availability, 0108:ENUM shop_condition, 0109:LIST<STABLE_ID> innate_effect_refs, 010a:STABLE_ID presentation_ref` |
| Effect `0x1004` / 2 | `0100:ENUM content_role, 0101:ENUM trigger, 0102:U32 periodic_interval_ticks, 0103:SET<RECORD<2002>> conditions, 0104:LIST<RECORD<3001..3009>> battle_operations, 0105:LIST<RECORD<3101..310a>> run_operations, 0106:ENUM stacking, 0107:U32 max_stacks, 0108:U32 duration_ticks, 0109:STRING description_key` |
| UnitPresentation `0x1011` / 1 | `0100:PATH portrait_path, 0101:PATH sprite_frames_path, 0102:PATH board_icon_path, 0103:PATH ability_icon_path, 0104:LIST<STABLE_ID> combat_vfx_refs, 0105:LIST<STABLE_ID> audio_cue_refs` |
| NodeChoiceSet `0x1012` / 1 | `0100:ENUM node_kind, 0101:LIST<RECORD<2010>> choices` |
| AudioCue `0x1013` / 1 | `0100:ENUM bus, 0101:PATH stream_path, 0102:BOOL loop` |

其餘 category、`0x2000..0x200f`、`0x3001..0x3009`、
`0x3101..0x310a` 完全沿用 V2，不得重排。`0x2010` fields：

| ID | Kind | Semantic |
|---|---|---|
| 1 | STABLE_ID | choice_id，set 內唯一 |
| 2 | U32 | sort_order，set 內唯一且從 0 連續 |
| 3..6 | STRING | title、description、preview、result keys |
| 7 | LIST<RECORD 0x3101..0x310a> | typed run operations |
| 8 | OPTIONAL<STABLE_ID> | reward_table_ref |
| 9 | ENUM | APPLY_AND_COMPLETE / OPEN_DISMANTLE_SERVICE / OPEN_REWARD_STAGE |
| 10 | BOOL | confirmation_required |

Choices 按 sort_order 形成 LIST；decoder 同時驗 order。OPEN_REWARD_STAGE 必有
reward ref；其餘不得有。OPEN_DISMANTLE_SERVICE 不得有 operations/reward ref。
V3 golden 鎖 manifest、新 categories、Unit/Effect 與 2010；每欄 wrong-kind、
unknown、duplicate、tamper 均為 negative。

## 2. 新增與擴充定義

### UnitPresentationDef

```gdscript
class_name UnitPresentationDef
extends ContentDefinition

@export var portrait_path: String
@export var sprite_frames_path: String
@export var board_icon_path: String
@export var ability_icon_path: String
@export var combat_vfx_refs: Array[StringName]
@export var audio_cue_refs: Array[StringName]
```

### NodeChoiceSetDef／NodeChoiceDef

```gdscript
class_name NodeChoiceSetDef
extends ContentDefinition

@export var node_kind: StringName
@export var choices: Array[NodeChoiceDef]
```

`NodeChoiceDef` 置於獨立檔案（每檔只能一個 `class_name`）：

```gdscript
class_name NodeChoiceDef
extends Resource

@export var choice_id: StringName
@export var sort_order: int
@export var title_key: StringName
@export var description_key: StringName
@export var preview_key: StringName
@export var result_key: StringName
@export var operations: Array[RunOperationDef]
@export var has_reward_table_ref: bool
@export var reward_table_ref: StringName
@export var outcome_kind: StringName
@export var confirmation_required: bool
```

### AudioCueDef

```gdscript
class_name AudioCueDef
extends ContentDefinition

@export var bus: StringName
@export var stream_path: String
@export var loop: bool
```

### 既有型別

- `UnitDef.presentation_ref: StringName`
- `EffectDef.description_key: StringName`
- `MapNodeDef.generator_ref` 依 node kind 指向 EncounterDef 或 NodeChoiceSetDef。
- Codec V3 的 UnitDef／EffectDef 將新欄位置於既有欄位之後，不重排 V2。

## 3. 正式內容 authoring

- 以既有 44 個 UnitDef ID 為權威，不改 stats、cost、traits 或 economy values。
- 為每個 UnitDef 建立 `ability.<unit token>`、`effect.<unit token>.primary` 與
  `presentation.<unit token>`。唯一 cast graph 是 UnitDef→AbilityDef→primary
  EffectDef，UnitDef另指 presentation；`UnitDef.effect_refs` 只保存 innate/
  on-board passive，validator拒絕與 ability effect_refs 交集。
- Ability／Effect 使用 deterministic template family 量產，但每個單位的 target、
  operation、damage/status semantics 與 tooltip key 均為正式資料，不在 UI 寫分支。
- 補充 shared status／VFX effects 可被多個主要 effect 引用，但主要 effect 一對一。
- Commander passive validator 先檢查 battle/run operation exclusive，再進一般
  operation／reference validation。

## 4. Localization 與 tooltip

- UTF-8 catalog 固定 RFC4180 CSV、無 BOM、header exact `key,zh_TW,en`，
  逗號分隔、quote escape `""`，接受 CRLF/LF。
- `LocalizationCatalogLoadRequest` exact fields為
  `source_id:StringName, source_bytes:PackedByteArray, expected_sha256:String`；
  建構時deep-copy bytes，source_id必須是tracked `res://` identity，digest必須
  小寫64-hex。Loader只hash/parse這份immutable bytes，不得驗完再重讀path。
- `LocalizationCatalogLoader.load(request) -> LocalizationCatalogLoadResult`
  是唯一 production factory；result exact為 `ok,catalog,error`，成功時只有
  sealed catalog、失敗時只有error，兩者不得同時存在。Error含 code/row/key，只允許
  `IO/MALFORMED_HEADER/MALFORMED_ROW/DUPLICATE_KEY/BLANK_VALUE/KEY_PARITY/
  UNSUPPORTED_LOCALE/HARDCODED_TEXT`。AppRoot/ContentDependencyPort只有
  `ok=true` 可接受 catalog；`LocalizationCatalog` constructor需要loader-private
  seal，production不得直接new；既有四個 public API簽章不變。
- Emergency catalog由獨立restricted factory從同一tracked source生成並驗value
  parity，只含具名boot/recovery/status keys，不接受任意bytes/path。Production
  load failure仍阻止boot，只有recovery route可用emergency catalog。
- `ContentTooltipCatalog` 只接受 pinned `ContentDefinitionView`／receipt；
  `ContentTooltipFormatter` 將 localized label 與正式 definition/formula 值組合。
- UI 只接收 immutable `ContentTooltipSnapshot`；accessibility runtime 繼續負責
  depth ≤2 guard。Snapshot綁 `locale_generation`；locale commit後以同一 pinned
  content重建，禁止沿用舊 locale snapshot。

## 5. Node choice transaction

- `ResolutionState.Kind.NODE_CHOICE_PENDING=4` 是 pending choice 唯一權威。
  `NodeChoicePendingState` exact fields：
  `node_id,choice_set_id,choice_ids,content_version,catalog_schema_version,
  content_codec_version,manifest_digest,lifecycle_nonce,pending_digest`。
  choice_ids依 content sort_order；nonce是非零小寫16-hex u64。
- `pending_digest = SHA256("NCP1" + framed UTF-8
  [node_id,choice_set_id,content_version] + catalog/content codec u32-be +
  manifest raw32 + nonce u64-be + choice count u32-be +
  每個 choice_id framed UTF-8)`；framed string為u32-be byte length加strict UTF-8。
- 進入 event/rest/treasure 時先在 RunController draft 產生 pending state並存檔；
  presentation只從 committed snapshot顯示。
- `RunPresentationSnapshot.node_choice: NodeChoiceView` deep clone identity與
  localized immutable choices。`RunPresentationIntent.COMMIT_NODE_CHOICE` 與
  `CommitNodeChoiceCommand` exact攜帶
  `expected_run_id,node_id,choice_set_id,pending_digest,content_version,
  catalog_schema_version,content_codec_version,manifest_digest,lifecycle_nonce,
  choice_id`；factory不得以 latest state覆蓋。Confirmation payload digest涵蓋
  相同 sequence與 choice_id。
- Command rejection codes：
  `RUN_MISMATCH/NODE_MISMATCH/CHOICE_SET_MISMATCH/CONTENT_VERSION_MISMATCH/
  CATALOG_SCHEMA_MISMATCH/CODEC_MISMATCH/MANIFEST_MISMATCH/
  PENDING_DIGEST_MISMATCH/NONCE_MISMATCH/CHOICE_UNKNOWN/ALREADY_COMMITTED`。
  LiveScreen另保留 `LEASE_STALE/ROUTE_GENERATION_STALE/LIFECYCLE_STALE/
  PAYLOAD_DIGEST_MISMATCH/CONFIRMATION_ALREADY_CLOSED`。
- 成功在同一copy-validate-save-swap transaction套用operation並append唯一
  `NodeChoiceReceiptLedgerEntry(receipt,result_acknowledged=false)` 至run-level
  `node_choice_receipts`。Immutable receipt fields：
  `run_id,node_id,choice_set_id,choice_id,pending_digest,lifecycle_nonce,
  transaction_serial,transaction_digest,result_key,outcome_kind,receipt_digest`。
- NCR1 preimage exact：
  ASCII `NCR1`，依序u32-be framed strict UTF-8
  `run_id,node_id,choice_set_id,choice_id`，pending raw32，nonce u64-be，
  transaction_serial u64-be，transaction digest raw32，framed result_key，
  outcome u32-be（APPLY=1、DISMANTLE=2、REWARD=3）。receipt_digest是其SHA-256。
  transaction_digest必須等於
  `RuntimeKeySchemaRegistry.build_transaction(run_id,node_id,
  "commit_node_choice",transaction_serial)` 的既有V1 key digest，且同digest的
  TransactionReceiptState必須存在；不得另創第二種transaction key算法。
  Ledger依transaction_serial升冪，`(node_id,pending_digest)`與serial皆唯一，
  生命期到run terminal清除。
- UI只由unacknowledged committed receipt顯示result；
  `AcknowledgeNodeChoiceResultCommand(expected_run_id,receipt_digest)`在另一個
  copy-save-swap transaction只把wrapper flag改true，不刪receipt、不改digest。
  Post-commit route failure/reload重播false receipt；repeat confirm不論ack狀態
  都由ledger回ALREADY_COMMITTED。
- `APPLY_AND_COMPLETE` 提交後完成節點；`OPEN_REWARD_STAGE` 原子切為既有
  RewardPendingResolutionState，receipt只由run ledger持有；
  `OPEN_DISMANTLE_SERVICE` 原子切為
  `NodeServicePendingResolutionState(kind=dismantle,choice_receipt_digest)`。
  `DismantleWithNodeServiceCommand(expected_run_id,node_id,choice_receipt_digest,
  item_instance_id)`要求該service authority，沿用既有拆解/overflow規則但不要求、
  不消耗consumable；服務期間不限次數且每次仍有唯一transaction receipt。
  一般DismantleEquipmentCommand維持耗材規則。只有 `ExitNodeServiceCommand`
  完成節點；reload保留同一 receipt，repeat confirm一律 ALREADY_COMMITTED。
- UI 選定後建立既有 ConfirmationDraft；cancel零 dispatch，confirm才 dispatch。
  confirm/cancel任何結果都關 modal、恢復焦點/背景；Modal lifecycle、status、
  stale lease與route fallback沿用 ProductionScreen/LiveScreenIntentPort。

## 6. Save schema 4 與 codec migration

- `SaveSchemaContract.CURRENT = 4`。
- `ContentSnapshotState` 增加兩個正整數欄位並納入 clone、validation、
  canonical equality與save encoding；`manifest_digest`仍是receipt釘選的catalog
  digest，不把版本欄再次混入或重算：
  `catalog_schema_version`、`content_codec_version`。
- Schema 4 root keys沿用schema 3。Run keys在schema3
  `claim_receipts`與`resolution_state`之間新增`node_choice_receipts`，其餘順序
  不變。3→4建立空ledger。Snapshot exact key order：
  `content_version,catalog_schema_version,content_codec_version,
  enabled_content_ids,economy_config_id,combat_config_id,reward_table_ids,
  map_node_def_ids,challenge_unlock_def_ids,meta_reward_table_id,manifest_digest`。
  版本是JSON integer 1..0x7fffffff；current production必須2/3。
- `resolution.kind` 增 `node_choice_pending` 與 `node_service_pending`。
  前者 exact keys：
  `kind,node_id,choice_set_id,choice_ids,content_version,catalog_schema_version,
  content_codec_version,manifest_digest,lifecycle_nonce,pending_digest`。
  後者 exact keys `kind,service_kind,node_id,choice_receipt_digest`，
  service_kind目前只允許`dismantle`，digest必須resolve同run ledger。
- `node_choice_receipts`為array，entry exact keys
  `receipt,result_acknowledged`；receipt exact keys/order：
  `run_id,node_id,choice_set_id,choice_id,pending_digest,lifecycle_nonce,
  transaction_serial,transaction_digest,result_key,outcome_kind,receipt_digest`。
  nonce/serial為小寫16-hex，outcome字串只允許
  `apply_and_complete/open_dismantle_service/open_reward_stage`。
  Unknown/missing/null/wrong-type、
  非canonical array、非小寫16-hex u64／64-hex digest一律拒絕。
- `SaveMigrationV3ToV4` 對 profile-only只改schema_version。Active run先以精確
  source receipt驗證raw schema3 snapshot並注入1/2，再呼叫generation migration；
  成功才換target 2/3，失敗不交換原bytes；schema3 migration建立空receipt ledger。
  0→4固定0→1→2→3→4；
  4→4 encode/decode/encode bytes idempotent。

### CGM2／CGR2 exact migration contract

`ContentGenerationMigrationEntryV2` fields：
`source_category,source_id,requirement(REQUIRED|OPTIONAL),
mapping_kind(IDENTITY|ALIAS|TOMBSTONE),has_target,target_id,
target_entry_digest`。Strings以u32-be length+strict UTF-8；enum為u32-be；
requirement ordinals固定REQUIRED=1/OPTIONAL=2；mapping ordinals固定
IDENTITY=1/ALIAS=2/TOMBSTONE=3。CMR2逐欄bytes為ASCII magic、source category
framed、source id framed、requirement u32、mapping u32、has_target一byte；
has_target=1時再接target id framed與target digest raw32，=0時到此結束，
不得寫空字串或zero digest sentinel。Entries依
`(source_category bytes,source_id bytes)`升冪，source tuple唯一。ALIAS必有
不同target；IDENTITY target同source；TOMBSTONE不得有target。

`mapping_digest = SHA256("CME2" + count u32-be + 每筆完整 CMR2 entry bytes)`。
Localization digest先以loader規則parse/validate，再將rows依key strict UTF-8
bytes升冪，編為`"L10N2"+row_count u32-be+每row依序framed key/zh_TW/en`後
SHA-256；pack驗證只接受target generation所安裝的同一catalog bytes重算值。
`pack_digest = SHA256("CGM2" + framed source_content_version +
framed target_content_version + source_manifest raw32 + expected_target_manifest raw32 +
source_catalog_schema u32 + target_catalog_schema u32 + from_codec u32 + to_codec u32 +
mapping_digest raw32 + localization_catalog_digest raw32)`；固定source tuple 1/2、
target tuple 2/3。Allowlist key exact：
`(source_content_version,source_manifest_digest,pack_digest)`。

`receipt_digest = SHA256("CGR2" + source_manifest raw32 + target_manifest raw32 +
mapping_digest raw32 + localization_catalog_digest raw32 + pack_digest raw32 +
source_catalog_schema u32 + target_catalog_schema u32 + from_codec u32 + to_codec u32)`。
Receipt亦保存source/target content version與上述所有欄。

Normative golden（hex，小寫）：

- CMR2 alias vector（unit.old→unit.new，target digest bytes 00..1f）：
  `434d523200000004756e697400000008756e69742e6f6c6400000001000000020100000008756e69742e6e6577000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`
- CME2 single-entry bytes：
  `434d453200000001434d523200000004756e697400000008756e69742e6f6c6400000001000000020100000008756e69742e6e6577000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`
  → mapping digest
  `8ef8d3ebd6de4cb7b14caf68c3afbcf44c008440431e091c6d4593523b576a2b`。
- Empty L10N2 digest：
  `b97c9b707aadfc40186db9d5d9b6c30f98aff38f9e61b00ef414759428838d50`。
- CGM2 vector使用source/target=`old/new`、manifest bytes 00×32/11×32與上述
  digests；完整bytes：
  `43474d32000000036f6c64000000036e657700000000000000000000000000000000000000000000000000000000000000001111111111111111111111111111111111111111111111111111111111111111000000010000000200000002000000038ef8d3ebd6de4cb7b14caf68c3afbcf44c008440431e091c6d4593523b576a2bb97c9b707aadfc40186db9d5d9b6c30f98aff38f9e61b00ef414759428838d50`；
  pack digest：
  `497855dd8d3ede3a2b3a6c8a779a13f7a1f8127270f145b4cbc3ee3d439735df`。
- 對應CGR2完整bytes：
  `43475232000000000000000000000000000000000000000000000000000000000000000011111111111111111111111111111111111111111111111111111111111111118ef8d3ebd6de4cb7b14caf68c3afbcf44c008440431e091c6d4593523b576a2bb97c9b707aadfc40186db9d5d9b6c30f98aff38f9e61b00ef414759428838d50497855dd8d3ede3a2b3a6c8a779a13f7a1f8127270f145b4cbc3ee3d439735df00000001000000020000000200000003`；
  receipt digest：
  `c4dfb71a1e82fd7d4769046f5a3249fbfad5072cf55924cf38a0e16eef788208`。
  T10 fixture由本表參數重建，任何byte差異必須讓golden test失敗。

Adapter先驗全部digest、allowlist與exact target generation，再traverse
ContentSnapshot、board/bench/pool、equipment/inventory/overflow、relics、
commander、map/current node/preview、所有ResolutionState、reservation、
transaction/claim/receipt。被active run引用者必為REQUIRED且禁止TOMBSTONE；
OPTIONAL只允許未被active run引用的collection/codex entry。Alias只允許單hop；
alias target亦是source、cycle、同source多筆、缺mapping、category mismatch、
target缺entry或digest不符皆拒絕。轉換後以target V3重編manifest並比對expected，
才可發CGR2 receipt與交換。
- 安全 gate 維持 idle MAP、無 current node、無 pending preview／resolution；
  其他 active state 回 incompatible-preserved，SaveRepository 不交換 canonical bytes。
- 任一validation/transcode/save/read-back fault保留原main bytes逐byte相同，
  backup另存相同source bytes，禁止先寫schema4半成品。Negative matrix含每欄
  tamper、missing/duplicate/ambiguous mapping、alias chain/cycle、required/
  optional tombstone、target digest mismatch與retry。

## 7. 資產與音訊 pipeline

- ImageGen 每個attempt一個獨立built-in call，以 T13 accepted anchors 作reference；
  每單位至少一個attempt且最終恰一個adopted source。Rejected單位以新call重試。
  生成5×5 chroma source；前20格各是一個action frame且格內為2×2 N/E/S/W
  turnaround，末5格為portrait/weapon/material/VFX/silhouette reference。
  不得以一個call冒充多個distinct units。
- Processor對前20格裁四向、去背、nearest-neighbor resize成80 base frames，
  再套三個deterministic star overlays成240 frames；不得鏡射、複製frame或插值
  冒充方向/動作。Grammar與播放契約：
  `idle(2,4fps,loop),move(4,8fps,loop),attack(4,10fps,once),
  cast(4,10fps,once),hit(2,8fps,once),death(4,8fps,once)`；
  name=`<action>_<n|e|s|w>_star<1|2|3>`。
- 1024 atlas 為 16×16 個 64px cell；240 個 cell 按
  star→direction→action→frame 排列，最後 16 cell 保留透明。
- 程序音訊以固定 seed 產生 PCM，再由鎖定的 SoundFile/libsndfile encoder
  輸出 OGG；所有 cue 經 AudioCueDef 接至既有 Master/Music/SFX/UI bus。
- OGG fixed contract：Vorbis 48kHz stereo quality 0.5；music 20–40s且loop，
  SFX 0.08–2.0s且不loop；decoded true peak≤-1dBFS，music首尾50ms difference
  RMS≤-45dBFS。Music→Music；ui_*→UI；其他SFX→SFX；Master只作parent。
- PNG fixed contract：RGBA8/sRGB、filter/mipmaps=false；portrait 256²、
  unit/shared atlas 1024²、camp 1280×720。Chroma leak≤0.1% opaque pixels，
  nontransparent coverage 15–85%。同pose玩家silhouette IoU<0.92且SSIM<0.95；
  超標需人工reject，不能用換色豁免。
- `production-asset-attempts.json` 保存全部attempt：unit/attempt ID、
  generated/reviewed/adopted/rejected status、paths、prompt/call/model_seed、
  processing seed/params/tool versions、hash、reviewer/decision/reason。
  Reviewer唯讀產出decision table，由主流程驗signature/hash後回寫ledger。
- `production-asset-inventory.schema.json` 固定required/enum/range且
  additionalProperties=false；`production-asset-inventory.json`只含每單位恰一個
  adopted item與衍生outputs，禁止rejected/generated/reviewed status。
  Production reference只能resolve inventory內adopted source。
  Toolchain另鎖wheel filename/SHA-256與Python/SoundFile/libsndfile/encoder版本。

## 8. Presentation data flow

- Battle VFX/audio adapter 只讀 committed BattleEvent；不回呼 simulation。
- RunCombatScreen 的 frame advance、500ms settle retry 與 post-commit exactly-once
  不因新 renderer 改變。
- RUN 選項 overlay 為 clone-only component；所有寫入仍經 LiveScreenIntentPort。
- Production static gate 增加正式 asset/localization 引用掃描，不削弱既有
  APP_ROUTE_FALLBACK、writer boundary、status z-order 與 accessibility 規則。

## 9. Failure policy

- Content、catalog、asset、localization、codec、migration 或 save 任一驗證錯誤
  都回 typed error，禁止部分安裝 generation。
- Migration 驗證失敗保留來源 bytes；asset／catalog 錯誤不得回退到 pilot 或 dev fake。
- 音訊 cue 缺失不得 crash；production validation 仍為阻擋，runtime 則具名靜音並
  顯示 diagnostic。

## 10. 測試與 evidence

- 每 wave 使用獨立 test 目錄與 SHA manifest，red output、green output、
  manifest read-back 均保存於 `.pipeline/content-production/`。
- Fixtures 保存原始 bytes、來源 commit、SHA-256、expected disposition；
  migration tests 不以重新 encode 的 bytes 冒充來源 fixture。
- Acceptance 聚合輸出 `artifacts/test/content-production-acceptance.json`，
  18 條 AC 各有 test/evidence path、hash、pass 與 `evidence_verified`。
