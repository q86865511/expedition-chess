class_name ContentValidationInput
extends RefCounted

var definitions: Array[ContentDefinition] = []
var aliases: Array[ContentAliasValue] = []
var tombstones: Array[ContentTombstoneValue] = []
var dependency_port: ContentDependencyPort
var base_population_cap: int = 9

func _init(
	p_definitions: Array[ContentDefinition] = [],
	p_aliases: Array[ContentAliasValue] = [],
	p_tombstones: Array[ContentTombstoneValue] = [],
	p_dependency_port: ContentDependencyPort = null,
	p_base_population_cap: int = 9
) -> void:
	for definition in p_definitions: definitions.append(definition.duplicate(true))
	for alias in p_aliases: aliases.append(alias.deep_clone())
	for tombstone in p_tombstones: tombstones.append(tombstone.deep_clone())
	dependency_port = p_dependency_port
	base_population_cap = p_base_population_cap

func deep_clone() -> ContentValidationInput:
	return ContentValidationInput.new(definitions, aliases, tombstones, dependency_port, base_population_cap)
