extends GutTest

const REQUIRED_SETTINGS: Array[StringName] = [
	&"locale",
	&"ui_scale_percent",
	&"color_vision_mode",
	&"reduced_motion",
	&"reduced_flash",
	&"reduced_particles",
	&"damage_number_density",
	&"master.volume",
	&"master.mute",
	&"music.volume",
	&"music.mute",
	&"sfx.volume",
	&"sfx.mute",
	&"ui.volume",
	&"ui.mute",
]


func test_settings_scene_exposes_focusable_typed_editor_controls() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"SETTINGS")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"SETTINGS",
				SettingsSnapshot.new(),
				null,
				&"en",
				{
					&"settings.apply": "Apply",
					&"settings.back": "Back",
				}
			)
		),
		&""
	)
	var found: Dictionary[StringName, Control] = {}
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if control != null and control.has_meta(&"setting_id"):
			found[StringName(control.get_meta(&"setting_id"))] = control
	for setting_id: StringName in REQUIRED_SETTINGS:
		assert_true(found.has(setting_id), "missing typed setting editor %s" % setting_id)
		if found.has(setting_id):
			assert_eq(found[setting_id].focus_mode, Control.FOCUS_ALL)
	assert_true(
		screen.has_method(&"settings_draft"),
		"editor must expose only a clone of its typed draft"
	)
	assert_true(
		screen.has_method(&"control_status_code"),
		"preflight/save/postcommit source code must remain player-visible"
	)


func test_keyboard_edit_changes_draft_without_mutating_staged_snapshot() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"SETTINGS")
	var original := SettingsSnapshot.new()
	original.locale = &"zh_TW"
	assert_eq(
		screen.bind(
			StagedScreenContext.new(&"SETTINGS", original, null, &"zh_TW")
		),
		&""
	)
	add_child_autofree(screen)
	var locale_control: Control
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if (
			control != null
			and control.has_meta(&"setting_id")
			and StringName(control.get_meta(&"setting_id")) == &"locale"
		):
			locale_control = control
			break
	assert_not_null(locale_control)
	if locale_control == null:
		return
	locale_control.grab_focus()
	var event := InputEventKey.new()
	event.keycode = KEY_RIGHT
	event.pressed = true
	locale_control.gui_input.emit(event)
	var draft: Variant = (
		screen.call(&"settings_draft")
		if screen.has_method(&"settings_draft")
		else null
	)
	assert_true(draft is SettingsSnapshot)
	if draft is SettingsSnapshot:
		assert_ne((draft as SettingsSnapshot).locale, original.locale)
	assert_eq(original.locale, &"zh_TW", "staged snapshot must remain clone-only")
