class_name ContentGenerationMigrationTranscoder
extends RefCounted

var _v2 := ContentCanonicalCodecV2.new()
var _stable_ids := StableIdValidator.new()
var _error: ContentGenerationMigrationError
var _mapping_by_identity: Dictionary = {}

func build(
	source: ContentCatalogSnapshot,
	request: ContentGenerationMigrationRequest,
	target_content_version: String,
	combat_config_entry_bytes: PackedByteArray,
	boss_mapping_entries: Array[BossSourceMigrationEntryV1]
) -> ContentGenerationMigrationDraftResult:
	_error = null
	_mapping_by_identity.clear()
	if source == null or source.manifest == null or request == null \
		or target_content_version.is_empty():
		return _failure(
			ContentGenerationMigrationError.SOURCE_CATALOG_INVALID,
			&"source_catalog"
		)
	if source.manifest.content_version != request.source_content_version \
		or source.manifest_digest != request.source_manifest_digest:
		return _failure(
			ContentGenerationMigrationError.SOURCE_MISMATCH,
			&"source_manifest_digest"
		)
	var config_entry := _decode_combat_config(combat_config_entry_bytes)
	if config_entry == null:
		return _failure_from_state(
			ContentGenerationMigrationError.CONFIG_INVALID,
			&"migration_pack.combat_config_entry_bytes"
		)
	if not _validate_boss_mapping(source, boss_mapping_entries):
		return _failure_from_state(
			ContentGenerationMigrationError.MAPPING_INVALID,
			&"migration_pack.boss_mapping_entries"
		)
	var selection := _mapped_selection(
		source,
		request,
		target_content_version
	)
	if selection == null:
		return _failure_from_state(
			ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
			&"request.enabled_content_ids"
		)
	var source_ids: Array[StringName] = []
	for entry: ContentEntryValue in source.entries:
		source_ids.append(entry.content_id)
	source_ids.sort_custom(_name_less)
	var active_ids: Array[StringName] = source_ids.duplicate()
	active_ids.append(&"config.combat_default")
	active_ids.sort_custom(_name_less)
	if _has_duplicate(active_ids):
		return _failure(
			ContentGenerationMigrationError.CONFIG_INVALID,
			&"config.combat_default"
		)
	var entries: Array[ContentEntryValue] = []
	for source_entry: ContentEntryValue in source.entries:
		var transcoded := _transcode_entry(source_entry)
		if transcoded == null:
			return _failure_from_state(
				ContentGenerationMigrationError.SOURCE_CATALOG_INVALID,
				&"source_catalog.entries"
			)
		entries.append(transcoded)
	entries.append(config_entry)
	entries.sort_custom(_entry_less)
	var entry_bytes: Array[PackedByteArray] = []
	var indexes: Array[ContentEntryIndexValue] = []
	for entry: ContentEntryValue in entries:
		var encoded := _v2.encode_entry(entry)
		if not encoded.ok:
			return _failure(
				ContentGenerationMigrationError.SOURCE_CATALOG_INVALID,
				StringName("target_entry.%s" % String(entry.content_id))
			)
		entry_bytes.append(encoded.canonical_bytes)
		indexes.append(ContentEntryIndexValue.new(
			entry.category,
			entry.content_id,
			entry.resource_schema_version,
			_v2.sha256_bytes(encoded.canonical_bytes)
		))
	var manifest := ContentManifestValue.new()
	manifest.catalog_schema_version = 1
	manifest.content_version = target_content_version
	manifest.pack_ids = source.manifest.pack_ids.duplicate()
	for alias: ContentAliasValue in source.manifest.aliases:
		manifest.aliases.append(alias.deep_clone())
	for tombstone: ContentTombstoneValue in source.manifest.tombstones:
		manifest.tombstones.append(tombstone.deep_clone())
	manifest.entry_indexes = indexes
	var manifest_encoded := _v2.encode_manifest(manifest)
	if not manifest_encoded.ok:
		return _failure(
			ContentGenerationMigrationError.SOURCE_CATALOG_INVALID,
			&"target_manifest"
		)
	var digest_bytes := _v2.sha256_bytes(manifest_encoded.canonical_bytes)
	var digest := digest_bytes.hex_encode()
	var catalog_encoded := _v2.encode_catalog(
		digest_bytes,
		manifest_encoded.canonical_bytes,
		entry_bytes
	)
	if not catalog_encoded.ok:
		return _failure(
			ContentGenerationMigrationError.SOURCE_CATALOG_INVALID,
			&"target_catalog"
		)
	var snapshot := ContentCatalogSnapshot.new()
	snapshot.manifest = manifest.deep_clone()
	snapshot.manifest_bytes = manifest_encoded.canonical_bytes.duplicate()
	snapshot.manifest_digest = digest
	for entry: ContentEntryValue in entries:
		snapshot.entries.append(entry.deep_clone())
	for bytes: PackedByteArray in entry_bytes:
		snapshot.entry_bytes.append(bytes.duplicate())
	snapshot.diagnostic_catalog_bytes = catalog_encoded.canonical_bytes.duplicate()
	return ContentGenerationMigrationDraftResult.success(
		snapshot,
		selection,
		active_ids
	)

func _decode_combat_config(bytes: PackedByteArray) -> ContentEntryValue:
	var decoded := _v2.decode_entry(bytes)
	if not decoded.ok or decoded.entry == null \
		or decoded.entry.category != &"combat_config" \
		or decoded.entry.content_id != &"config.combat_default" \
		or not _combat_config_values_valid(decoded.entry.payload):
		_error = ContentGenerationMigrationError.new(
			ContentGenerationMigrationError.CONFIG_INVALID,
			&"migration_pack.combat_config_entry_bytes"
		)
		return null
	return decoded.entry.deep_clone()

func _combat_config_values_valid(payload: ContentValue) -> bool:
	if payload == null or payload.record_type != ContentCategory.COMBAT_CONFIG \
		or payload.children.size() != 32:
		return false
	var values: Array[int] = []
	for index: int in range(3, payload.children.size()):
		values.append(payload.children[index].int_value)
	var fixed_values := PackedInt32Array([
		1, 20, 8, 8, 1200, 1800, 1000, 100, 10000, 20, 1,
	])
	for index: int in fixed_values.size():
		if values[index] != fixed_values[index]:
			return false
	return values[11] >= 0 and values[11] <= 100 \
		and values[12] >= 1 and values[12] <= 100 \
		and values[13] >= 0 and values[14] <= 100 and values[13] <= values[14] \
		and values[15] >= 1 and values[15] <= 1000 \
		and values[16] >= values[15] and values[16] <= 10000 \
		and values[17] >= 1 and values[17] <= 100 \
		and values[18] >= 1 and values[18] <= 100 \
		and values[19] >= 1 and values[19] <= 100 \
		and values[20] >= 0 and values[20] <= 100 \
		and values[21] >= 0 and values[21] <= 100 \
		and values[22] >= 64 and values[22] <= 65535 \
		and values[23] >= values[22] and values[23] <= 65535 \
		and values[24] >= 64 and values[24] <= 65535 \
		and values[25] >= 64 and values[25] <= 1024 \
		and values[26] == 10000 \
		and values[27] >= 1 and values[27] <= 100000 \
		and values[28] >= 1 and values[28] <= 100000

func _validate_boss_mapping(
	source: ContentCatalogSnapshot,
	entries: Array[BossSourceMigrationEntryV1]
) -> bool:
	if ContentGenerationMigrationCodec.new().boss_mapping_bytes(entries).is_empty():
		_error = ContentGenerationMigrationError.new(
			ContentGenerationMigrationError.MAPPING_INVALID,
			&"migration_pack.boss_mapping_entries"
		)
		return false
	var expected: Array[String] = []
	var spawn_keys_by_encounter: Dictionary = {}
	for entry: ContentEntryValue in source.entries:
		if entry.category != &"encounter": continue
		if entry.payload == null or entry.payload.record_type != ContentCategory.ENCOUNTER \
			or entry.payload.children.size() != 8:
			return _mapping_error(&"source_catalog.encounter")
		var spawn_counts: Dictionary = {}
		for spawn: ContentValue in entry.payload.children[5].children:
			if spawn == null or spawn.record_type != 0x2006 \
				or spawn.children.size() != 7:
				return _mapping_error(&"source_catalog.enemy_spawns")
			var spawn_key := spawn.children[3].string_value
			spawn_counts[spawn_key] = int(spawn_counts.get(spawn_key, 0)) + 1
		spawn_keys_by_encounter[entry.content_id] = spawn_counts
		for phase: ContentValue in entry.payload.children[7].children:
			if phase == null or phase.record_type != 0x2007 \
				or phase.children.size() != 3:
				return _mapping_error(&"source_catalog.boss_phases")
			expected.append(_phase_identity(
				entry.content_id,
				phase.children[0].int_value
			))
	expected.sort()
	if expected.size() != entries.size():
		return _mapping_error(&"migration_pack.boss_mapping_entries.count")
	for index: int in range(entries.size()):
		var mapping: BossSourceMigrationEntryV1 = entries[index]
		var identity := _phase_identity(mapping.encounter_id, mapping.phase_index)
		if identity != expected[index] \
			or not spawn_keys_by_encounter.has(mapping.encounter_id):
			return _mapping_error(&"migration_pack.boss_mapping_entries.identity")
		var counts: Dictionary = spawn_keys_by_encounter[mapping.encounter_id]
		if int(counts.get(mapping.source_spawn_key, 0)) != 1:
			return _mapping_error(&"migration_pack.boss_mapping_entries.source_spawn_key")
		_mapping_by_identity[identity] = mapping.source_spawn_key
	return true

func _mapped_selection(
	source: ContentCatalogSnapshot,
	request: ContentGenerationMigrationRequest,
	target_content_version: String
) -> CatalogSelection:
	var mapped_enabled := _map_required_ids(
		source,
		request.enabled_content_ids,
		&"",
		&"request.enabled_content_ids"
	)
	if _error != null: return null
	var source_ids: Array[StringName] = []
	for entry: ContentEntryValue in source.entries: source_ids.append(entry.content_id)
	source_ids.sort_custom(_name_less)
	if mapped_enabled != source_ids:
		_error = ContentGenerationMigrationError.new(
			ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
			&"request.enabled_content_ids"
		)
		return null
	var economy := _resolve_required(
		source,
		request.economy_config_id,
		&"economy_config",
		&"request.economy_config_id"
	)
	var meta := _resolve_required(
		source,
		request.meta_reward_table_id,
		&"meta_reward_table",
		&"request.meta_reward_table_id"
	)
	var rewards := _map_required_ids(
		source,
		request.reward_table_ids,
		&"reward_table",
		&"request.reward_table_ids"
	)
	var maps := _map_required_ids(
		source,
		request.map_node_def_ids,
		&"map_node",
		&"request.map_node_def_ids"
	)
	var challenges := _map_required_ids(
		source,
		request.challenge_unlock_def_ids,
		&"unlock",
		&"request.challenge_unlock_def_ids"
	)
	if _error != null or economy == null or meta == null:
		return null
	var required_ids: Array[StringName] = []
	required_ids.append_array(rewards)
	required_ids.append_array(maps)
	required_ids.append_array(challenges)
	for required_id: StringName in required_ids:
		if not mapped_enabled.has(required_id):
			_error = ContentGenerationMigrationError.new(
				ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
				&"request.selection"
			)
			return null
	if not mapped_enabled.has(economy.resolved_id) \
		or not mapped_enabled.has(meta.resolved_id):
		_error = ContentGenerationMigrationError.new(
			ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
			&"request.selection"
		)
		return null
	return CatalogSelection.new(
		target_content_version,
		mapped_enabled,
		economy.resolved_id,
		&"config.combat_default",
		rewards,
		maps,
		challenges,
		meta.resolved_id
	)

func _map_required_ids(
	source: ContentCatalogSnapshot,
	values: Array[StringName],
	expected_category: StringName,
	path: StringName
) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: StringName in values:
		var resolved := _resolve_required(source, value, expected_category, path)
		if resolved == null: return []
		result.append(resolved.resolved_id)
	result.sort_custom(_name_less)
	if _has_duplicate(result):
		_error = ContentGenerationMigrationError.new(
			ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
			path
		)
		return []
	return result

func _resolve_required(
	source: ContentCatalogSnapshot,
	content_id: StringName,
	expected_category: StringName,
	path: StringName
) -> ContentMigrationLookup:
	if not _stable_ids.is_valid(content_id):
		return _selection_error(path)
	var cursor := content_id
	var aliased := false
	var visited: Dictionary = {}
	while true:
		if visited.has(cursor): return _selection_error(path)
		visited[cursor] = true
		var active := source._find_entry(cursor)
		if active != null:
			if not expected_category.is_empty() \
				and active.category != expected_category:
				return _selection_error(path)
			return ContentMigrationLookup.alias(active.category, cursor) \
				if aliased else ContentMigrationLookup.active(active.category, cursor)
		for tombstone: ContentTombstoneValue in source.manifest.tombstones:
			if tombstone.original_id == cursor:
				return _selection_error(path)
		var target := StringName("")
		for alias: ContentAliasValue in source.manifest.aliases:
			if alias.source_id == cursor:
				target = alias.target_id
				break
		if target.is_empty(): return _selection_error(path)
		cursor = target
		aliased = true
	return null

func _selection_error(path: StringName) -> ContentMigrationLookup:
	_error = ContentGenerationMigrationError.new(
		ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
		path
	)
	return null

func _transcode_entry(source: ContentEntryValue) -> ContentEntryValue:
	if source == null or source.payload == null: return null
	var payload := source.payload.deep_clone()
	match source.category:
		&"unit":
			if payload.children.size() != 12: return null
			var empty_effects: Array[ContentValue] = []
			payload.children.append(ContentValue.ordered_list(empty_effects))
			payload.field_ids = _top_level_field_ids(payload.children.size())
		&"effect":
			if payload.children.size() != 11: return null
			if StringName(payload.children[4].string_value) == &"periodic":
				_error = ContentGenerationMigrationError.new(
					ContentGenerationMigrationError.SOURCE_CATALOG_INVALID,
					&"source_catalog.effect.periodic_interval_ticks"
				)
				return null
			payload.children.insert(5, ContentValue.u32(0))
			payload.field_ids = _top_level_field_ids(payload.children.size())
		&"encounter":
			if payload.children.size() != 8: return null
			var phases: Array[ContentValue] = []
			for phase: ContentValue in payload.children[7].children:
				if phase == null or phase.children.size() != 3: return null
				var identity := _phase_identity(
					source.content_id,
					phase.children[0].int_value
				)
				if not _mapping_by_identity.has(identity): return null
				phases.append(ContentValue.record(
					0x2007,
					PackedInt32Array([1, 2, 3, 4]),
					[
						phase.children[0].deep_clone(),
						phase.children[1].deep_clone(),
						ContentValue.text(String(_mapping_by_identity[identity])),
						phase.children[2].deep_clone(),
					]
				))
			payload.children[7] = ContentValue.ordered_list(phases)
	return ContentEntryValue.new(
		source.category,
		source.content_id,
		source.resource_schema_version,
		payload
	)

func _top_level_field_ids(count: int) -> PackedInt32Array:
	var result := PackedInt32Array([1, 2, 3])
	for offset: int in range(count - 3): result.append(0x0100 + offset)
	return result

func _phase_identity(encounter_id: StringName, phase_index: int) -> String:
	return "%s/%010d" % [String(encounter_id), phase_index]

func _mapping_error(path: StringName) -> bool:
	_error = ContentGenerationMigrationError.new(
		ContentGenerationMigrationError.MAPPING_INVALID,
		path
	)
	return false

func _has_duplicate(values: Array[StringName]) -> bool:
	for index: int in range(1, values.size()):
		if values[index] == values[index - 1]: return true
	return false

func _entry_less(left: ContentEntryValue, right: ContentEntryValue) -> bool:
	var left_code := ContentCategory.code_for_name(left.category)
	var right_code := ContentCategory.code_for_name(right.category)
	return String(left.content_id) < String(right.content_id) \
		if left_code == right_code else left_code < right_code

func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _failure_from_state(
	default_code: StringName,
	default_path: StringName
) -> ContentGenerationMigrationDraftResult:
	if _error == null: return _failure(default_code, default_path)
	return _failure(_error.code, _error.field_path)

func _failure(
	code: StringName,
	path: StringName
) -> ContentGenerationMigrationDraftResult:
	return ContentGenerationMigrationDraftResult.failure(code, path)
