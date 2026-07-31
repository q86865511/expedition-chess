class_name ContentGenerationMigrationCodecV2
extends RefCounted

## CGM2／CGR2 exact contract(design.md「CGM2／CGR2 exact migration contract」)。
## B4(b) 硬化:mapping entry 的語意約束(IDENTITY 同 ID、ALIAS 異 ID、TOMBSTONE 無
## target、single-hop、非空 pack)全部在 codec 層 fail-closed;digest 排序依規格的
## 「(source_category bytes, source_id bytes) 升冪」而非編碼後 bytes 的字典序
## (framed length prefix 會讓兩者在 category 長度不同時發散)。

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
	var ordered: Array[ContentGenerationMigrationEntryV2] = []
	for value: ContentGenerationMigrationEntryV2 in entries:
		if value == null:
			return ""
		ordered.append(value)
	ordered.sort_custom(_entry_less)
	var encoded_entries: Array[PackedByteArray] = []
	for value: ContentGenerationMigrationEntryV2 in ordered:
		var encoded := encode_entry(value)
		if encoded.is_empty():
			return ""
		encoded_entries.append(encoded)
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
			return _bytes_less(left[0].to_utf8_buffer(), right[0].to_utf8_buffer())
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
		if not _is_digest(digest):
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
		if not _is_digest(digest):
			return ""
	var bytes := "CGR2".to_ascii_buffer()
	for digest: String in digests:
		bytes.append_array(digest.hex_decode())
	_append_u32(bytes, receipt.source_catalog_schema_version)
	_append_u32(bytes, receipt.target_catalog_schema_version)
	_append_u32(bytes, receipt.from_codec)
	_append_u32(bytes, receipt.to_codec)
	return _sha256(bytes)


## try_reject:回 null 代表 pack 合法;否則回具名 error(code + field path)。
func try_reject_pack(
	pack: ContentGenerationMigrationPackV2,
	allowlist: Array[ContentGenerationMigrationAllowlistEntryV2]
) -> ContentGenerationMigrationError:
	if pack == null:
		return _error(ContentGenerationMigrationError.PACK_INVALID, &"migration_pack")
	# exact allowlist 的前提是 pack 必須真的列舉 mapping;空 mappings 的 pack
	# 等於「任何 source id 都無約束」,一律拒絕(B4 攻擊面)。
	if pack.mappings.is_empty():
		return _error(
			ContentGenerationMigrationError.MAPPING_INVALID,
			&"migration_pack.mappings"
		)
	if pack.source_content_version.is_empty() \
		or pack.target_content_version.is_empty():
		return _error(
			ContentGenerationMigrationError.PACK_INVALID,
			&"migration_pack.content_version"
		)
	if pack_digest(pack) != pack.pack_digest:
		return _error(
			ContentGenerationMigrationError.PACK_INVALID,
			&"migration_pack.pack_digest"
		)
	var source_keys: Dictionary = {}
	var previous := PackedByteArray()
	for entry: ContentGenerationMigrationEntryV2 in pack.mappings:
		var entry_error := _validate_entry(entry)
		if entry_error != null:
			return entry_error
		var current := _sort_key(entry)
		if not previous.is_empty() and not _bytes_less(previous, current):
			return _error(
				ContentGenerationMigrationError.MAPPING_INVALID,
				&"migration_pack.mappings.order"
			)
		previous = current
		source_keys[_namespaced_key(entry.source_category, entry.source_id)] = true
	# single hop:alias/identity 的 target 不得同時是另一筆 mapping 的 source
	# (alias chain / cycle / alias target 亦為 source 全部落在此判斷)。
	for entry: ContentGenerationMigrationEntryV2 in pack.mappings:
		if entry.mapping_kind != ContentGenerationMigrationEntryV2.MappingKind.ALIAS:
			continue
		if source_keys.has(_namespaced_key(entry.source_category, entry.target_id)):
			return _error(
				ContentGenerationMigrationError.MAPPING_INVALID,
				&"migration_pack.mappings.alias_chain"
			)
	for allowed: ContentGenerationMigrationAllowlistEntryV2 in allowlist:
		if allowed.matches(pack):
			return null
	return _error(
		ContentGenerationMigrationError.PACK_NOT_ALLOWLISTED,
		&"migration_pack.pack_digest"
	)


func _validate_entry(
	entry: ContentGenerationMigrationEntryV2
) -> ContentGenerationMigrationError:
	if entry == null or entry.source_category.is_empty() or entry.source_id.is_empty():
		return _error(
			ContentGenerationMigrationError.MAPPING_INVALID,
			&"migration_pack.mappings.source"
		)
	if entry.requirement not in [
		ContentGenerationMigrationEntryV2.Requirement.REQUIRED,
		ContentGenerationMigrationEntryV2.Requirement.OPTIONAL,
	]:
		return _error(
			ContentGenerationMigrationError.MAPPING_INVALID,
			&"migration_pack.mappings.requirement"
		)
	match entry.mapping_kind:
		ContentGenerationMigrationEntryV2.MappingKind.IDENTITY:
			if not entry.has_target or entry.target_id != entry.source_id \
				or not _is_digest(entry.target_entry_digest):
				return _error(
					ContentGenerationMigrationError.MAPPING_INVALID,
					&"migration_pack.mappings.identity"
				)
		ContentGenerationMigrationEntryV2.MappingKind.ALIAS:
			if not entry.has_target or entry.target_id.is_empty() \
				or entry.target_id == entry.source_id \
				or not _is_digest(entry.target_entry_digest):
				return _error(
					ContentGenerationMigrationError.MAPPING_INVALID,
					&"migration_pack.mappings.alias"
				)
		ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE:
			# REQUIRED tombstone 無法對應任何 target,規格禁止。
			if entry.has_target or not entry.target_id.is_empty() \
				or not entry.target_entry_digest.is_empty() \
				or entry.requirement \
					!= ContentGenerationMigrationEntryV2.Requirement.OPTIONAL:
				return _error(
					ContentGenerationMigrationError.MAPPING_INVALID,
					&"migration_pack.mappings.tombstone"
				)
		_:
			return _error(
				ContentGenerationMigrationError.MAPPING_INVALID,
				&"migration_pack.mappings.mapping_kind"
			)
	return null


func _sort_key(entry: ContentGenerationMigrationEntryV2) -> PackedByteArray:
	var bytes := entry.source_category.to_utf8_buffer()
	# 0x00 不會出現在 strict UTF-8 的 category/id 內容中,可作為欄位分隔。
	bytes.append(0)
	bytes.append_array(entry.source_id.to_utf8_buffer())
	return bytes


func _entry_less(
	left: ContentGenerationMigrationEntryV2,
	right: ContentGenerationMigrationEntryV2
) -> bool:
	return _bytes_less(_sort_key(left), _sort_key(right))


func _namespaced_key(category: String, content_id: String) -> String:
	return "%s/%s" % [category, content_id]


func _bytes_less(left: PackedByteArray, right: PackedByteArray) -> bool:
	var shared: int = mini(left.size(), right.size())
	for index: int in shared:
		if left[index] != right[index]:
			return left[index] < right[index]
	return left.size() < right.size()


func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


func _error(
	code: StringName,
	field_path: StringName
) -> ContentGenerationMigrationError:
	return ContentGenerationMigrationError.new(code, field_path)


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
