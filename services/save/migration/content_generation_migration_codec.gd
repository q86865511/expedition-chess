class_name ContentGenerationMigrationCodec
extends RefCounted

const _DIGEST_PATTERN: String = "^[0-9a-f]{64}$"
const _SPAWN_PATTERN: String = "^[a-z][a-z0-9_]{0,63}$"

func boss_mapping_bytes(entries: Array[BossSourceMigrationEntryV1]) -> PackedByteArray:
	if not _entries_valid(entries):
		return PackedByteArray()
	var bytes := "BSM1".to_ascii_buffer()
	_append_u32(bytes, entries.size())
	for entry: BossSourceMigrationEntryV1 in entries:
		_append_ascii(bytes, String(entry.encounter_id))
		_append_u32(bytes, entry.phase_index)
		_append_ascii(bytes, entry.source_spawn_key)
	return bytes

func boss_mapping_digest(entries: Array[BossSourceMigrationEntryV1]) -> String:
	var bytes := boss_mapping_bytes(entries)
	return _sha256(bytes) if not bytes.is_empty() else ""

func pack_digest(pack: ContentGenerationMigrationPackV1) -> String:
	if pack == null or pack.from_codec != 1 or pack.to_codec != 2:
		return ""
	if not _content_version(pack.source_content_version) \
		or not _content_version(pack.target_content_version) \
		or pack.source_content_version == pack.target_content_version:
		return ""
	if not _digest(pack.source_manifest_digest) \
		or not _digest(pack.expected_target_manifest_digest) \
		or not _digest(pack.combat_config_entry_digest) \
		or not _digest(pack.boss_mapping_digest):
		return ""
	var bytes := "CGM1".to_ascii_buffer()
	_append_utf8(bytes, pack.source_content_version)
	_append_utf8(bytes, pack.target_content_version)
	bytes.append_array(pack.source_manifest_digest.hex_decode())
	bytes.append_array(pack.expected_target_manifest_digest.hex_decode())
	bytes.append_array(pack.combat_config_entry_digest.hex_decode())
	bytes.append_array(pack.boss_mapping_digest.hex_decode())
	_append_u32(bytes, pack.from_codec)
	_append_u32(bytes, pack.to_codec)
	return _sha256(bytes)

func validate_pack(
	pack: ContentGenerationMigrationPackV1,
	allowlist: Array[ContentGenerationMigrationAllowlistEntry]
) -> ContentGenerationMigrationValidationResult:
	if pack == null:
		return _failure(&"migration_pack")
	var mapping_digest := boss_mapping_digest(pack.boss_mapping_entries)
	var config_digest := _sha256(pack.combat_config_entry_bytes)
	var expected_pack_digest := pack_digest(pack)
	if pack.combat_config_entry_bytes.is_empty() \
		or mapping_digest.is_empty() \
		or mapping_digest != pack.boss_mapping_digest \
		or config_digest != pack.combat_config_entry_digest \
		or expected_pack_digest != pack.pack_digest:
		return _failure(&"migration_pack.digest")
	var allowlisted := false
	for entry: ContentGenerationMigrationAllowlistEntry in allowlist:
		if entry != null and entry.matches(pack):
			allowlisted = true
			break
	if not allowlisted:
		return ContentGenerationMigrationValidationResult.failure(
			ContentGenerationMigrationError.new(
				ContentGenerationMigrationError.PACK_NOT_ALLOWLISTED,
				&"migration_pack.pack_digest"
			)
		)
	var receipt_digest := _receipt_digest(pack)
	if receipt_digest.is_empty():
		return _failure(&"migration_receipt")
	return ContentGenerationMigrationValidationResult.success(
		ContentGenerationMigrationReceipt.new(
			pack.source_manifest_digest,
			pack.expected_target_manifest_digest,
			pack.combat_config_entry_digest,
			pack.boss_mapping_digest,
			pack.pack_digest,
			pack.from_codec,
			pack.to_codec,
			receipt_digest
		)
	)

func _receipt_digest(pack: ContentGenerationMigrationPackV1) -> String:
	var digests: Array[String] = [
		pack.source_manifest_digest,
		pack.expected_target_manifest_digest,
		pack.combat_config_entry_digest,
		pack.boss_mapping_digest,
		pack.pack_digest,
	]
	return _receipt_digest_values(digests, pack.from_codec, pack.to_codec)

func validate_receipt(receipt: ContentGenerationMigrationReceipt) -> bool:
	if receipt == null:
		return false
	var digests: Array[String] = [
		receipt.source_manifest_digest,
		receipt.target_manifest_digest,
		receipt.combat_config_entry_digest,
		receipt.boss_mapping_digest,
		receipt.pack_digest,
	]
	var expected := _receipt_digest_values(digests, receipt.from_codec, receipt.to_codec)
	return not expected.is_empty() and expected == receipt.receipt_digest

func _receipt_digest_values(
	digests: Array[String],
	from_codec: int,
	to_codec: int
) -> String:
	if from_codec != 1 or to_codec != 2:
		return ""
	for value: String in digests:
		if not _digest(value):
			return ""
	var bytes := "CGR1".to_ascii_buffer()
	for value: String in digests:
		bytes.append_array(value.hex_decode())
	_append_u32(bytes, from_codec)
	_append_u32(bytes, to_codec)
	return _sha256(bytes)

func _entries_valid(entries: Array[BossSourceMigrationEntryV1]) -> bool:
	var stable := StableIdValidator.new()
	var spawn_regex := RegEx.new()
	if spawn_regex.compile(_SPAWN_PATTERN) != OK:
		return false
	var previous := ""
	for entry: BossSourceMigrationEntryV1 in entries:
		if entry == null or not stable.is_valid(entry.encounter_id) \
			or entry.phase_index < 0 or entry.phase_index > 0xffffffff \
			or spawn_regex.search(entry.source_spawn_key) == null:
			return false
		var key := "%s/%010d" % [String(entry.encounter_id), entry.phase_index]
		if key <= previous:
			return false
		previous = key
	return true

func _append_ascii(bytes: PackedByteArray, value: String) -> void:
	var raw := value.to_ascii_buffer()
	_append_u32(bytes, raw.size())
	bytes.append_array(raw)

func _append_utf8(bytes: PackedByteArray, value: String) -> void:
	var raw := value.to_utf8_buffer()
	_append_u32(bytes, raw.size())
	bytes.append_array(raw)

func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xff)
	bytes.append((value >> 16) & 0xff)
	bytes.append((value >> 8) & 0xff)
	bytes.append(value & 0xff)

func _digest(value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile(_DIGEST_PATTERN) == OK and expression.search(value) != null

func _content_version(value: String) -> bool:
	if value.is_empty():
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 0x21 or byte > 0x7e:
			return false
	return true

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK \
		or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

func _failure(path: StringName) -> ContentGenerationMigrationValidationResult:
	return ContentGenerationMigrationValidationResult.failure(
		ContentGenerationMigrationError.new(
			ContentGenerationMigrationError.PACK_INVALID,
			path
		)
	)
