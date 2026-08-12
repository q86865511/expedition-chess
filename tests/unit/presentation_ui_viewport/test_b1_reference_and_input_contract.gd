extends GutTest

const AUTOLOADS := {
	"ContentRegistry": "*res://content/registry/content_registry_service.gd",
	"SaveService": "*res://services/save/save_repository.gd",
	"SettingsService": "*res://services/settings/settings_repository.gd",
	"AudioService": "*res://services/audio/audio_coordinator.gd",
	"SceneRouter": "*res://services/scene/scene_router_service.gd",
}


func test_project_and_runtime_share_the_1920_reference() -> void:
	assert_eq(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		1920
	)
	assert_eq(
		ProjectSettings.get_setting("display/window/size/viewport_height"),
		1080
	)
	assert_eq(UiScaleRoot.REFERENCE_SIZE, Vector2i(1920, 1080))
	assert_eq(WorldViewportPolicy.UI_REFERENCE_SIZE, Vector2i(1920, 1080))
	assert_eq(WindowCoordinateMapper.UI_REFERENCE_SIZE, Vector2i(1920, 1080))
	assert_eq(WorldViewportPolicy.WORLD_SIZE, Vector2i(640, 360))
	assert_eq(ProductionLayoutShell.REFERENCE_SIZE, Vector2(1920, 1080))


func test_ui_policy_fits_all_supported_16_by_9_windows() -> void:
	var policy := UiScaleRoot.new()
	for window_size: Vector2i in [
		Vector2i(1280, 720),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
	]:
		for ui_scale: int in UiScaleRoot.SUPPORTED_UI_SCALES:
			var layout := policy.configure(window_size, ui_scale)
			assert_true(bool(layout.get("ok", false)))
			assert_eq(layout.get("reference_size"), Vector2i(1920, 1080))
			assert_eq(
				layout.get("screen_rect"),
				Rect2(Vector2.ZERO, Vector2(window_size))
			)


func test_dedicated_input_actions_use_escape_and_w() -> void:
	_assert_key_action(&"system_menu", KEY_ESCAPE)
	_assert_key_action(&"prepare_quick_toggle_unit", KEY_W)


func test_five_autoload_entries_remain_exactly_unchanged() -> void:
	var observed := {}
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name := String(property.get("name", ""))
		if property_name.begins_with("autoload/"):
			observed[property_name.trim_prefix("autoload/")] = (
				ProjectSettings.get_setting(property_name)
			)
	assert_eq(observed, AUTOLOADS)


func _assert_key_action(action: StringName, expected_key: Key) -> void:
	assert_true(InputMap.has_action(action), "%s must be registered" % action)
	var matched := false
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null and (
			key.physical_keycode == expected_key
			or key.keycode == expected_key
		):
			matched = true
	assert_true(matched, "%s must use %s" % [action, expected_key])
