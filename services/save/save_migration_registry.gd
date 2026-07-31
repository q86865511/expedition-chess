class_name SaveMigrationRegistry
extends RefCounted

const _SCHEMA_ZERO_KEYS: Array[String] = [
	"schema_version", "content_version", "app_version", "rng_version",
	"saved_at_utc", "profile", "run",
]
const _SCHEMA_ONE_SNAPSHOT_KEYS: Array[String] = [
	"content_version", "enabled_content_ids", "economy_config_id",
	"reward_table_ids", "map_node_def_ids", "challenge_unlock_def_ids",
	"meta_reward_table_id", "manifest_digest",
]
const MIGRATION_RECEIPT_DIAGNOSTIC: StringName = &"LOAD_CONTENT_GENERATION_MIGRATED"

var _codec: SaveJsonCodec
var _generation_port: ContentGenerationMigrationPort


func _init(
	codec: SaveJsonCodec,
	generation_port: ContentGenerationMigrationPort = null
) -> void:
	_codec = codec
	_generation_port = generation_port if generation_port != null else ContentGenerationMigrationPort.new()


func migrate(raw_json_text: String) -> MigrationResult:
	var parser := JSON.new()
	if parser.parse(raw_json_text) != OK or not parser.data is Dictionary:
		return _failure(UnknownSourceSchemaVersion.new(), MigrationError.PARSE_INVALID, &"root")
	var data: Dictionary = (parser.data as Dictionary).duplicate(true)
	if not data.has("schema_version") or not _integer_value(data["schema_version"]):
		return _failure(UnknownSourceSchemaVersion.new(), MigrationError.PARSE_INVALID, &"schema_version")
	var source_schema := int(data["schema_version"])
	var known := KnownSourceSchemaVersion.new(source_schema)
	if source_schema < 0 or source_schema > SaveJsonCodec.SCHEMA_VERSION:
		return _failure(known, MigrationError.STEP_MISSING, &"schema_version")
	if source_schema == SaveJsonCodec.SCHEMA_VERSION:
		return _decode_current(raw_json_text, known)
	if source_schema == 2:
		return _upgrade_two_to_three(data, raw_json_text, known)
	if source_schema == 3:
		return _upgrade_three_to_four(data, raw_json_text, known)
	if source_schema == 0:
		var zero_error := _upgrade_zero_to_one(data)
		if not zero_error.is_empty():
			return _failure(known, MigrationError.PARSE_INVALID, zero_error)
	elif source_schema != 1:
		return _failure(known, MigrationError.STEP_MISSING, &"schema_version")
	return _upgrade_one_to_current(data, raw_json_text, known)


func _decode_current(raw_json_text: String, source_schema: SourceSchemaVersionState) -> MigrationResult:
	var decoded := _codec.decode_text(raw_json_text)
	if not decoded.ok:
		return _failure(source_schema, MigrationError.PARSE_INVALID, decoded.error.field_path)
	if decoded.run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED:
		return MigrationResult.incompatible_preserved(
			source_schema,
			raw_json_text,
			decoded.profile,
			decoded.diagnostics,
			decoded.incompatible_content_ids
		)
	if decoded.root == null:
		return _failure(source_schema, MigrationError.PARSE_INVALID, &"root")
	return MigrationResult.success(
		source_schema,
		raw_json_text,
		decoded.root,
		decoded.incompatible_content_ids,
		null,
		decoded.diagnostics
	)


func _upgrade_zero_to_one(data: Dictionary) -> StringName:
	if not _exact_keys(data, _SCHEMA_ZERO_KEYS):
		return &"root"
	data["schema_version"] = 1
	data["hash_version"] = 1
	return &""


## S5 meta-progression (design.md SS2/SS10): schema 2 lacks the three new wire
## fields ProfileState.last_selection, ProfileState.commander_challenge_records
## and RunState.discovered_content_ids. Every upgrade path that eventually
## decodes with today's codec (0->.., 1->.., 2->..) must default these fields
## onto the raw dict before decoding, since the current codec's exact-keys
## check now requires them. Idempotent: leaves already-present keys untouched.
func _default_meta_progression_fields(data: Dictionary) -> void:
	if data.get("profile") is Dictionary:
		var profile: Dictionary = data["profile"]
		if not profile.has("last_selection"):
			profile["last_selection"] = null
		if not profile.has("commander_challenge_records"):
			profile["commander_challenge_records"] = []
	if data.get("run") is Dictionary:
		var run: Dictionary = data["run"]
		if not run.has("discovered_content_ids"):
			run["discovered_content_ids"] = []

func _default_content_production_fields(
	data: Dictionary,
	default_content_codec_version: int = 2
) -> void:
	if not data.get("run") is Dictionary:
		return
	var run: Dictionary = data["run"]
	if not run.has("node_choice_receipts"):
		run["node_choice_receipts"] = []
	if run.get("content_snapshot") is Dictionary:
		var snapshot: Dictionary = run["content_snapshot"]
		if not snapshot.has("catalog_schema_version"):
			snapshot["catalog_schema_version"] = 1
		if not snapshot.has("content_codec_version"):
			snapshot["content_codec_version"] = default_content_codec_version


func _upgrade_one_to_current(
	data: Dictionary,
	original_json_text: String,
	source_schema: SourceSchemaVersionState
) -> MigrationResult:
	_default_meta_progression_fields(data)
	_default_content_production_fields(data, 1)
	var profile := _decode_profile_for_preservation(data)
	if profile == null:
		return _failure(source_schema, MigrationError.PARSE_INVALID, &"profile")
	if data.get("run") == null:
		data["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
		return _decode_and_canonicalize(data, source_schema)
	if not data["run"] is Dictionary:
		return _failure(source_schema, MigrationError.PARSE_INVALID, &"run")
	var run_data: Dictionary = data["run"]
	if not _active_run_can_change_generation(run_data):
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			MigrationError.RUN_INCOMPATIBLE_PRESERVED,
			&"run"
		)
	var request := _generation_request(run_data)
	if request == null:
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			MigrationError.GENERATION_MIGRATION_FAILED,
			&"run.content_snapshot"
		)
	var migrated := _generation_port.migrate_generation(request)
	if not migrated.ok:
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			migrated.error.code,
			migrated.error.field_path
		)
	if not _generation_result_matches(request, migrated):
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			ContentGenerationMigrationError.TARGET_MISMATCH,
			&"run.content_snapshot"
		)
	# codec 2→3 的 port 會附上套用計畫:先把 raw run 的每個引用面改寫／移除,
	# 再換 content_snapshot(design.md:304-311)。只換 snapshot 會讓 alias 過的舊 id
	# 原樣留在 run 裡,等於用一張合法 CGR2 收據夾帶未遷移的引用。
	if migrated.migration_receipt is ContentGenerationMigrationReceiptV2 \
		and not _apply_generation_plan(run_data, migrated.plan):
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			ContentGenerationMigrationError.MAPPING_INVALID,
			&"run"
		)
	_apply_target_receipt(data, run_data, migrated.target_receipt)
	var decoded := _decode_candidate(data)
	if not decoded.ok or decoded.root == null:
		var path := decoded.error.field_path if decoded.error != null else &"root"
		return _incompatible(
			source_schema,
			original_json_text,
			profile,
			ContentGenerationMigrationError.TARGET_MISMATCH,
			path
		)
	var encoded := _codec.encode(decoded.root)
	if not encoded.ok:
		return _failure(source_schema, MigrationError.PARSE_INVALID, encoded.error.field_path)
	var receipt_values: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"receipt_digest", migrated.migration_receipt.receipt_digest),
		DiagnosticValue.from_string(&"target_manifest_digest", migrated.migration_receipt.target_manifest_digest),
	]
	var diagnostics: Array[LoadDiagnostic] = [
		LoadDiagnostic.new(MIGRATION_RECEIPT_DIAGNOSTIC, &"run.content_snapshot", receipt_values),
	]
	return MigrationResult.success(
		source_schema,
		encoded.json_text.value,
		decoded.root,
		[],
		migrated.migration_receipt,
		diagnostics
	)


## S5 meta-progression (design.md SS2/SS10, REQ-SAVE-003): pure structural
## upgrade -- schema 2->3 only adds the three new wire fields (defaulted by
## _default_meta_progression_fields), it does not touch content_snapshot shape
## or require any content-generation migration (that is a separate axis,
## handled via catalog lease at load time -- see design.md SS13). Mirrors
## _decode_current's handling of an incompatible active run (profile
## preserved, run dropped) rather than _decode_and_canonicalize's, because
## unlike that helper's original (run==null-only) call site, a schema-2 input
## here may carry a real active run whose content_snapshot no longer matches
## the currently pinned receipt.
func _upgrade_two_to_three(
	data: Dictionary,
	original_json_text: String,
	source_schema: SourceSchemaVersionState
) -> MigrationResult:
	_default_meta_progression_fields(data)
	_default_content_production_fields(data)
	var decoded := _decode_candidate(data)
	if decoded.run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED:
		return MigrationResult.incompatible_preserved(
			source_schema,
			original_json_text,
			decoded.profile,
			decoded.diagnostics,
			decoded.incompatible_content_ids
		)
	if not decoded.ok or decoded.root == null:
		var path := decoded.error.field_path if decoded.error != null else &"root"
		return _failure(source_schema, MigrationError.PARSE_INVALID, path)
	var encoded := _codec.encode(decoded.root)
	if not encoded.ok:
		return _failure(source_schema, MigrationError.PARSE_INVALID, encoded.error.field_path)
	return MigrationResult.success(
		source_schema,
		encoded.json_text.value,
		decoded.root,
		decoded.incompatible_content_ids,
		null,
		decoded.diagnostics
	)

func _upgrade_three_to_four(
	data: Dictionary,
	original_json_text: String,
	source_schema: SourceSchemaVersionState
) -> MigrationResult:
	_default_content_production_fields(data)
	if data.get("run") == null:
		data["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
		return _decode_and_canonicalize(data, source_schema)
	return _upgrade_one_to_current(
		data, original_json_text, source_schema
	)


func _decode_profile_for_preservation(data: Dictionary) -> ProfileState:
	var profile_only := data.duplicate(true)
	profile_only["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
	profile_only["run"] = null
	var decoded := _codec._decode_root(profile_only)
	return decoded.profile if decoded.ok else null


func _decode_and_canonicalize(
	data: Dictionary,
	source_schema: SourceSchemaVersionState
) -> MigrationResult:
	var decoded := _decode_candidate(data)
	if not decoded.ok or decoded.root == null:
		var path := decoded.error.field_path if decoded.error != null else &"root"
		return _failure(source_schema, MigrationError.PARSE_INVALID, path)
	var encoded := _codec.encode(decoded.root)
	if not encoded.ok:
		return _failure(source_schema, MigrationError.PARSE_INVALID, encoded.error.field_path)
	return MigrationResult.success(
		source_schema,
		encoded.json_text.value,
		decoded.root,
		decoded.incompatible_content_ids,
		null,
		decoded.diagnostics
	)


func _decode_candidate(data: Dictionary) -> SaveDecodeResult:
	data["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
	return _codec._decode_root(data)


func _active_run_can_change_generation(run_data: Dictionary) -> bool:
	if run_data.get("run_phase") != "MAP" or run_data.get("current_node_id") != null:
		return false
	var resolution: Variant = run_data.get("resolution_state")
	if not resolution is Dictionary or (resolution as Dictionary).get("kind") != "idle":
		return false
	var map_value: Variant = run_data.get("map_state")
	if not map_value is Dictionary:
		return false
	var map_data: Dictionary = map_value
	if map_data.get("current_node_id") != null:
		return false
	var nodes_value: Variant = map_data.get("nodes")
	if not nodes_value is Array:
		return false
	for node_value: Variant in nodes_value:
		if not node_value is Dictionary or (node_value as Dictionary).get("encounter_preview") != null:
			return false
	return true


func _generation_request(run_data: Dictionary) -> ContentGenerationMigrationRequest:
	var snapshot_value: Variant = run_data.get("content_snapshot")
	if not snapshot_value is Dictionary:
		return null
	var snapshot: Dictionary = snapshot_value
	var allowed_keys := _SCHEMA_ONE_SNAPSHOT_KEYS.duplicate()
	allowed_keys.append("catalog_schema_version")
	allowed_keys.append("content_codec_version")
	if int(snapshot.get("content_codec_version", 0)) >= 2:
		allowed_keys.append("combat_config_id")
	if not _exact_keys(snapshot, allowed_keys):
		return null
	for scalar_key: String in [
		"content_version", "economy_config_id", "meta_reward_table_id", "manifest_digest"
	]:
		if not snapshot.get(scalar_key) is String:
			return null
	var enabled: Variant = _name_array(snapshot.get("enabled_content_ids"))
	var rewards: Variant = _name_array(snapshot.get("reward_table_ids"))
	var nodes: Variant = _name_array(snapshot.get("map_node_def_ids"))
	var challenges: Variant = _name_array(snapshot.get("challenge_unlock_def_ids"))
	if enabled == null or rewards == null or nodes == null or challenges == null:
		return null
	var sites_value: Variant = _reference_sites(run_data, snapshot)
	if sites_value == null:
		return null
	var sites: Array = sites_value
	return ContentGenerationMigrationRequest.new(
		snapshot["content_version"],
		snapshot["manifest_digest"],
		enabled,
		StringName(snapshot["economy_config_id"]),
		rewards,
		nodes,
		challenges,
		StringName(snapshot["meta_reward_table_id"]),
		int(snapshot["catalog_schema_version"]),
		int(snapshot["content_codec_version"]),
		_references_from_sites(sites)
	)


## 單一 content 引用點:除了交給 port 的 typed reference 之外,還記住「它住在哪個
## 容器的哪個位置」,讓 generation migration 成功後可以就地改寫。收集與改寫共用
## 同一支 `_reference_sites()`,兩者結構上不可能漂移(codex B4 指出的漏改寫)。
class _ReferenceSite:
	## Dictionary(key 為欄位名 String)或 Array(key 為索引 int)。
	var container: Variant
	var key: Variant
	var reference: ContentGenerationMigrationReference
	## true = 位在可移除元素的集合型欄位(只有 run.discovered_content_ids)。
	var removable: bool

	func _init(
		p_container: Variant,
		p_key: Variant,
		p_reference: ContentGenerationMigrationReference,
		p_removable: bool
	) -> void:
		container = p_container
		key = p_key
		reference = p_reference
		removable = p_removable


func _references_from_sites(
	sites: Array
) -> Array[ContentGenerationMigrationReference]:
	var result: Array[ContentGenerationMigrationReference] = []
	for site: _ReferenceSite in sites:
		result.append(site.reference.deep_clone())
	return result


## design.md:304-311 要求 generation migration 逐一走訪 ContentSnapshot、
## board/bench/pool、equipment/inventory/overflow、relics、commander、
## map/current node/preview、ResolutionState、reservation 與
## transaction/claim/receipt。這裡把 raw run dictionary 上的每個 content 引用
## 翻成 typed reference 交給 port;port 依此要求 pack 有 exact mapping。
## 形狀不符即回 null(呼叫端轉成 GENERATION_MIGRATION_FAILED),不做寬鬆略過。
##
## instance id(bench／inventory／overflow／board placement)不是 content id,
## 由 unit_instances／item_instances 的 def_id 代表;item def 的 category 在 save
## 上無法區分 equipment 與 item_component,以空 category 交給 port 做唯一比對。
##
## ledger_bound 的引用面(claim receipt 的 effect_id、node choice receipt 的
## choice_set_id／choice_id)其 id 已進了 runtime key／receipt digest 的 preimage,
## 改名會讓已簽的 exactly-once 憑證與內容不符,且無法在此重算;因此 port 只允許
## 這些位置對到 IDENTITY,其餘一律 fail-closed(不是靜默保留舊 id)。
func _reference_sites(run_data: Dictionary, snapshot: Dictionary) -> Variant:
	var sites: Array = []
	_append_site(
		sites, snapshot, "economy_config_id", &"economy_config",
		&"run.content_snapshot.economy_config_id", true, false, false
	)
	if snapshot.has("combat_config_id"):
		_append_site(
			sites, snapshot, "combat_config_id", &"combat_config",
			&"run.content_snapshot.combat_config_id", true, false, false
		)
	_append_site(
		sites, snapshot, "meta_reward_table_id", &"meta_reward_table",
		&"run.content_snapshot.meta_reward_table_id", true, false, false
	)
	if not _append_array_sites(
		sites, snapshot.get("reward_table_ids"), &"reward_table",
		&"run.content_snapshot.reward_table_ids", true, false, false
	) or not _append_array_sites(
		sites, snapshot.get("map_node_def_ids"), &"map_node",
		&"run.content_snapshot.map_node_def_ids", true, false, false
	) or not _append_array_sites(
		sites, snapshot.get("challenge_unlock_def_ids"), &"unlock",
		&"run.content_snapshot.challenge_unlock_def_ids", true, false, false
	):
		return null
	_append_site(
		sites, run_data, "commander_id", &"commander", &"run.commander_id",
		true, false, false
	)
	# codex/collection 面:OPTIONAL TOMBSTONE 在這裡是「移除」而不是保留舊 id。
	if not _append_array_sites(
		sites, run_data.get("discovered_content_ids"), &"",
		&"run.discovered_content_ids", false, true, false
	):
		return null
	if not _append_record_sites(
		sites, run_data.get("map_state"), "nodes", "def_id", &"map_node",
		&"run.map_state.nodes.def_id"
	):
		return null
	var roster_value: Variant = run_data.get("roster_state")
	if roster_value != null and not roster_value is Dictionary:
		return null
	var roster: Dictionary = roster_value if roster_value is Dictionary else {}
	if not _append_element_sites(
		sites, roster.get("unit_instances"), "def_id", &"unit",
		&"run.roster_state.unit_instances.def_id"
	) or not _append_element_sites(
		sites, roster.get("item_instances"), "def_id", &"",
		&"run.roster_state.item_instances.def_id"
	) or not _append_element_sites(
		sites, roster.get("active_relic_slots"), "relic_id", &"relic",
		&"run.roster_state.active_relic_slots.relic_id"
	):
		return null
	if not _append_record_sites(
		sites, run_data.get("unit_pool_state"), "entries", "unit_def_id",
		&"unit", &"run.unit_pool_state.entries.unit_def_id"
	):
		return null
	if not _append_record_sites(
		sites, run_data.get("economy_state"), "shop_offers", "unit_def_id",
		&"unit", &"run.economy_state.shop_offers.unit_def_id"
	):
		return null
	if not _append_element_sites(
		sites, run_data.get("reservation_owners"), "unit_def_id", &"unit",
		&"run.reservation_owners.unit_def_id"
	):
		return null
	if not _append_nested_sites(
		sites, run_data.get("claim_receipts"), "key", "effect_id", &"effect",
		&"run.claim_receipts.key.effect_id"
	):
		return null
	if not _append_nested_sites(
		sites, run_data.get("node_choice_receipts"), "receipt",
		"choice_set_id", &"node_choice_set",
		&"run.node_choice_receipts.receipt.choice_set_id"
	) or not _append_nested_sites(
		sites, run_data.get("node_choice_receipts"), "receipt", "choice_id",
		&"", &"run.node_choice_receipts.receipt.choice_id"
	):
		return null
	return sites


func _append_site(
	sites: Array,
	container: Variant,
	key: Variant,
	category: StringName,
	field_path: StringName,
	structural: bool,
	removable: bool,
	ledger_bound: bool
) -> void:
	var value: Variant = (
		(container as Dictionary).get(key)
		if container is Dictionary
		else (container as Array)[key]
	)
	if not value is String or (value as String).is_empty():
		return
	sites.append(_ReferenceSite.new(
		container,
		key,
		ContentGenerationMigrationReference.new(
			category, StringName(value), field_path, structural, ledger_bound
		),
		removable
	))


func _append_array_sites(
	sites: Array,
	value: Variant,
	category: StringName,
	field_path: StringName,
	structural: bool,
	removable: bool,
	ledger_bound: bool
) -> bool:
	if value == null:
		return true
	if not value is Array:
		return false
	var values: Array = value
	for index: int in values.size():
		if not values[index] is String:
			return false
		_append_site(
			sites, values, index, category, field_path, structural, removable,
			ledger_bound
		)
	return true


func _append_element_sites(
	sites: Array,
	value: Variant,
	field: String,
	category: StringName,
	field_path: StringName
) -> bool:
	if value == null:
		return true
	if not value is Array:
		return false
	for entry: Variant in (value as Array):
		if not entry is Dictionary:
			return false
		var data: Dictionary = entry
		var content_id: Variant = data.get(field)
		if content_id == null:
			continue
		if not content_id is String:
			return false
		_append_site(sites, data, field, category, field_path, true, false, false)
	return true


func _append_record_sites(
	sites: Array,
	value: Variant,
	array_field: String,
	field: String,
	category: StringName,
	field_path: StringName
) -> bool:
	if value == null:
		return true
	if not value is Dictionary:
		return false
	return _append_element_sites(
		sites, (value as Dictionary).get(array_field), field, category,
		field_path
	)


## `claim_receipts[].key.effect_id`、`node_choice_receipts[].receipt.choice_*`
## 這種「陣列 → 巢狀物件 → 欄位」的引用面;一律標記 ledger_bound。
func _append_nested_sites(
	sites: Array,
	value: Variant,
	nested_field: String,
	field: String,
	category: StringName,
	field_path: StringName
) -> bool:
	if value == null:
		return true
	if not value is Array:
		return false
	for entry: Variant in (value as Array):
		if not entry is Dictionary:
			return false
		var nested: Variant = (entry as Dictionary).get(nested_field)
		if nested == null:
			continue
		if not nested is Dictionary:
			return false
		var data: Dictionary = nested
		var content_id: Variant = data.get(field)
		if content_id == null:
			continue
		if not content_id is String:
			return false
		_append_site(sites, data, field, category, field_path, true, false, true)
	return true


## generation migration 成功後、重編碼／重驗之前,依 pack 的 mapping 就地改寫
## raw run 的每一個引用面(design.md:304-311)。ALIAS → 改寫成 target id;
## OPTIONAL TOMBSTONE → 從可移除的集合型欄位移除;結構性位置的 TOMBSTONE 與
## ledger-bound 位置的改名在 port 已 fail-closed,這裡再守一次。
## 回 false 代表無法安全套用,呼叫端轉 incompatible-preserved(不交換原 bytes)。
func _apply_generation_plan(
	run_data: Dictionary,
	plan: ContentGenerationMigrationPlan
) -> bool:
	if plan == null:
		return false
	var snapshot_value: Variant = run_data.get("content_snapshot")
	if not snapshot_value is Dictionary:
		return false
	var sites_value: Variant = _reference_sites(run_data, snapshot_value)
	if sites_value == null:
		return false
	var removals: Array = []
	for site: _ReferenceSite in (sites_value as Array):
		var mapping := plan.try_resolve(site.reference)
		if mapping == null:
			return false
		if mapping.mapping_kind \
			== ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE:
			if site.reference.structural or not site.removable:
				return false
			removals.append(site)
			continue
		if mapping.target_id == String(site.reference.content_id):
			continue
		if site.reference.ledger_bound:
			return false
		if site.container is Dictionary:
			(site.container as Dictionary)[site.key] = mapping.target_id
		else:
			(site.container as Array)[site.key] = mapping.target_id
	if not _remove_sites(removals):
		return false
	return _renormalize_after_rewrite(run_data)


## 只有 Array 容器可以移除元素;同一個容器內由大到小刪,避免索引位移。
func _remove_sites(removals: Array) -> bool:
	var containers: Array = []
	var indexes_by_container: Array = []
	for site: _ReferenceSite in removals:
		if not site.container is Array:
			return false
		# Array 的 `==` 是逐元素比較,不能用 find() 認容器;必須比參考同一性。
		var position := -1
		for index: int in containers.size():
			if is_same(containers[index], site.container):
				position = index
				break
		if position < 0:
			containers.append(site.container)
			indexes_by_container.append([site.key])
		else:
			(indexes_by_container[position] as Array).append(site.key)
	for position: int in containers.size():
		var indexes: Array = indexes_by_container[position]
		indexes.sort()
		indexes.reverse()
		var target: Array = containers[position]
		for index: int in indexes:
			target.remove_at(index)
	return true


## 改寫可能破壞兩個「依 content id 排序且唯一」的不變量
## (RunStateValidator 的 `run.discovered_content_ids` 與 `run.unit_pool_state.entries`)。
## pack 已保證 target 不重複(codec 的 target 唯一性檢查),所以這裡只需重排;
## 若仍出現重複代表 pack 與 run 不相容,回 false 而非合併。
func _renormalize_after_rewrite(run_data: Dictionary) -> bool:
	var discovered: Variant = run_data.get("discovered_content_ids")
	if discovered is Array:
		var values: Array = discovered
		var sorted_values: Array = values.duplicate()
		sorted_values.sort()
		for index: int in sorted_values.size():
			if index > 0 and sorted_values[index] == sorted_values[index - 1]:
				return false
		values.clear()
		values.append_array(sorted_values)
	var pool_value: Variant = run_data.get("unit_pool_state")
	if not pool_value is Dictionary:
		return true
	var entries_value: Variant = (pool_value as Dictionary).get("entries")
	if not entries_value is Array:
		return true
	var entries: Array = entries_value
	var sorted_entries: Array = entries.duplicate()
	sorted_entries.sort_custom(_pool_entry_less)
	for index: int in sorted_entries.size():
		if index == 0:
			continue
		if _pool_entry_id(sorted_entries[index]) \
			== _pool_entry_id(sorted_entries[index - 1]):
			return false
	entries.clear()
	entries.append_array(sorted_entries)
	return true


func _pool_entry_id(value: Variant) -> String:
	if not value is Dictionary:
		return ""
	var id_value: Variant = (value as Dictionary).get("unit_def_id")
	return String(id_value) if id_value is String else ""


func _pool_entry_less(left: Variant, right: Variant) -> bool:
	return _pool_entry_id(left) < _pool_entry_id(right)


func _generation_result_matches(
	request: ContentGenerationMigrationRequest,
	result: ContentGenerationMigrationResult
) -> bool:
	if result == null or not result.ok or result.target_receipt == null \
		or result.migration_receipt == null:
		return false
	var receipt: RefCounted = result.migration_receipt
	if receipt is ContentGenerationMigrationReceiptV2:
		var receipt_v2 := receipt as ContentGenerationMigrationReceiptV2
		return request.source_catalog_schema_version == 1 \
			and request.source_content_codec_version == 2 \
			and receipt_v2.source_manifest_digest == request.source_manifest_digest \
			and receipt_v2.target_manifest_digest \
				== result.target_receipt.manifest_digest \
			and receipt_v2.source_catalog_schema_version == 1 \
			and receipt_v2.target_catalog_schema_version == 2 \
			and receipt_v2.from_codec == 2 \
			and receipt_v2.to_codec == 3 \
			and result.target_receipt.catalog_schema_version == 2 \
			and result.target_receipt.content_codec_version == 3
	if not receipt is ContentGenerationMigrationReceipt:
		return false
	var receipt_v1 := receipt as ContentGenerationMigrationReceipt
	return request.source_content_codec_version == 1 \
		and receipt_v1.source_manifest_digest == request.source_manifest_digest \
		and receipt_v1.target_manifest_digest \
			== result.target_receipt.manifest_digest \
		and receipt_v1.from_codec == 1 \
		and receipt_v1.to_codec == 2 \
		and result.target_receipt.content_codec_version == 2


func _apply_target_receipt(
	root_data: Dictionary,
	run_data: Dictionary,
	receipt: PinnedCatalogBuildReceipt
) -> void:
	root_data["schema_version"] = SaveJsonCodec.SCHEMA_VERSION
	root_data["content_version"] = receipt.content_version
	var snapshot: Dictionary = run_data["content_snapshot"]
	snapshot["content_version"] = receipt.content_version
	snapshot["enabled_content_ids"] = _strings(receipt.active_entry_ids)
	snapshot["economy_config_id"] = String(receipt.economy_config_id)
	snapshot["reward_table_ids"] = _strings(receipt.reward_table_ids)
	snapshot["map_node_def_ids"] = _strings(receipt.map_node_def_ids)
	snapshot["challenge_unlock_def_ids"] = _strings(receipt.challenge_unlock_def_ids)
	snapshot["meta_reward_table_id"] = String(receipt.meta_reward_table_id)
	snapshot["manifest_digest"] = receipt.manifest_digest
	snapshot["catalog_schema_version"] = receipt.catalog_schema_version
	snapshot["content_codec_version"] = receipt.content_codec_version
	if not run_data.has("node_choice_receipts"):
		run_data["node_choice_receipts"] = []
	if _has_property(receipt, &"combat_config_id"):
		snapshot["combat_config_id"] = String(receipt.get("combat_config_id"))


func _name_array(value: Variant) -> Variant:
	if not value is Array:
		return null
	var output: Array[StringName] = []
	for item: Variant in value:
		if not item is String:
			return null
		output.append(StringName(item))
	return output


func _strings(values: Array[StringName]) -> Array[String]:
	var output: Array[String] = []
	for value: StringName in values:
		output.append(String(value))
	return output


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _exact_keys(data: Dictionary, expected: Array[String]) -> bool:
	if data.size() != expected.size():
		return false
	for key: String in expected:
		if not data.has(key):
			return false
	return true


func _integer_value(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and floor(value) == value)


func _incompatible(
	source_schema: SourceSchemaVersionState,
	original_json_text: String,
	profile: ProfileState,
	code: StringName,
	path: StringName
) -> MigrationResult:
	var diagnostics: Array[LoadDiagnostic] = [LoadDiagnostic.new(code, path)]
	return MigrationResult.incompatible_preserved(
		source_schema,
		original_json_text,
		profile,
		diagnostics
	)


func _failure(
	source_schema: SourceSchemaVersionState,
	code: StringName,
	path: StringName
) -> MigrationResult:
	return MigrationResult.failure(source_schema, MigrationError.new(code, path))
