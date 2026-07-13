class_name StoredSaveCandidate
extends RefCounted

var logical_path: StringName
var exists: bool
var valid: bool
var bytes: PackedByteArray
var decoded: SaveDecodeResult
var storage_error: StorageError
var codec_error: SaveCodecError

static func missing(path: StringName) -> StoredSaveCandidate:
	return StoredSaveCandidate.new(path, false, false, PackedByteArray(), null, null, null)

static func invalid(
	path: StringName,
	p_bytes: PackedByteArray = PackedByteArray(),
	p_codec_error: SaveCodecError = null
) -> StoredSaveCandidate:
	return StoredSaveCandidate.new(
		path, true, false, p_bytes, null, null, p_codec_error
	)

static func io_failure(path: StringName, error: StorageError) -> StoredSaveCandidate:
	return StoredSaveCandidate.new(path, true, false, PackedByteArray(), null, error, null)

static func decoded_value(path: StringName, p_bytes: PackedByteArray, result: SaveDecodeResult) -> StoredSaveCandidate:
	return StoredSaveCandidate.new(path, true, result.ok, p_bytes, result, null, null)

func _init(
	p_logical_path: StringName,
	p_exists: bool,
	p_valid: bool,
	p_bytes: PackedByteArray,
	p_decoded: SaveDecodeResult,
	p_storage_error: StorageError,
	p_codec_error: SaveCodecError
) -> void:
	logical_path = p_logical_path
	exists = p_exists
	valid = p_valid
	bytes = p_bytes.duplicate()
	decoded = p_decoded
	storage_error = p_storage_error.deep_clone() if p_storage_error != null else null
	codec_error = p_codec_error.deep_clone() if p_codec_error != null else null
