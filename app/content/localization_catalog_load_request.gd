class_name LocalizationCatalogLoadRequest
extends RefCounted

var source_id: StringName
var expected_sha256: String
var _source_bytes: PackedByteArray

func _init(
	p_source_id: StringName,
	p_source_bytes: PackedByteArray,
	p_expected_sha256: String
) -> void:
	source_id = p_source_id
	_source_bytes = p_source_bytes.duplicate()
	expected_sha256 = p_expected_sha256

func source_bytes_copy() -> PackedByteArray:
	return _source_bytes.duplicate()
