extends GutTest

const SOURCE_DIGEST: String = "1111111111111111111111111111111111111111111111111111111111111111"
const TARGET_DIGEST: String = "2222222222222222222222222222222222222222222222222222222222222222"
const CONFIG_DIGEST: String = "463ac1f542a942fb1dc8c3dea7f7647295e4635f9b02c57be7c3ea0a15bcaaa6"
const MAPPING_DIGEST: String = "2f7b38387cf9a69a2f9fa03f20b690f0098f5411097a4f96aa259db21076d2b9"
const PACK_DIGEST: String = "20d34a4e5b489b1bad34f7d86005d757442f4922ef73b8369a703aedc1920b15"
const RECEIPT_DIGEST: String = "7c2ef65221a2ad4a84b923786500b2a974e560b6068e5a83393e783ae1524f65"
const BSM1_BYTES: String = "42534d31000000020000000e656e636f756e7465722e626f7373000000000000000a626f73735f616c7068610000000e656e636f756e7465722e626f73730000000100000009626f73735f62657461"


func test_bsm1_cgm1_and_cgr1_golden_vectors_are_stable() -> void:
	var codec := ContentGenerationMigrationCodec.new()
	var pack := _pack(codec)
	assert_eq(codec.boss_mapping_bytes(pack.boss_mapping_entries).hex_encode(), BSM1_BYTES)
	assert_eq(codec.boss_mapping_digest(pack.boss_mapping_entries), MAPPING_DIGEST)
	assert_eq(codec.pack_digest(pack), PACK_DIGEST)
	var allowlist := _allowlist()
	var validated := codec.validate_pack(pack, allowlist)
	assert_true(validated.ok)
	assert_not_null(validated.receipt)
	assert_eq(validated.receipt.receipt_digest, RECEIPT_DIGEST)
	assert_eq(validated.receipt.source_manifest_digest, SOURCE_DIGEST)
	assert_eq(validated.receipt.target_manifest_digest, TARGET_DIGEST)
	assert_eq(validated.receipt.from_codec, 1)
	assert_eq(validated.receipt.to_codec, 2)


func test_bsm1_rejects_unsorted_duplicate_and_invalid_spawn_entries() -> void:
	var codec := ContentGenerationMigrationCodec.new()
	var unsorted: Array[BossSourceMigrationEntryV1] = [
		BossSourceMigrationEntryV1.new(&"encounter.boss", 1, "boss_beta"),
		BossSourceMigrationEntryV1.new(&"encounter.boss", 0, "boss_alpha"),
	]
	assert_true(codec.boss_mapping_bytes(unsorted).is_empty())
	var duplicate: Array[BossSourceMigrationEntryV1] = [
		BossSourceMigrationEntryV1.new(&"encounter.boss", 0, "boss_alpha"),
		BossSourceMigrationEntryV1.new(&"encounter.boss", 0, "boss_beta"),
	]
	assert_true(codec.boss_mapping_bytes(duplicate).is_empty())
	var invalid_spawn: Array[BossSourceMigrationEntryV1] = [
		BossSourceMigrationEntryV1.new(&"encounter.boss", 0, "Boss Alpha"),
	]
	assert_true(codec.boss_mapping_bytes(invalid_spawn).is_empty())


func test_pack_validation_recomputes_every_digest_and_requires_allowlist() -> void:
	var codec := ContentGenerationMigrationCodec.new()
	var valid := _pack(codec)
	var no_allowlist: Array[ContentGenerationMigrationAllowlistEntry] = []
	var rejected := codec.validate_pack(valid, no_allowlist)
	assert_false(rejected.ok)
	assert_eq(rejected.error.code, ContentGenerationMigrationError.PACK_NOT_ALLOWLISTED)
	var wrong_source: Array[ContentGenerationMigrationAllowlistEntry] = [
		ContentGenerationMigrationAllowlistEntry.new("fixture.wrong", SOURCE_DIGEST, PACK_DIGEST),
	]
	var wrong_source_result := codec.validate_pack(valid, wrong_source)
	assert_false(wrong_source_result.ok)
	assert_eq(
		wrong_source_result.error.code,
		ContentGenerationMigrationError.PACK_NOT_ALLOWLISTED
	)
	var wrong_manifest: Array[ContentGenerationMigrationAllowlistEntry] = [
		ContentGenerationMigrationAllowlistEntry.new("fixture.1", TARGET_DIGEST, PACK_DIGEST),
	]
	assert_eq(
		codec.validate_pack(valid, wrong_manifest).error.code,
		ContentGenerationMigrationError.PACK_NOT_ALLOWLISTED
	)
	var wrong_pack: Array[ContentGenerationMigrationAllowlistEntry] = [
		ContentGenerationMigrationAllowlistEntry.new("fixture.1", SOURCE_DIGEST, TARGET_DIGEST),
	]
	assert_eq(
		codec.validate_pack(valid, wrong_pack).error.code,
		ContentGenerationMigrationError.PACK_NOT_ALLOWLISTED
	)

	var allowlist := _allowlist()
	var tampered_config := _pack(codec)
	tampered_config.combat_config_entry_bytes.append(0)
	_assert_pack_invalid(codec.validate_pack(tampered_config, allowlist))

	var tampered_mapping := _pack(codec)
	tampered_mapping.boss_mapping_entries[0].source_spawn_key = "boss_changed"
	_assert_pack_invalid(codec.validate_pack(tampered_mapping, allowlist))

	var tampered_pack_digest := _pack(codec)
	tampered_pack_digest.pack_digest = SOURCE_DIGEST
	_assert_pack_invalid(codec.validate_pack(tampered_pack_digest, allowlist))

	var tampered_target := _pack(codec)
	tampered_target.expected_target_manifest_digest = SOURCE_DIGEST
	_assert_pack_invalid(codec.validate_pack(tampered_target, allowlist))


func test_cgm1_rejects_tampering_of_every_pack_field() -> void:
	var codec := ContentGenerationMigrationCodec.new()
	var allowlist := _allowlist()
	var source_version := _pack(codec)
	source_version.source_content_version = "fixture.changed"
	_assert_pack_invalid(codec.validate_pack(source_version, allowlist))
	var source_manifest := _pack(codec)
	source_manifest.source_manifest_digest = TARGET_DIGEST
	_assert_pack_invalid(codec.validate_pack(source_manifest, allowlist))
	var target_version := _pack(codec)
	target_version.target_content_version = "fixture.changed"
	_assert_pack_invalid(codec.validate_pack(target_version, allowlist))
	var target_manifest := _pack(codec)
	target_manifest.expected_target_manifest_digest = SOURCE_DIGEST
	_assert_pack_invalid(codec.validate_pack(target_manifest, allowlist))
	var config_bytes := _pack(codec)
	config_bytes.combat_config_entry_bytes[0] ^= 1
	_assert_pack_invalid(codec.validate_pack(config_bytes, allowlist))
	var config_digest := _pack(codec)
	config_digest.combat_config_entry_digest = SOURCE_DIGEST
	_assert_pack_invalid(codec.validate_pack(config_digest, allowlist))
	var mapping_entry := _pack(codec)
	mapping_entry.boss_mapping_entries[0].source_spawn_key = "changed"
	_assert_pack_invalid(codec.validate_pack(mapping_entry, allowlist))
	var mapping_digest := _pack(codec)
	mapping_digest.boss_mapping_digest = SOURCE_DIGEST
	_assert_pack_invalid(codec.validate_pack(mapping_digest, allowlist))
	var from_codec := _pack(codec)
	from_codec.from_codec = 0
	_assert_pack_invalid(codec.validate_pack(from_codec, allowlist))
	var to_codec := _pack(codec)
	to_codec.to_codec = 3
	_assert_pack_invalid(codec.validate_pack(to_codec, allowlist))
	var pack_digest := _pack(codec)
	pack_digest.pack_digest = SOURCE_DIGEST
	_assert_pack_invalid(codec.validate_pack(pack_digest, allowlist))


func test_cgr1_rejects_tampering_of_every_receipt_field() -> void:
	var codec := ContentGenerationMigrationCodec.new()
	var receipt := codec.validate_pack(_pack(codec), _allowlist()).receipt
	assert_true(codec.validate_receipt(receipt))
	var source_manifest := receipt.deep_clone()
	source_manifest.source_manifest_digest = TARGET_DIGEST
	assert_false(codec.validate_receipt(source_manifest))
	var target_manifest := receipt.deep_clone()
	target_manifest.target_manifest_digest = SOURCE_DIGEST
	assert_false(codec.validate_receipt(target_manifest))
	var config_digest := receipt.deep_clone()
	config_digest.combat_config_entry_digest = SOURCE_DIGEST
	assert_false(codec.validate_receipt(config_digest))
	var mapping_digest := receipt.deep_clone()
	mapping_digest.boss_mapping_digest = SOURCE_DIGEST
	assert_false(codec.validate_receipt(mapping_digest))
	var pack_digest := receipt.deep_clone()
	pack_digest.pack_digest = SOURCE_DIGEST
	assert_false(codec.validate_receipt(pack_digest))
	var from_codec := receipt.deep_clone()
	from_codec.from_codec = 0
	assert_false(codec.validate_receipt(from_codec))
	var to_codec := receipt.deep_clone()
	to_codec.to_codec = 3
	assert_false(codec.validate_receipt(to_codec))
	var receipt_digest := receipt.deep_clone()
	receipt_digest.receipt_digest = SOURCE_DIGEST
	assert_false(codec.validate_receipt(receipt_digest))


func _pack(codec: ContentGenerationMigrationCodec) -> ContentGenerationMigrationPackV1:
	var entries: Array[BossSourceMigrationEntryV1] = [
		BossSourceMigrationEntryV1.new(&"encounter.boss", 0, "boss_alpha"),
		BossSourceMigrationEntryV1.new(&"encounter.boss", 1, "boss_beta"),
	]
	var pack := ContentGenerationMigrationPackV1.new(
		"fixture.1",
		SOURCE_DIGEST,
		"fixture.2",
		TARGET_DIGEST,
		"config-v2-canonical".to_ascii_buffer(),
		CONFIG_DIGEST,
		entries,
		MAPPING_DIGEST,
		1,
		2,
		PACK_DIGEST
	)
	assert_eq(codec.pack_digest(pack), PACK_DIGEST)
	return pack


func _assert_pack_invalid(result: ContentGenerationMigrationValidationResult) -> void:
	assert_false(result.ok)
	assert_not_null(result.error)
	assert_eq(result.error.code, ContentGenerationMigrationError.PACK_INVALID)


func _allowlist() -> Array[ContentGenerationMigrationAllowlistEntry]:
	return [ContentGenerationMigrationAllowlistEntry.new("fixture.1", SOURCE_DIGEST, PACK_DIGEST)]
