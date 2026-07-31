class_name ContentGenerationMigrationEntryV2
extends RefCounted

enum Requirement { REQUIRED = 1, OPTIONAL = 2 }
enum MappingKind { IDENTITY = 1, ALIAS = 2, TOMBSTONE = 3 }

var source_category: String
var source_id: String
var requirement: Requirement
var mapping_kind: MappingKind
var has_target: bool
var target_id: String
var target_entry_digest: String

func _init(
	p_source_category: String,
	p_source_id: String,
	p_requirement: int,
	p_mapping_kind: int,
	p_has_target: bool,
	p_target_id: String,
	p_target_entry_digest: String
) -> void:
	source_category = p_source_category
	source_id = p_source_id
	requirement = p_requirement
	mapping_kind = p_mapping_kind
	has_target = p_has_target
	target_id = p_target_id
	target_entry_digest = p_target_entry_digest

func deep_clone() -> ContentGenerationMigrationEntryV2:
	return ContentGenerationMigrationEntryV2.new(
		source_category,
		source_id,
		requirement,
		mapping_kind,
		has_target,
		target_id,
		target_entry_digest
	)
