class_name ContentDefinitionCompilerV3
extends ContentDefinitionCompiler

func _init() -> void:
	super(ContentCanonicalCodecV3.new(), 3)

func _supports_resource_schema(definition: ContentDefinition) -> bool:
	if definition == null:
		return false
	if definition is UnitDef or definition is EffectDef:
		return definition.schema_version == 2
	return definition.schema_version == 1
