class_name ContentGenerationMigrationCodecV2
extends RefCounted

func encode_entry(entry: ContentGenerationMigrationEntryV2) -> PackedByteArray:
	if entry == null:
		return PackedByteArray()
	var bytes := "CMR2".to_ascii_buffer()
	_append_text(bytes, entry.source_category)
	_append_text(bytes, entry.source_id)
	_append_u32(bytes, entry.requirement)
	_append_u32(bytes, entry.mapping_kind)
	bytes.append(1 if entry.has_target else 0)
	if entry.has_target:
		if entry.target_entry_digest.length() != 64:
			return PackedByteArray()
		_append_text(bytes, entry.target_id)
		var digest := entry.target_entry_digest.hex_decode()
		if digest.size() != 32:
			return PackedByteArray()
		bytes.append_array(digest)
	return bytes

func mapping_digest(entries: Array[ContentGenerationMigrationEntryV2]) -> String:
	var encoded_entries: Array[PackedByteArray] = []
	for value: ContentGenerationMigrationEntryV2 in entries:
		if value == null:
			return ""
		var encoded := encode_entry(value)
		if encoded.is_empty():
			return ""
		encoded_entries.append(encoded)
	encoded_entries.sort_custom(func(left: PackedByteArray, right: PackedByteArray) -> bool:
		return left.hex_encode() < right.hex_encode()
	)
	var bytes := "CME2".to_ascii_buffer()
	_append_u32(bytes, encoded_entries.size())
	for encoded: PackedByteArray in encoded_entries:
		bytes.append_array(encoded)
	return _sha256(bytes)

# row = [key, zh_TW, en] 三欄;L10N2 preimage(framed key/zh/en)不變
func localization_digest(rows: Array[PackedStringArray]) -> String:
	var canonical_rows: Array[PackedStringArray] = []
	for row: PackedStringArray in rows:
		if row.size() != 3 or row[0].is_empty():
			return ""
		canonical_rows.append(row.duplicate())
	canonical_rows.sort_custom(
		func(left: PackedStringArray, right: PackedStringArray) -> bool:
			return left[0] < right[0]
	)
	var bytes := "L10N2".to_ascii_buffer()
	_append_u32(bytes, canonical_rows.size())
	for row: PackedStringArray in canonical_rows:
		_append_text(bytes, row[0])
		_append_text(bytes, row[1])
		_append_text(bytes, row[2])
	return _sha256(bytes)

func pack_digest(pack: ContentGenerationMigrationPackV2) -> String:
	if pack == null \
		or pack.source_catalog_schema_version != 1 \
		or pack.target_catalog_schema_version != 2 \
		or pack.from_codec != 2 \
		or pack.to_codec != 3:
		return ""
	var digests: Array[String] = [
		pack.source_manifest_digest,
		pack.expected_target_manifest_digest,
		pack.mapping_digest,
		pack.localization_catalog_digest,
	]
	for digest: String in digests:
		if digest.length() != 64 or digest.hex_decode().size() != 32:
			return ""
	if mapping_digest(pack.mappings) != pack.mapping_digest:
		return ""
	var bytes := "CGM2".to_ascii_buffer()
	_append_text(bytes, pack.source_content_version)
	_append_text(bytes, pack.target_content_version)
	bytes.append_array(pack.source_manifest_digest.hex_decode())
	bytes.append_array(pack.expected_target_manifest_digest.hex_decode())
	_append_u32(bytes, pack.source_catalog_schema_version)
	_append_u32(bytes, pack.target_catalog_schema_version)
	_append_u32(bytes, pack.from_codec)
	_append_u32(bytes, pack.to_codec)
	bytes.append_array(pack.mapping_digest.hex_decode())
	bytes.append_array(pack.localization_catalog_digest.hex_decode())
	return _sha256(bytes)

func receipt_digest(receipt: ContentGenerationMigrationReceiptV2) -> String:
	if receipt == null:
		return ""
	var digests: Array[String] = [
		receipt.source_manifest_digest,
		receipt.target_manifest_digest,
		receipt.mapping_digest,
		receipt.localization_catalog_digest,
		receipt.pack_digest,
	]
	for digest: String in digests:
		if digest.length() != 64 or digest.hex_decode().size() != 32:
			return ""
	var bytes := "CGR2".to_ascii_buffer()
	for digest: String in digests:
		bytes.append_array(digest.hex_decode())
	_append_u32(bytes, receipt.source_catalog_schema_version)
	_append_u32(bytes, receipt.target_catalog_schema_version)
	_append_u32(bytes, receipt.from_codec)
	_append_u32(bytes, receipt.to_codec)
	return _sha256(bytes)

func validate_pack(
	pack: ContentGenerationMigrationPackV2,
	allowlist: Array[ContentGenerationMigrationAllowlistEntryV2]
) -> bool:
	if pack == null or pack_digest(pack) != pack.pack_digest:
		return false
	var previous := ""
	for entry: ContentGenerationMigrationEntryV2 in pack.mappings:
		var current := "%s%s%s" % [
			entry.source_category, String.chr(0), entry.source_id
		]
		if not previous.is_empty() and current <= previous:
			return false
		previous = current
		if entry.requirement not in [1, 2] \
			or entry.mapping_kind not in [1, 2, 3]:
			return false
		if entry.mapping_kind == 3 and entry.has_target:
			return false
		if entry.mapping_kind != 3 and not entry.has_target:
			return false
		if entry.requirement == 1 and entry.mapping_kind == 3:
			return false
	for allowed: ContentGenerationMigrationAllowlistEntryV2 in allowlist:
		if allowed.matches(pack):
			return true
	return false

func _append_text(bytes: PackedByteArray, value: String) -> void:
	var raw := value.to_utf8_buffer()
	_append_u32(bytes, raw.size())
	bytes.append_array(raw)

func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xff)
	bytes.append((value >> 16) & 0xff)
	bytes.append((value >> 8) & 0xff)
	bytes.append(value & 0xff)

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
