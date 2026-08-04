class_name ForgeRecipeTableBuilder
extends RefCounted

func build(
	registry: ContentRegistryService,
	manifest_digest: String,
	equipment_ids: Array[StringName]
) -> ForgeRecipeTableBuildResult:
	if registry == null or manifest_digest.length() != 64:
		return ForgeRecipeTableBuildResult.failure(ForgeRecipeTableError.INPUT_INVALID, &"manifest_digest")
	var recipes: Array[ForgeRecipeRule] = []
	var sorted_ids: Array[StringName] = equipment_ids.duplicate()
	sorted_ids.sort_custom(StableNameSort.id_less)
	for equipment_id: StringName in sorted_ids:
		if not StableIdValidator.new().is_valid(equipment_id):
			return ForgeRecipeTableBuildResult.failure(ForgeRecipeTableError.INPUT_INVALID, &"equipment_ids", equipment_id)
		var resolved := registry.resolve(ContentRef.new(manifest_digest, equipment_id))
		if not resolved.ok:
			return ForgeRecipeTableBuildResult.failure(ForgeRecipeTableError.RESOLVE_FAILED, resolved.error.field_path, equipment_id)
		var view: ContentDefinitionView = resolved.value
		if view.category != &"equipment":
			return ForgeRecipeTableBuildResult.failure(ForgeRecipeTableError.CATEGORY_MISMATCH, &"category", equipment_id)
		if view.payload == null or view.payload.record_type != ContentCategory.EQUIPMENT or view.payload.children.size() != 7:
			return ForgeRecipeTableBuildResult.failure(ForgeRecipeTableError.PAYLOAD_INVALID, &"equipment.payload", equipment_id)
		var recipe := ForgeRecipeRule.new()
		recipe.equipment_id = view.content_id
		recipe.component_ids = _names(view.payload.children[3])
		if recipe.component_ids.size() < 1 or recipe.component_ids.size() > 2:
			return ForgeRecipeTableBuildResult.failure(ForgeRecipeTableError.PAYLOAD_INVALID, &"equipment.component_pair", equipment_id)
		recipes.append(recipe)
	recipes.sort_custom(_recipe_less)
	return ForgeRecipeTableBuildResult.success(ForgeRecipeTable.new(manifest_digest, recipes))

func _names(value: ContentValue) -> Array[StringName]:
	var result: Array[StringName] = []
	if value == null:
		return result
	for child: ContentValue in value.children:
		result.append(StringName(child.string_value))
	return result

func _recipe_less(left: ForgeRecipeRule, right: ForgeRecipeRule) -> bool:
	return String(left.equipment_id) < String(right.equipment_id)
