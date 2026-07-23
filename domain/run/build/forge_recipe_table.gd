class_name ForgeRecipeTable
extends RefCounted

var _manifest_digest: String
var _recipes: Array[ForgeRecipeRule] = []

func _init(manifest_digest: String, recipes: Array[ForgeRecipeRule]) -> void:
	_manifest_digest = manifest_digest
	for value: ForgeRecipeRule in recipes:
		_recipes.append(value.deep_clone())

func manifest_digest_value() -> String:
	return _manifest_digest

func recipe_count() -> int:
	return _recipes.size()

func try_recipe(component_a: StringName, component_b: StringName) -> ForgeRecipeRule:
	var key := _canonical_key([component_a, component_b])
	for value: ForgeRecipeRule in _recipes:
		if _canonical_key(value.component_ids) == key:
			return value.deep_clone()
	return null

func recipes_containing(component_id: StringName) -> Array[ForgeRecipeRule]:
	var result: Array[ForgeRecipeRule] = []
	for value: ForgeRecipeRule in _recipes:
		if value.component_ids.has(component_id):
			result.append(value.deep_clone())
	return result

func deep_clone() -> ForgeRecipeTable:
	return ForgeRecipeTable.new(_manifest_digest, _recipes)

func _canonical_key(component_ids: Array[StringName]) -> String:
	var unique: Array[String] = []
	for value: StringName in component_ids:
		var text := String(value)
		if not unique.has(text):
			unique.append(text)
	unique.sort()
	return "|".join(unique)
