class_name ContentRef
extends RefCounted

var manifest_digest: String
var content_id: StringName

func _init(p_manifest_digest: String = "", p_content_id: StringName = &"") -> void:
	manifest_digest = p_manifest_digest
	content_id = p_content_id

func is_valid() -> bool:
	if manifest_digest.length() != 64 or not StableIdValidator.new().is_valid(content_id):
		return false
	for code in manifest_digest.to_ascii_buffer():
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true
