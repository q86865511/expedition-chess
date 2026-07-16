class_name ContentCanonicalCodecV2
extends ContentCanonicalCodecV1

const CONTENT_CODEC_VERSION_V2: int = 2

func encode_manifest(manifest: ContentManifestValue) -> ContentCodecResult:
	if manifest == null:
		return ContentCodecResult.failed(&"manifest")
	if manifest.catalog_schema_version != 1:
		return ContentCodecResult.failed(&"manifest.catalog_schema_version")
	var pack_values: Array[ContentValue] = []
	for pack_id: StringName in manifest.pack_ids:
		pack_values.append(ContentValue.stable_id(pack_id))
	var alias_values: Array[ContentValue] = []
	for alias: ContentAliasValue in manifest.aliases:
		alias_values.append(ContentValue.record(
			0x0200,
			PackedInt32Array([1, 2]),
			[ContentValue.stable_id(alias.source_id), ContentValue.stable_id(alias.target_id)]
		))
	var tombstone_values: Array[ContentValue] = []
	for tombstone: ContentTombstoneValue in manifest.tombstones:
		var replacement: ContentValue = null
		if tombstone.has_replacement:
			replacement = ContentValue.stable_id(tombstone.replacement_id)
		tombstone_values.append(ContentValue.record(
			0x0201,
			PackedInt32Array([1, 2, 3, 4, 5]),
			[
				ContentValue.stable_id(tombstone.original_id),
				ContentValue.enum_value(tombstone.category),
				ContentValue.enum_value(tombstone.policy),
				ContentValue.optional(replacement),
				ContentValue.enum_value(tombstone.reason_code),
			]
		))
	var index_values: Array[ContentValue] = []
	for index_value: ContentEntryIndexValue in manifest.entry_indexes:
		index_values.append(ContentValue.record(
			0x0202,
			PackedInt32Array([1, 2, 3, 4]),
			[
				ContentValue.enum_value(index_value.category),
				ContentValue.stable_id(index_value.content_id),
				ContentValue.u32(index_value.resource_schema_version),
				ContentValue.digest(index_value.entry_digest),
			]
		))
	var record := ContentValue.record(
		0x0101,
		PackedInt32Array([1, 2, 3, 4, 5, 6, 7]),
		[
			ContentValue.u32(CONTENT_CODEC_VERSION_V2),
			ContentValue.u32(manifest.catalog_schema_version),
			ContentValue.text(manifest.content_version),
			ContentValue.canonical_set(pack_values),
			ContentValue.canonical_set(alias_values),
			ContentValue.canonical_set(tombstone_values),
			ContentValue.ordered_list(index_values),
		]
	)
	return _encode_prefixed("CCM1", record)

func decode_manifest(bytes: PackedByteArray) -> ContentCodecResult:
	var decoded := _decode_prefixed(bytes, "CCM1")
	if not decoded.ok:
		return decoded
	var record: ContentValue = decoded.catalog.entries[0].payload
	if record.record_type != 0x0101 \
		or record.children[0].int_value != CONTENT_CODEC_VERSION_V2:
		return ContentCodecResult.failed(&"manifest.envelope")
	if record.children[1].int_value != 1:
		return ContentCodecResult.failed(&"manifest.catalog_schema_version")
	var result := ContentManifestValue.new()
	result.catalog_schema_version = record.children[1].int_value
	result.content_version = record.children[2].string_value
	for value: ContentValue in record.children[3].children:
		result.pack_ids.append(StringName(value.string_value))
	for value: ContentValue in record.children[4].children:
		result.aliases.append(ContentAliasValue.new(
			StringName(value.children[0].string_value),
			StringName(value.children[1].string_value)
		))
	for value: ContentValue in record.children[5].children:
		var optional: ContentValue = value.children[3]
		var replacement := StringName("")
		if optional.optional_present:
			replacement = StringName(optional.children[0].string_value)
		result.tombstones.append(ContentTombstoneValue.new(
			StringName(value.children[0].string_value),
			StringName(value.children[1].string_value),
			StringName(value.children[2].string_value),
			replacement,
			optional.optional_present,
			StringName(value.children[4].string_value)
		))
	for value: ContentValue in record.children[6].children:
		result.entry_indexes.append(ContentEntryIndexValue.new(
			StringName(value.children[0].string_value),
			StringName(value.children[1].string_value),
			value.children[2].int_value,
			value.children[3].bytes_value
		))
	return ContentCodecResult.decoded_manifest(result, bytes)

func _expected_collection_child_kind(type_id: int, field_id: int) -> int:
	if type_id == ContentCategory.EFFECT:
		if field_id in [0x0103, 0x0104, 0x0105]:
			return ContentValue.Kind.RECORD
	if type_id == ContentCategory.UNIT and field_id == 0x0109:
		return ContentValue.Kind.STABLE_ID
	if type_id == ContentCategory.ENCOUNTER and field_id == 0x0104:
		return ContentValue.Kind.RECORD
	if type_id == 0x2007 and field_id == 4:
		return ContentValue.Kind.STABLE_ID
	return super._expected_collection_child_kind(type_id, field_id)

func _record_child_allowed(parent_type: int, field_id: int, child_type: int) -> bool:
	if parent_type == ContentCategory.EFFECT:
		if field_id == 0x0103:
			return child_type == 0x2002
		if field_id == 0x0104:
			return child_type >= 0x3001 and child_type <= 0x3009
		if field_id == 0x0105:
			return child_type >= 0x3101 and child_type <= 0x3107
	if parent_type == ContentCategory.ENCOUNTER and field_id == 0x0104:
		return child_type == 0x2007
	return super._record_child_allowed(parent_type, field_id, child_type)

func _expected_field_ids(type_id: int) -> PackedInt32Array:
	if type_id == ContentCategory.COMBAT_CONFIG:
		var kinds := _expected_field_kinds(type_id)
		var result := PackedInt32Array([1, 2, 3])
		for offset: int in range(kinds.size() - 3):
			result.append(0x0100 + offset)
		return result
	return super._expected_field_ids(type_id)

func _expected_field_kinds(type_id: int) -> PackedInt32Array:
	var U := ContentValue.Kind.U32
	var S := ContentValue.Kind.STRING
	var C := ContentValue.Kind.SET
	if type_id == ContentCategory.COMBAT_CONFIG:
		var result := PackedInt32Array([S, C, C])
		for _index: int in range(26):
			result.append(U)
		return result
	if type_id == 0x2007:
		return PackedInt32Array([U, U, S, ContentValue.Kind.LIST])
	if type_id == ContentCategory.EFFECT:
		return PackedInt32Array([
			S, C, C,
			ContentValue.Kind.ENUM,
			ContentValue.Kind.ENUM,
			U,
			C,
			ContentValue.Kind.LIST,
			ContentValue.Kind.LIST,
			ContentValue.Kind.ENUM,
			U,
			U,
		])
	if type_id == ContentCategory.UNIT:
		return PackedInt32Array([
			S, C, C,
			U, C, ContentValue.Kind.RECORD, C, ContentValue.Kind.OPTIONAL,
			ContentValue.Kind.ENUM, ContentValue.Kind.ENUM, ContentValue.Kind.ENUM,
			ContentValue.Kind.ENUM, ContentValue.Kind.LIST,
		])
	return super._expected_field_kinds(type_id)
