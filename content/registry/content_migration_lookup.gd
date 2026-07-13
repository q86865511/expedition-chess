class_name ContentMigrationLookup
extends RefCounted

enum Kind { MISSING, ACTIVE, ALIAS, TOMBSTONE }

var kind: Kind
var category: StringName
var resolved_id: StringName
var tombstone: ContentTombstoneValue

static func missing() -> ContentMigrationLookup:
	return ContentMigrationLookup.new()

static func active(p_category: StringName, p_id: StringName) -> ContentMigrationLookup:
	var result := ContentMigrationLookup.new()
	result.kind = Kind.ACTIVE
	result.category = p_category
	result.resolved_id = p_id
	return result

static func alias(p_category: StringName, p_id: StringName) -> ContentMigrationLookup:
	var result := active(p_category, p_id)
	result.kind = Kind.ALIAS
	return result

static func tombstone_value(value: ContentTombstoneValue) -> ContentMigrationLookup:
	var result := ContentMigrationLookup.new()
	result.kind = Kind.TOMBSTONE
	result.category = value.category
	result.tombstone = value.deep_clone()
	return result
