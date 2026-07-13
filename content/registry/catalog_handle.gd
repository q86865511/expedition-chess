class_name CatalogHandle
extends RefCounted

var manifest_digest: String
var content_version: String
var is_latest: bool

func _init(p_digest: String = "", p_version: String = "", p_is_latest: bool = false) -> void:
	manifest_digest = p_digest
	content_version = p_version
	is_latest = p_is_latest

func deep_clone() -> CatalogHandle:
	return CatalogHandle.new(manifest_digest, content_version, is_latest)
