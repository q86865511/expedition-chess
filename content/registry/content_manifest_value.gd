class_name ContentManifestValue
extends RefCounted

var catalog_schema_version: int = 1
var content_version: String
var pack_ids: Array[StringName] = []
var aliases: Array[ContentAliasValue] = []
var tombstones: Array[ContentTombstoneValue] = []
var entry_indexes: Array[ContentEntryIndexValue] = []

func deep_clone() -> ContentManifestValue:
	var result := ContentManifestValue.new()
	result.catalog_schema_version = catalog_schema_version
	result.content_version = content_version
	result.pack_ids = pack_ids.duplicate()
	for value in aliases:
		result.aliases.append(value.deep_clone())
	for value in tombstones:
		result.tombstones.append(value.deep_clone())
	for value in entry_indexes:
		result.entry_indexes.append(value.deep_clone())
	return result
