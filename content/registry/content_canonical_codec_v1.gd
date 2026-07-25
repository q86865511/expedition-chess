class_name ContentCanonicalCodecV1
extends RefCounted

const CONTENT_CODEC_VERSION := 1
const MAX_SCALAR_BYTES := 1048576
const MAX_COLLECTION_COUNT := 65535
const MAX_CATALOG_BYTES := 67108864

var _stable_id_validator := StableIdValidator.new()

const TAG_BOOL := 0x01
const TAG_I32 := 0x02
const TAG_U32 := 0x03
const TAG_U64 := 0x04
const TAG_STRING := 0x05
const TAG_STABLE_ID := 0x06
const TAG_ENUM := 0x07
const TAG_PATH := 0x08
const TAG_DIGEST := 0x09
const TAG_RECORD := 0x0a
const TAG_LIST := 0x0b
const TAG_SET := 0x0c
const TAG_OPTIONAL := 0x0d
const TAG_BYTES := 0x0e

class ByteWriter:
	var data := PackedByteArray()

	func append_u8(value: int) -> void:
		data.append(value & 0xff)

	func append_u16(value: int) -> void:
		append_u8(value >> 8)
		append_u8(value)

	func append_u32(value: int) -> void:
		append_u8(value >> 24)
		append_u8(value >> 16)
		append_u8(value >> 8)
		append_u8(value)

	func append_i32(value: int) -> void:
		append_u32(value & 0xffffffff)

	func append_bytes(value: PackedByteArray) -> void:
		data.append_array(value)

class ByteReader:
	var data: PackedByteArray
	var offset: int
	var failed: bool

	func _init(p_data: PackedByteArray) -> void:
		data = p_data.duplicate()

	func remaining() -> int:
		return data.size() - offset

	func read_u8() -> int:
		if remaining() < 1:
			failed = true
			return 0
		var value := data[offset]
		offset += 1
		return value

	func read_u16() -> int:
		return (read_u8() << 8) | read_u8()

	func read_u32() -> int:
		return (read_u8() << 24) | (read_u8() << 16) | (read_u8() << 8) | read_u8()

	func read_i32() -> int:
		var value := read_u32()
		if value >= 0x80000000:
			return value - 0x100000000
		return value

	func read_bytes(count: int) -> PackedByteArray:
		if count < 0 or remaining() < count:
			failed = true
			return PackedByteArray()
		var value := data.slice(offset, offset + count)
		offset += count
		return value

func encode_entry(entry: ContentEntryValue) -> ContentCodecResult:
	if entry == null or entry.payload == null:
		return ContentCodecResult.failed(&"entry")
	if entry.resource_schema_version != 1:
		return ContentCodecResult.failed(
			&"entry.resource_schema_version",
			entry.content_id
		)
	var envelope := ContentValue.record(0x0100, PackedInt32Array([1, 2, 3, 4]), [
		ContentValue.enum_value(entry.category),
		ContentValue.stable_id(entry.content_id),
		ContentValue.u32(entry.resource_schema_version),
		entry.payload
	])
	if envelope.record_type != 0x0100 or entry.payload.record_type != ContentCategory.code_for_name(entry.category):
		return ContentCodecResult.failed(&"entry.payload", entry.content_id)
	return _encode_prefixed("CCE1", envelope, entry.content_id)

func decode_entry(bytes: PackedByteArray) -> ContentCodecResult:
	var decoded := _decode_prefixed(bytes, "CCE1")
	if not decoded.ok or decoded.entry != null:
		return decoded
	var value := decoded.catalog.entries[0].payload
	if value.record_type != 0x0100 or value.children.size() != 4:
		return ContentCodecResult.failed(&"entry.envelope")
	var category := StringName(value.children[0].string_value)
	var entry := ContentEntryValue.new(category, StringName(value.children[1].string_value), value.children[2].int_value, value.children[3])
	if entry.resource_schema_version != 1:
		return ContentCodecResult.failed(
			&"entry.resource_schema_version",
			entry.content_id
		)
	if entry.payload.record_type != ContentCategory.code_for_name(category):
		return ContentCodecResult.failed(&"entry.payload", entry.content_id)
	return ContentCodecResult.decoded_entry(entry, bytes)

func encode_manifest(manifest: ContentManifestValue) -> ContentCodecResult:
	if manifest == null:
		return ContentCodecResult.failed(&"manifest")
	if manifest.catalog_schema_version != 1:
		return ContentCodecResult.failed(&"manifest.catalog_schema_version")
	var pack_values: Array[ContentValue] = []
	for pack_id in manifest.pack_ids:
		pack_values.append(ContentValue.stable_id(pack_id))
	var alias_values: Array[ContentValue] = []
	for alias in manifest.aliases:
		alias_values.append(ContentValue.record(0x0200, PackedInt32Array([1, 2]), [ContentValue.stable_id(alias.source_id), ContentValue.stable_id(alias.target_id)]))
	var tombstone_values: Array[ContentValue] = []
	for tombstone in manifest.tombstones:
		var replacement: ContentValue = null
		if tombstone.has_replacement:
			replacement = ContentValue.stable_id(tombstone.replacement_id)
		tombstone_values.append(ContentValue.record(0x0201, PackedInt32Array([1, 2, 3, 4, 5]), [
			ContentValue.stable_id(tombstone.original_id), ContentValue.enum_value(tombstone.category),
			ContentValue.enum_value(tombstone.policy), ContentValue.optional(replacement), ContentValue.enum_value(tombstone.reason_code)
		]))
	var index_values: Array[ContentValue] = []
	for index in manifest.entry_indexes:
		index_values.append(ContentValue.record(0x0202, PackedInt32Array([1, 2, 3, 4]), [
			ContentValue.enum_value(index.category), ContentValue.stable_id(index.content_id),
			ContentValue.u32(index.resource_schema_version), ContentValue.digest(index.entry_digest)
		]))
	var record := ContentValue.record(0x0101, PackedInt32Array([1, 2, 3, 4, 5, 6, 7]), [
		ContentValue.u32(CONTENT_CODEC_VERSION), ContentValue.u32(manifest.catalog_schema_version),
		ContentValue.text(manifest.content_version), ContentValue.canonical_set(pack_values),
		ContentValue.canonical_set(alias_values), ContentValue.canonical_set(tombstone_values),
		ContentValue.ordered_list(index_values)
	])
	return _encode_prefixed("CCM1", record)

func decode_manifest(bytes: PackedByteArray) -> ContentCodecResult:
	var decoded := _decode_prefixed(bytes, "CCM1")
	if not decoded.ok:
		return decoded
	var record := decoded.catalog.entries[0].payload
	if record.record_type != 0x0101 or record.children[0].int_value != CONTENT_CODEC_VERSION:
		return ContentCodecResult.failed(&"manifest.envelope")
	if record.children[1].int_value != 1:
		return ContentCodecResult.failed(&"manifest.catalog_schema_version")
	var result := ContentManifestValue.new()
	result.catalog_schema_version = record.children[1].int_value
	result.content_version = record.children[2].string_value
	for value in record.children[3].children:
		result.pack_ids.append(StringName(value.string_value))
	for value in record.children[4].children:
		result.aliases.append(ContentAliasValue.new(StringName(value.children[0].string_value), StringName(value.children[1].string_value)))
	for value in record.children[5].children:
		var optional := value.children[3]
		var replacement := StringName("")
		if optional.optional_present:
			replacement = StringName(optional.children[0].string_value)
		result.tombstones.append(ContentTombstoneValue.new(
			StringName(value.children[0].string_value), StringName(value.children[1].string_value),
			StringName(value.children[2].string_value), replacement, optional.optional_present,
			StringName(value.children[4].string_value)))
	for value in record.children[6].children:
		result.entry_indexes.append(ContentEntryIndexValue.new(
			StringName(value.children[0].string_value), StringName(value.children[1].string_value),
			value.children[2].int_value, value.children[3].bytes_value))
	return ContentCodecResult.decoded_manifest(result, bytes)

func encode_catalog(manifest_digest: PackedByteArray, manifest_bytes: PackedByteArray, entry_bytes: Array[PackedByteArray]) -> ContentCodecResult:
	if manifest_digest.size() != 32 or manifest_bytes.size() > MAX_CATALOG_BYTES:
		return ContentCodecResult.failed(&"catalog")
	var encoded_entries: Array[ContentValue] = []
	for bytes in entry_bytes:
		encoded_entries.append(ContentValue.raw_bytes(bytes))
	var record := ContentValue.record(0x0102, PackedInt32Array([1, 2, 3]), [
		ContentValue.digest(manifest_digest), ContentValue.raw_bytes(manifest_bytes), ContentValue.ordered_list(encoded_entries)
	])
	return _encode_prefixed("CCC1", record)

func decode_catalog(bytes: PackedByteArray) -> ContentCodecResult:
	if bytes.size() > MAX_CATALOG_BYTES:
		return ContentCodecResult.failed(&"catalog.size")
	var decoded := _decode_prefixed(bytes, "CCC1")
	if not decoded.ok:
		return decoded
	var record := decoded.catalog.entries[0].payload
	if record.record_type != 0x0102:
		return ContentCodecResult.failed(&"catalog.envelope")
	var manifest_result := decode_manifest(record.children[1].bytes_value)
	if not manifest_result.ok:
		return manifest_result
	var actual_digest := sha256_bytes(record.children[1].bytes_value)
	if actual_digest != record.children[0].bytes_value:
		return ContentCodecResult.failed(&"catalog.manifest_digest")
	var entry_values: Array[ContentValue] = record.children[2].children
	if entry_values.size() != manifest_result.manifest.entry_indexes.size():
		return ContentCodecResult.failed(&"catalog.entry_count")
	var previous_index: ContentEntryIndexValue = null
	for expected_index in manifest_result.manifest.entry_indexes:
		if ContentCategory.code_for_name(expected_index.category) == 0:
			return ContentCodecResult.failed(&"catalog.entry_identity", expected_index.content_id)
		if previous_index != null and not _catalog_identity_less(
			previous_index.category,
			previous_index.content_id,
			expected_index.category,
			expected_index.content_id
		):
			return ContentCodecResult.failed(&"catalog.entry_order", expected_index.content_id)
		previous_index = expected_index
	var decoded_entries: Array[ContentEntryValue] = []
	var decoded_entry_bytes: Array[PackedByteArray] = []
	var previous_entry: ContentEntryValue = null
	for child in entry_values:
		var entry_result := decode_entry(child.bytes_value)
		if not entry_result.ok:
			return entry_result
		if previous_entry != null and not _catalog_identity_less(
			previous_entry.category,
			previous_entry.content_id,
			entry_result.entry.category,
			entry_result.entry.content_id
		):
			return ContentCodecResult.failed(&"catalog.entry_order", entry_result.entry.content_id)
		previous_entry = entry_result.entry
		decoded_entries.append(entry_result.entry)
		decoded_entry_bytes.append(child.bytes_value.duplicate())
	for index in decoded_entries.size():
		var expected: ContentEntryIndexValue = manifest_result.manifest.entry_indexes[index]
		var actual: ContentEntryValue = decoded_entries[index]
		if actual.category != expected.category \
			or actual.content_id != expected.content_id \
			or actual.resource_schema_version != expected.resource_schema_version:
			return ContentCodecResult.failed(&"catalog.entry_identity", actual.content_id)
		if sha256_bytes(decoded_entry_bytes[index]) != expected.entry_digest:
			return ContentCodecResult.failed(&"catalog.entry_digest", actual.content_id)
	var catalog := ContentCatalogSnapshot.new()
	catalog.manifest = manifest_result.manifest
	catalog.manifest_bytes = record.children[1].bytes_value.duplicate()
	catalog.manifest_digest = actual_digest.hex_encode()
	for entry in decoded_entries: catalog.entries.append(entry.deep_clone())
	for entry_bytes in decoded_entry_bytes: catalog.entry_bytes.append(entry_bytes.duplicate())
	catalog.diagnostic_catalog_bytes = bytes.duplicate()
	return ContentCodecResult.decoded_catalog(catalog, bytes)

func _catalog_identity_less(
	left_category: StringName,
	left_id: StringName,
	right_category: StringName,
	right_id: StringName
) -> bool:
	var left_code := ContentCategory.code_for_name(left_category)
	var right_code := ContentCategory.code_for_name(right_category)
	if left_code != right_code: return left_code < right_code
	return String(left_id) < String(right_id)

func sha256_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()

func encode_value_for_sort(value: ContentValue) -> ContentCodecResult:
	var writer := ByteWriter.new()
	if not _encode_value(writer, value):
		return ContentCodecResult.failed(&"codec.sort_value")
	return ContentCodecResult.encoded(writer.data)

func validate_typed_value(value: ContentValue) -> ContentCodecResult:
	if value == null or value.kind != ContentValue.Kind.RECORD or not _validate_record_schema(value):
		return ContentCodecResult.failed(&"codec.typed_value")
	return encode_value_for_sort(value)

func _encode_prefixed(prefix: String, value: ContentValue, source_id: StringName = &"") -> ContentCodecResult:
	if value.kind != ContentValue.Kind.RECORD or not _validate_record_schema(value):
		return ContentCodecResult.failed(&"codec.schema", source_id)
	var writer := ByteWriter.new()
	writer.append_bytes(prefix.to_ascii_buffer())
	if not _encode_value(writer, value):
		return ContentCodecResult.failed(&"codec.value", source_id)
	return ContentCodecResult.encoded(writer.data)

func _decode_prefixed(bytes: PackedByteArray, prefix: String) -> ContentCodecResult:
	if bytes.size() < 5 or bytes.slice(0, 4) != prefix.to_ascii_buffer():
		return ContentCodecResult.failed(&"codec.magic")
	var reader := ByteReader.new(bytes)
	reader.offset = 4
	var value := _decode_value(reader)
	if reader.failed or value == null or reader.remaining() != 0 or not _validate_record_schema(value):
		return ContentCodecResult.failed(&"codec.value")
	var holder := ContentCatalogSnapshot.new()
	holder.entries.append(ContentEntryValue.new(&"", &"", 1, value))
	return ContentCodecResult.decoded_catalog(holder, bytes)

func _encode_value(writer: ByteWriter, value: ContentValue) -> bool:
	if value == null:
		return false
	writer.append_u8(_tag_for_kind(value.kind))
	match value.kind:
		ContentValue.Kind.BOOL:
			writer.append_u8(1 if value.bool_value else 0)
		ContentValue.Kind.I32:
			if value.int_value < -2147483648 or value.int_value > 2147483647: return false
			writer.append_i32(value.int_value)
		ContentValue.Kind.U32:
			if value.int_value < 0 or value.int_value > 0xffffffff: return false
			writer.append_u32(value.int_value)
		ContentValue.Kind.U64:
			if value.bytes_value.size() == 8:
				writer.append_bytes(value.bytes_value)
			elif value.int_value >= 0:
				writer.append_u32(0)
				writer.append_u32(value.int_value)
			else:
				return false
		ContentValue.Kind.STRING, ContentValue.Kind.STABLE_ID, ContentValue.Kind.ENUM, ContentValue.Kind.PATH:
			var string_bytes := value.string_value.to_utf8_buffer()
			if string_bytes.size() > MAX_SCALAR_BYTES or not _validate_string_value(value): return false
			writer.append_u32(string_bytes.size())
			writer.append_bytes(string_bytes)
		ContentValue.Kind.DIGEST:
			if value.bytes_value.size() != 32: return false
			writer.append_bytes(value.bytes_value)
		ContentValue.Kind.RECORD:
			if value.children.size() != value.field_ids.size() or value.children.size() > MAX_COLLECTION_COUNT: return false
			writer.append_u16(value.record_type)
			writer.append_u16(value.children.size())
			var previous := -1
			for index in value.children.size():
				var field_id := value.field_ids[index]
				if field_id <= previous: return false
				previous = field_id
				writer.append_u16(field_id)
				if not _encode_value(writer, value.children[index]): return false
		ContentValue.Kind.LIST, ContentValue.Kind.SET:
			if value.children.size() > MAX_COLLECTION_COUNT: return false
			if value.kind == ContentValue.Kind.SET and not _is_canonical_set(value.children): return false
			writer.append_u32(value.children.size())
			for child in value.children:
				if not _encode_value(writer, child): return false
		ContentValue.Kind.OPTIONAL:
			if value.optional_present:
				if value.children.size() != 1: return false
				writer.append_u8(1)
				if not _encode_value(writer, value.children[0]): return false
			else:
				if not value.children.is_empty(): return false
				writer.append_u8(0)
		ContentValue.Kind.BYTES:
			if value.bytes_value.size() > MAX_SCALAR_BYTES: return false
			writer.append_u32(value.bytes_value.size())
			writer.append_bytes(value.bytes_value)
	return true

func _decode_value(reader: ByteReader) -> ContentValue:
	var tag := reader.read_u8()
	if reader.failed:
		return null
	match tag:
		TAG_BOOL:
			var bool_byte := reader.read_u8()
			if bool_byte > 1: reader.failed = true
			return ContentValue.boolean(bool_byte == 1)
		TAG_I32: return ContentValue.i32(reader.read_i32())
		TAG_U32: return ContentValue.u32(reader.read_u32())
		TAG_U64:
			var result := ContentValue.new()
			result.kind = ContentValue.Kind.U64
			result.bytes_value = reader.read_bytes(8)
			return result
		TAG_STRING, TAG_STABLE_ID, TAG_ENUM, TAG_PATH:
			var length := reader.read_u32()
			if length > MAX_SCALAR_BYTES: reader.failed = true; return null
			var raw := reader.read_bytes(length)
			var decoded := raw.get_string_from_utf8()
			var value: ContentValue
			match tag:
				TAG_STRING: value = ContentValue.text(decoded)
				TAG_STABLE_ID: value = ContentValue.stable_id(StringName(decoded))
				TAG_ENUM: value = ContentValue.enum_value(StringName(decoded))
				_: value = ContentValue.path(decoded)
			if decoded.to_utf8_buffer() != raw or not _validate_string_value(value): reader.failed = true
			return value
		TAG_DIGEST: return ContentValue.digest(reader.read_bytes(32))
		TAG_RECORD:
			var type_id := reader.read_u16()
			var count := reader.read_u16()
			var ids := PackedInt32Array()
			var values: Array[ContentValue] = []
			var previous := -1
			for index in count:
				var field_id := reader.read_u16()
				if field_id <= previous: reader.failed = true; return null
				previous = field_id
				ids.append(field_id)
				var child := _decode_value(reader)
				if child == null: reader.failed = true; return null
				values.append(child)
			return ContentValue.record(type_id, ids, values)
		TAG_LIST, TAG_SET:
			var count := reader.read_u32()
			if count > MAX_COLLECTION_COUNT: reader.failed = true; return null
			var values: Array[ContentValue] = []
			for index in count:
				var child := _decode_value(reader)
				if child == null: reader.failed = true; return null
				values.append(child)
			var collection := ContentValue.ordered_list(values) if tag == TAG_LIST else ContentValue.canonical_set(values)
			if tag == TAG_SET and not _is_canonical_set(collection.children): reader.failed = true
			return collection
		TAG_OPTIONAL:
			var marker := reader.read_u8()
			if marker == 0: return ContentValue.optional(null)
			if marker != 1: reader.failed = true; return null
			return ContentValue.optional(_decode_value(reader))
		TAG_BYTES:
			var length := reader.read_u32()
			if length > MAX_SCALAR_BYTES: reader.failed = true; return null
			return ContentValue.raw_bytes(reader.read_bytes(length))
	reader.failed = true
	return null

func _tag_for_kind(kind: ContentValue.Kind) -> int:
	return [TAG_BOOL, TAG_I32, TAG_U32, TAG_U64, TAG_STRING, TAG_STABLE_ID, TAG_ENUM, TAG_PATH, TAG_DIGEST, TAG_RECORD, TAG_LIST, TAG_SET, TAG_OPTIONAL, TAG_BYTES][kind]

func _validate_string_value(value: ContentValue) -> bool:
	if value.kind == ContentValue.Kind.STABLE_ID:
		return _stable_id_validator.is_valid(StringName(value.string_value))
	if value.kind == ContentValue.Kind.ENUM:
		return _is_canonical_ascii(value.string_value)
	if value.kind == ContentValue.Kind.PATH:
		return value.string_value.begins_with("res://") and not value.string_value.contains("\\") and not value.string_value.contains("..")
	return true

func _is_canonical_ascii(value: String) -> bool:
	if value.is_empty(): return false
	for byte in value.to_utf8_buffer():
		if byte < 0x21 or byte > 0x7e: return false
	return true

func _is_canonical_set(values: Array[ContentValue]) -> bool:
	var previous := PackedByteArray()
	for index in values.size():
		var writer := ByteWriter.new()
		if not _encode_value(writer, values[index]): return false
		if index > 0 and _compare_bytes(previous, writer.data) >= 0: return false
		previous = writer.data
	return true

func _compare_bytes(left: PackedByteArray, right: PackedByteArray) -> int:
	var count := mini(left.size(), right.size())
	for index in count:
		if left[index] < right[index]: return -1
		if left[index] > right[index]: return 1
	if left.size() < right.size(): return -1
	if left.size() > right.size(): return 1
	return 0

func _validate_record_schema(value: ContentValue) -> bool:
	if value.kind != ContentValue.Kind.RECORD:
		return false
	var expected_ids := _expected_field_ids(value.record_type)
	var expected_kinds := _expected_field_kinds(value.record_type)
	if expected_ids.is_empty() or value.field_ids != expected_ids or value.children.size() != expected_kinds.size():
		return false
	for index in value.children.size():
		if value.children[index].kind != expected_kinds[index]:
			return false
		if value.children[index].kind == ContentValue.Kind.RECORD and not _validate_record_schema(value.children[index]):
			return false
		if value.children[index].kind in [ContentValue.Kind.LIST, ContentValue.Kind.SET]:
			var expected_child_kind := _expected_collection_child_kind(value.record_type, value.field_ids[index])
			for child in value.children[index].children:
				if expected_child_kind >= 0 and child.kind != expected_child_kind: return false
				if child.kind == ContentValue.Kind.RECORD and not _validate_record_schema(child): return false
				if child.kind == ContentValue.Kind.RECORD and not _record_child_allowed(value.record_type, value.field_ids[index], child.record_type): return false
		if value.children[index].kind == ContentValue.Kind.OPTIONAL and value.children[index].optional_present:
			var child := value.children[index].children[0]
			var expected_optional_kind := _expected_optional_child_kind(value.record_type, value.field_ids[index])
			if expected_optional_kind >= 0 and child.kind != expected_optional_kind: return false
			if child.kind == ContentValue.Kind.RECORD and not _validate_record_schema(child): return false
	return true

func _expected_collection_child_kind(type_id: int, field_id: int) -> int:
	var D := ContentValue.Kind.STABLE_ID
	var P := ContentValue.Kind.PATH
	var R := ContentValue.Kind.RECORD
	var U := ContentValue.Kind.U32
	var Y := ContentValue.Kind.BYTES
	match type_id:
		0x0101:
			if field_id == 4: return D
			if field_id in [5, 6, 7]: return R
		0x0102: return Y if field_id == 3 else -1
		0x1001:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id == 0x0101: return D
			if field_id == 0x0103: return R
		0x1002:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id == 0x0102: return R
		0x1003:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id == 0x0104: return D
		0x1004:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id in [0x0102, 0x0103, 0x0104]: return R
		0x1005:
			if field_id == 2: return D
			if field_id == 3: return P
		0x1006:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id == 0x0100: return D
			if field_id == 0x0101: return R
			if field_id == 0x0102: return D
		0x1007:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id == 0x0101: return R
		0x1008:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id == 0x0101: return D
		0x1009:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id in [0x0100, 0x0102]: return R
			if field_id == 0x0101: return D
		0x100a:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id in [0x0102, 0x0104]: return R
			if field_id == 0x0103: return D
		0x100b:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id == 0x0100: return R
		0x100c:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id in [0x0102, 0x0103]: return R
		0x100d:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id in [0x0102, 0x0104, 0x0105]: return D
		0x100e:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id in [0x0100, 0x0108, 0x0109, 0x010a, 0x010b, 0x010c, 0x010d]: return R
		0x100f:
			if field_id == 2: return D
			if field_id == 3: return P
			if field_id in [0x0100, 0x0103]: return R
		0x2001: return D if field_id == 2 else -1
		0x2006: return D if field_id == 7 else -1
		0x2007: return D if field_id == 3 else -1
		0x2008: return R if field_id == 4 else -1
		0x200a: return U if field_id == 2 else -1
	return -1

func _expected_optional_child_kind(type_id: int, field_id: int) -> int:
	if type_id == 0x0201 and field_id == 4: return ContentValue.Kind.STABLE_ID
	if type_id == 0x1001 and field_id == 0x0104: return ContentValue.Kind.STABLE_ID
	if type_id == 0x1006 and field_id == 0x0103: return ContentValue.Kind.STABLE_ID
	if type_id == 0x2002:
		if field_id == 4: return ContentValue.Kind.I32
		if field_id == 5: return ContentValue.Kind.STABLE_ID
		if field_id == 6: return ContentValue.Kind.U32
	if type_id == 0x2008 and field_id == 2: return ContentValue.Kind.STABLE_ID
	return -1

func _record_child_allowed(parent_type: int, field_id: int, child_type: int) -> bool:
	if parent_type == 0x0101:
		if field_id == 5: return child_type == 0x0200
		if field_id == 6: return child_type == 0x0201
		if field_id == 7: return child_type == 0x0202
	if parent_type == 0x1001 and field_id == 0x0103: return child_type == 0x200f
	if parent_type == 0x1002 and field_id == 0x0102: return child_type == 0x2001
	if parent_type == 0x1004:
		if field_id == 0x0102: return child_type == 0x2002
		if field_id == 0x0103: return child_type >= 0x3001 and child_type <= 0x3009
		if field_id == 0x0104: return child_type >= 0x3101 and child_type <= 0x310a
	if parent_type == 0x1006 and field_id == 0x0101: return child_type == 0x2003
	if parent_type == 0x1007 and field_id == 0x0101: return child_type >= 0x3101 and child_type <= 0x310a
	if parent_type == 0x1009:
		if field_id == 0x0100: return child_type == 0x2004
		if field_id == 0x0102: return child_type == 0x2005
	if parent_type == 0x100a:
		if field_id == 0x0102: return child_type == 0x2006
		if field_id == 0x0104: return child_type == 0x2007
	if parent_type == 0x100b and field_id == 0x0100: return child_type == 0x2008
	if parent_type == 0x100c and field_id in [0x0102, 0x0103]: return child_type >= 0x3101 and child_type <= 0x310a
	if parent_type == 0x100e:
		if field_id == 0x010a: return child_type == 0x200a
		return child_type == 0x200e
	if parent_type == 0x100f:
		if field_id == 0x0100: return child_type == 0x200b
		if field_id == 0x0103: return child_type == 0x200c
	if parent_type == 0x2008 and field_id == 4: return child_type == 0x2002
	return true

func _expected_field_ids(type_id: int) -> PackedInt32Array:
	var count := _expected_field_kinds(type_id).size()
	if count == 0: return PackedInt32Array()
	var result := PackedInt32Array()
	if type_id >= 0x1001 and type_id <= 0x100f:
		result.append_array(PackedInt32Array([1, 2, 3]))
		for offset in count - 3: result.append(0x0100 + offset)
	elif type_id >= 0x3001 and type_id <= 0x31ff:
		result.append(1)
		for offset in count - 1: result.append(0x0100 + offset)
	else:
		for field_id in range(1, count + 1): result.append(field_id)
	return result

func _expected_field_kinds(type_id: int) -> PackedInt32Array:
	var B := ContentValue.Kind.BOOL
	var I := ContentValue.Kind.I32
	var U := ContentValue.Kind.U32
	var S := ContentValue.Kind.STRING
	var D := ContentValue.Kind.STABLE_ID
	var E := ContentValue.Kind.ENUM
	var P := ContentValue.Kind.PATH
	var H := ContentValue.Kind.DIGEST
	var R := ContentValue.Kind.RECORD
	var L := ContentValue.Kind.LIST
	var C := ContentValue.Kind.SET
	var O := ContentValue.Kind.OPTIONAL
	var Y := ContentValue.Kind.BYTES
	match type_id:
		0x0100: return PackedInt32Array([E, D, U, R])
		0x0101: return PackedInt32Array([U, U, S, C, C, C, L])
		0x0102: return PackedInt32Array([H, Y, L])
		0x0200: return PackedInt32Array([D, D])
		0x0201: return PackedInt32Array([D, E, E, O, E])
		0x0202: return PackedInt32Array([E, D, U, H])
		0x1001: return PackedInt32Array([S, C, C, U, C, R, C, O, E, E, E, E])
		0x1002: return PackedInt32Array([S, C, C, E, E, C, S])
		0x1003: return PackedInt32Array([S, C, C, I, I, E, U, L, S])
		0x1004: return PackedInt32Array([S, C, C, E, E, C, L, L, E, U, U])
		0x1005: return PackedInt32Array([S, C, C, S, U])
		0x1006: return PackedInt32Array([S, C, C, C, C, L, O])
		0x1007: return PackedInt32Array([S, C, C, E, L, U])
		0x1008: return PackedInt32Array([S, C, C, E, L, U, I])
		0x1009: return PackedInt32Array([S, C, C, C, L, C, I])
		0x100a: return PackedInt32Array([S, C, C, E, U, C, C, L])
		0x100b: return PackedInt32Array([S, C, C, C, U])
		0x100c: return PackedInt32Array([S, C, C, E, D, L, L])
		0x100d: return PackedInt32Array([S, C, C, E, U, C, U, C, C])
		0x100e: return PackedInt32Array([S, C, C, C, U, U, U, U, U, U, U, C, C, C, C, C, C])
		0x100f: return PackedInt32Array([S, C, C, C, I, I, C])
		0x2000: return PackedInt32Array([I, I, I, I, I, I, I, I, I])
		0x2001: return PackedInt32Array([U, L])
		0x2002: return PackedInt32Array([E, E, E, O, O, O])
		0x2003: return PackedInt32Array([E, E, I])
		0x2004: return PackedInt32Array([D, U])
		0x2005: return PackedInt32Array([E, I])
		0x2006: return PackedInt32Array([E, I, I, S, D, U, L])
		0x2007: return PackedInt32Array([U, U, L])
		0x2008: return PackedInt32Array([E, O, I, C])
		0x2009: return PackedInt32Array([I, I])
		0x200a: return PackedInt32Array([U, L])
		0x200b: return PackedInt32Array([E, I])
		0x200c: return PackedInt32Array([U, U])
		0x200d: return PackedInt32Array([D, I])
		0x200e: return PackedInt32Array([U, U])
		0x200f: return PackedInt32Array([U, U, U, U, U, U, U, U, U, U])
		0x3001: return PackedInt32Array([U, I, E, E, E])
		0x3002: return PackedInt32Array([U, I, E, E])
		0x3003: return PackedInt32Array([U, I, U, E])
		0x3004: return PackedInt32Array([U, E, E, I, U, E])
		0x3005: return PackedInt32Array([U, D, U, U, E])
		0x3006: return PackedInt32Array([U, D, E])
		0x3007: return PackedInt32Array([U, E, U])
		0x3008: return PackedInt32Array([U, D, U, U, E])
		0x3009: return PackedInt32Array([U, I, E])
		0x3101, 0x3102, 0x3103: return PackedInt32Array([U, I, E])
		0x3108, 0x3109, 0x310a: return PackedInt32Array([U, I, E])
		0x3104: return PackedInt32Array([U, D, I])
		0x3105: return PackedInt32Array([U, D, U])
		0x3106: return PackedInt32Array([U, D])
		0x3107: return PackedInt32Array([U, D, I])
	return PackedInt32Array()
