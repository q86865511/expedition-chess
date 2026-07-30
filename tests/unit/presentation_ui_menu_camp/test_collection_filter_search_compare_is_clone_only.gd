extends GutTest

const SNAPSHOT_PATH := "res://presentation/viewmodels/collection_browser_snapshot.gd"
const VIEW_MODEL_PATH := "res://presentation/viewmodels/collection_browser_view_model.gd"


func test_collection_filter_search_compare_is_clone_only() -> void:
	var snapshot_script := _load_script(SNAPSHOT_PATH)
	var view_model_script := _load_script(VIEW_MODEL_PATH)
	if snapshot_script == null or view_model_script == null:
		return
	var snapshot: Object = snapshot_script.new()
	snapshot.set("content_ids", [&"unit.alpha", &"unit.beta"])
	snapshot.set("recipe_ids", [&"recipe.alpha", &"recipe.beta"])
	snapshot.set("glossary_ids", [&"rule.armor", &"rule.speed"])
	var view_model: Object = view_model_script.new(snapshot)
	if not _require_methods(
		view_model,
		[
			&"filter_and_search", &"select", &"move_focus", &"selected_id",
			&"compare_selected_with", &"entries",
		]
	):
		return

	assert_eq(
		view_model.call("filter_and_search", &"content", "beta"),
		[&"unit.beta"]
	)
	assert_eq(view_model.call("filter_and_search", &"recipe", "alpha"), [&"recipe.alpha"])
	assert_eq(view_model.call("filter_and_search", &"glossary", "armor"), [&"rule.armor"])
	assert_eq(view_model.call("select", &"content", &"unit.alpha"), &"")
	assert_eq(view_model.call("move_focus", 1), &"unit.beta")
	assert_eq(view_model.call("selected_id"), &"unit.beta")
	var same_kind: Variant = view_model.call(
		"compare_selected_with", &"content", &"unit.alpha"
	)
	assert_true(same_kind.get("ok"), "content same-kind compare is supported")

	var before_selection: Variant = view_model.call("selected_id")
	var cross_kind: Variant = view_model.call(
		"compare_selected_with", &"recipe", &"recipe.alpha"
	)
	assert_false(cross_kind.get("ok"))
	assert_eq(cross_kind.get("error_code"), &"COLLECTION_COMPARE_KIND_MISMATCH")
	assert_eq(view_model.call("selected_id"), before_selection)
	assert_eq(view_model.call("select", &"glossary", &"rule.armor"), &"")
	var glossary: Variant = view_model.call(
		"compare_selected_with", &"glossary", &"rule.speed"
	)
	assert_false(glossary.get("ok"))
	assert_eq(glossary.get("error_code"), &"COLLECTION_COMPARE_UNSUPPORTED")
	assert_eq(view_model.call("selected_id"), &"rule.armor")

	var returned: Array = view_model.call("entries", &"content")
	returned.append(&"unit.injected")
	snapshot.get("content_ids").append(&"unit.alias")
	assert_eq(
		view_model.call("entries", &"content"),
		[&"unit.alpha", &"unit.beta"],
		"caller and returned collection mutations must not write through"
	)


func _load_script(path: String) -> GDScript:
	if not FileAccess.file_exists(path):
		assert_true(false, "%s must provide the T08 clone-only browser contract" % path)
		return null
	var script := load(path) as GDScript
	assert_not_null(script)
	return script


func _require_methods(target: Object, methods: Array[StringName]) -> bool:
	for method: StringName in methods:
		if not target.has_method(method):
			assert_true(false, "%s must implement %s" % [VIEW_MODEL_PATH, method])
			return false
	return true
