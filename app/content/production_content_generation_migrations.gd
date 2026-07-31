class_name ProductionContentGenerationMigrations
extends RefCounted

## 正式版本的 codec 2 → codec 3 generation migration 宣告表(requirements.md R1、
## R7;design.md「CGM2／CGR2 exact migration contract」)。
##
## 本檔是「宣告」而非執行期推導:哪些歷史 generation 可以升級、每個歷史 content id
## 對到哪個現行 content id,全部逐筆寫死在這裡。builder 只負責用「已安裝的 target
## generation」補上 entry digest 與 localization digest 後封裝成 pack,不得自行
## 補 mapping、不得對缺 mapping 的 id 做 identity 推定。
##
## 資料來源(逐欄抄錄,無推測):
## - 三個歷史世代的 `content_version` / `manifest_digest`:
##   `tests/fixtures/save/content_production/<commit>.schema3.codec2.json`
##   的 `run.content_snapshot`(fixture hash 由 `<commit>.sha256` 鎖定)。
## - 來源 content id 全集:同上 fixture 的 `enabled_content_ids`(三個世代完全相同
##   的 8 個 id)加上 `run.commander_id`(已含於該清單)。
## - 目標 content id:`content/packs/` 內現行正式定義的 `id`。
##
## 目標選擇理由:
## - `economy.fixture` / `meta.fixture` 的目標在正式內容中各只有唯一一筆同 category
##   的定義(`economy.slice_default`、`meta_reward_table.slice_default`),映射無選擇餘地。
## - `mapnode.fixture` 是無 kind 特徵的通用節點,對應通用戰鬥節點 `map_node.slice_normal`。
## - `commander.fixture` 是測試替身指揮官;正式內容有三名指揮官,取宣告順序第一位
##   `commander.slice_c0` 作為承接對象(此為唯一一筆帶取捨的映射)。
## - `unit.fixture` / `relic.fixture` / `effect.fixture` 在正式內容中沒有對應的承接
##   定義,宣告為 OPTIONAL TOMBSTONE:只要 active run 真的引用到它們,port 就會
##   fail-closed(design.md:304-311「被 active run 引用者必為 REQUIRED 且禁止 TOMBSTONE」)。
## - `config.combat_default` 在兩個世代同名同 category,宣告為 IDENTITY。


## 單筆宣告;`target_id` 在 TOMBSTONE 時為空。
class MappingDeclaration:
	var source_category: StringName
	var source_id: StringName
	var requirement: int
	var mapping_kind: int
	var target_id: StringName

	func _init(
		p_source_category: StringName,
		p_source_id: StringName,
		p_requirement: int,
		p_mapping_kind: int,
		p_target_id: StringName
	) -> void:
		source_category = p_source_category
		source_id = p_source_id
		requirement = p_requirement
		mapping_kind = p_mapping_kind
		target_id = p_target_id


## 可升級的歷史世代身分(allowlist key 的前兩欄)。
class SourceGeneration:
	var commit: String
	var content_version: String
	var manifest_digest: String

	func _init(
		p_commit: String,
		p_content_version: String,
		p_manifest_digest: String
	) -> void:
		commit = p_commit
		content_version = p_content_version
		manifest_digest = p_manifest_digest


static func source_generations() -> Array[SourceGeneration]:
	var result: Array[SourceGeneration] = [
		SourceGeneration.new(
			"5ddf80a",
			"0.1.0-build-lab",
			"c80e9386453436ee590f35ee1626acdf2abc464c449a68c6b6c98e9d9f1af381"
		),
		SourceGeneration.new(
			"9362e7d",
			"0.1.0-presentation-ui",
			"b24faa4944209ea90ddf6c5b65882fe47de0fcb5c053ab02017b4f45a4314ab1"
		),
		SourceGeneration.new(
			"5e78ccf",
			"0.1.0-presentation-ui",
			"ce6b1183df48d277549f592b19bf011528940790181e3fc46974dc7c565314e8"
		),
	]
	return result


## 依 (source_category bytes, source_id bytes) 升冪宣告,與 CME2 的 canonical
## 排序一致;三個歷史世代的 enabled_content_ids 完全相同,共用同一張表。
static func mapping_declarations() -> Array[MappingDeclaration]:
	var identity := ContentGenerationMigrationEntryV2.MappingKind.IDENTITY
	var alias := ContentGenerationMigrationEntryV2.MappingKind.ALIAS
	var tombstone := ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE
	var required := ContentGenerationMigrationEntryV2.Requirement.REQUIRED
	var optional := ContentGenerationMigrationEntryV2.Requirement.OPTIONAL
	var result: Array[MappingDeclaration] = [
		MappingDeclaration.new(
			&"combat_config", &"config.combat_default", required, identity,
			&"config.combat_default"
		),
		MappingDeclaration.new(
			&"commander", &"commander.fixture", required, alias,
			&"commander.slice_c0"
		),
		MappingDeclaration.new(
			&"economy_config", &"economy.fixture", required, alias,
			&"economy.slice_default"
		),
		MappingDeclaration.new(
			&"effect", &"effect.fixture", optional, tombstone, &""
		),
		MappingDeclaration.new(
			&"map_node", &"mapnode.fixture", required, alias,
			&"map_node.slice_normal"
		),
		MappingDeclaration.new(
			&"meta_reward_table", &"meta.fixture", required, alias,
			&"meta_reward_table.slice_default"
		),
		MappingDeclaration.new(
			&"relic", &"relic.fixture", optional, tombstone, &""
		),
		MappingDeclaration.new(
			&"unit", &"unit.fixture", optional, tombstone, &""
		),
	]
	return result


## 同一張宣告表推導出的 registry alias:歷史 id 在 save decode 階段(content id
## migration port)也必須解得開,否則 generation migration 成功後 decode 仍會把
## run 判為 incompatible。IDENTITY 不產生 alias(target 本身就是 active id)。
static func content_aliases() -> Array[ContentAliasValue]:
	var result: Array[ContentAliasValue] = []
	for declaration: MappingDeclaration in mapping_declarations():
		if declaration.mapping_kind \
			!= ContentGenerationMigrationEntryV2.MappingKind.ALIAS:
			continue
		result.append(ContentAliasValue.new(
			declaration.source_id, declaration.target_id
		))
	return result


## TOMBSTONE 宣告對應的 registry tombstone;policy 固定 `safe_absent`——被 active
## run 需要時 ContentRegistryMigrationAdapter 會回 incompatible,與 CGM2 的
## 「REQUIRED 不得 TOMBSTONE」同向 fail-closed。
static func content_tombstones() -> Array[ContentTombstoneValue]:
	var result: Array[ContentTombstoneValue] = []
	for declaration: MappingDeclaration in mapping_declarations():
		if declaration.mapping_kind \
			!= ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE:
			continue
		result.append(ContentTombstoneValue.new(
			declaration.source_id,
			declaration.source_category,
			&"safe_absent",
			&"",
			false,
			&"legacy_fixture_entry"
		))
	return result
