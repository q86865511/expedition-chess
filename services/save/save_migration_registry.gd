class_name SaveMigrationRegistry
extends RefCounted

var _codec: SaveJsonCodec

func _init(codec: SaveJsonCodec) -> void:
	_codec = codec

func migrate(raw_json_text: String) -> MigrationResult:
	var parser := JSON.new()
	if parser.parse(raw_json_text) != OK or not parser.data is Dictionary:
		return MigrationResult.failure(
			UnknownSourceSchemaVersion.new(),
			MigrationError.new(MigrationError.PARSE_INVALID, &"root")
		)
	var data: Dictionary = parser.data
	if not data.has("schema_version"):
		return MigrationResult.failure(
			UnknownSourceSchemaVersion.new(),
			MigrationError.new(MigrationError.PARSE_INVALID, &"schema_version")
		)
	var schema_value: Variant = data["schema_version"]
	if not schema_value is int and not (schema_value is float and floor(schema_value) == schema_value):
		return MigrationResult.failure(
			UnknownSourceSchemaVersion.new(),
			MigrationError.new(MigrationError.PARSE_INVALID, &"schema_version")
		)
	var source_schema := int(schema_value)
	var known := KnownSourceSchemaVersion.new(source_schema)
	if source_schema < 0 or source_schema > SaveJsonCodec.SCHEMA_VERSION:
		return MigrationResult.failure(
			known,
			MigrationError.new(MigrationError.STEP_MISSING, &"schema_version")
		)
	if source_schema == SaveJsonCodec.SCHEMA_VERSION:
		var decoded := _codec.decode_text(raw_json_text)
		if not decoded.ok or decoded.root == null:
			return MigrationResult.failure(
				known,
				MigrationError.new(MigrationError.PARSE_INVALID, &"root")
			)
		return MigrationResult.success(known, raw_json_text, decoded.root, decoded.incompatible_content_ids)
	if source_schema != 0:
		return MigrationResult.failure(
			known,
			MigrationError.new(MigrationError.STEP_MISSING, &"schema_version")
		)
	var expected_schema_zero: Array[String] = [
		"schema_version", "content_version", "app_version", "rng_version",
		"saved_at_utc", "profile", "run"
	]
	if data.size() != expected_schema_zero.size():
		return MigrationResult.failure(
			known, MigrationError.new(MigrationError.PARSE_INVALID, &"root")
		)
	for key: String in expected_schema_zero:
		if not data.has(key):
			return MigrationResult.failure(
				known,
				MigrationError.new(MigrationError.PARSE_INVALID, StringName("root.%s" % key))
			)
	data["schema_version"] = 1
	data["hash_version"] = 1
	var decoded_zero: SaveDecodeResult = _codec._decode_root(data)
	if not decoded_zero.ok or decoded_zero.root == null:
		return MigrationResult.failure(
			known,
			MigrationError.new(MigrationError.PARSE_INVALID, &"root")
		)
	var encoded := _codec.encode(decoded_zero.root)
	if not encoded.ok:
		return MigrationResult.failure(
			known,
			MigrationError.new(MigrationError.PARSE_INVALID, encoded.error.field_path)
		)
	return MigrationResult.success(
		known, encoded.json_text.value, decoded_zero.root, decoded_zero.incompatible_content_ids
	)
