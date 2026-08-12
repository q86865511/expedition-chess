class_name SystemMenuOverlay
extends Control

signal closed
signal return_to_menu_requested
signal exit_requested
signal settings_applied(result: SettingsApplicationResult)

enum State {
	CLOSED,
	ROOT,
	SETTINGS_EMBEDDED,
	CONFIRM_MENU,
	CONFIRM_EXIT,
}

const STATE_NAMES: Dictionary = {
	State.CLOSED: &"CLOSED",
	State.ROOT: &"ROOT",
	State.SETTINGS_EMBEDDED: &"SETTINGS_EMBEDDED",
	State.CONFIRM_MENU: &"CONFIRM_MENU",
	State.CONFIRM_EXIT: &"CONFIRM_EXIT",
}

const ROOT_NODE: StringName = &"SystemMenuRoot"
const SETTINGS_NODE: StringName = &"EmbeddedSettings"
const CONFIRM_MENU_NODE: StringName = &"RunMenuConfirmation"
const CONFIRM_EXIT_NODE: StringName = &"ExitConfirmation"

var _state: State = State.CLOSED
var _localized_text: Dictionary[StringName, String] = {}
var _settings_snapshot: SettingsSnapshot
var _settings_port: SettingsApplicationPort
var _surface: Control
var _active_focus_controls: Array[Control] = []
var _background_controls: Dictionary = {}
var _background_focus_modes: Dictionary[int, int] = {}
var _previous_focus: Control
var _background_root: Control
var _background_root_focus_behavior: int = Control.FOCUS_BEHAVIOR_INHERITED


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	visible = false


func configure(
	localized_text: Dictionary,
	settings_snapshot: SettingsSnapshot = null,
	settings_port: SettingsApplicationPort = null
) -> void:
	_localized_text.clear()
	for key: Variant in localized_text.keys():
		_localized_text[StringName(key)] = String(localized_text[key])
	_settings_snapshot = (
		settings_snapshot.deep_clone()
		if settings_snapshot != null
		else null
	)
	_settings_port = settings_port
	if _state != State.CLOSED:
		_rebuild_state()


func relocalize(localized_text: Dictionary) -> void:
	for key: Variant in localized_text.keys():
		_localized_text[StringName(key)] = String(localized_text[key])
	if _surface == null:
		return
	for node: Node in _surface.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.has_meta(&"localization_key"):
			continue
		var key := StringName(control.get_meta(&"localization_key"))
		if control is Button:
			(control as Button).text = _text(key)
		elif control is Label:
			(control as Label).text = _text(key)
		control.set_meta(&"accessible_text", _text(key))
	var settings := settings_composition()
	if settings != null:
		settings.relocalize(_localized_text)


func open(
	background_controls: Array[Control] = [],
	background_root: Control = null
) -> bool:
	if _state != State.CLOSED:
		return false
	_previous_focus = get_viewport().gui_get_focus_owner()
	_capture_background_focus(background_controls, background_root)
	visible = true
	_set_state(State.ROOT)
	return true


func close() -> bool:
	if _state == State.CLOSED:
		return false
	_clear_surface()
	_state = State.CLOSED
	visible = false
	_restore_background_focus()
	closed.emit()
	return true


func handle_system_menu_action() -> bool:
	match _state:
		State.CLOSED:
			return false
		State.ROOT:
			return close()
		State.SETTINGS_EMBEDDED, State.CONFIRM_MENU, State.CONFIRM_EXIT:
			_set_state(State.ROOT)
			return true
	return false


func state() -> State:
	return _state


func state_name() -> StringName:
	return StringName(STATE_NAMES.get(_state, &"CLOSED"))


func is_open() -> bool:
	return _state != State.CLOSED


func is_confirmation_open() -> bool:
	return _state in [State.CONFIRM_MENU, State.CONFIRM_EXIT]


func confirmation_node_name() -> String:
	match _state:
		State.CONFIRM_MENU:
			return String(CONFIRM_MENU_NODE)
		State.CONFIRM_EXIT:
			return String(CONFIRM_EXIT_NODE)
	return ""


func active_focus_controls() -> Array[Control]:
	var result: Array[Control] = []
	for control: Control in _active_focus_controls:
		if is_instance_valid(control):
			result.append(control)
	return result


func settings_composition() -> SettingsScreenComposition:
	if _surface == null:
		return null
	for candidate: Node in _surface.find_children(
		"*", "SettingsScreenComposition", true, false
	):
		if candidate is SettingsScreenComposition:
			return candidate as SettingsScreenComposition
	return null


func _set_state(next: State) -> void:
	_state = next
	_rebuild_state()


func _rebuild_state() -> void:
	_clear_surface()
	match _state:
		State.ROOT:
			_build_root()
		State.SETTINGS_EMBEDDED:
			_build_settings()
		State.CONFIRM_MENU:
			_build_confirmation(
				CONFIRM_MENU_NODE,
				&"run.menu.status",
				&"run.menu.confirm",
				&"run.menu.cancel",
				_on_return_to_menu_confirmed
			)
		State.CONFIRM_EXIT:
			_build_confirmation(
				CONFIRM_EXIT_NODE,
				&"menu.exit.status",
				&"menu.exit.confirm",
				&"menu.exit.cancel",
				_on_exit_confirmed
			)


func _build_root() -> void:
	var content := _new_panel(ROOT_NODE, Vector2(660.0, 570.0), false)
	_add_label(content, &"screen.run_container.title", "Title")
	_add_button(
		content,
		&"menu.continue",
		&"menu.continue",
		_on_continue_pressed
	)
	_add_button(
		content,
		&"system_menu.settings",
		&"menu.settings",
		_on_settings_pressed
	)
	_add_button(content, &"run.menu", &"run.menu", _on_menu_pressed)
	_add_button(content, &"menu.exit", &"menu.exit", _on_exit_pressed)
	_finish_focus_graph()


func _build_settings() -> void:
	var content := _new_panel(SETTINGS_NODE, Vector2(1320.0, 900.0), false)
	_add_label(content, &"menu.settings", "Title")
	var composition := SettingsScreenComposition.new()
	composition.name = "SettingsScreenComposition"
	composition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composition.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(composition)
	var initial := (
		_settings_snapshot.deep_clone()
		if _settings_snapshot != null
		else SettingsSnapshot.new()
	)
	composition.compose_embedded(initial, _localized_text)
	for editor: Control in composition.focus_controls():
		_active_focus_controls.append(editor)
	var actions := HBoxContainer.new()
	actions.name = "EmbeddedSettingsActions"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(actions)
	var apply := _add_button(
		actions,
		&"settings.apply",
		&"settings.apply",
		_on_settings_apply_pressed
	)
	apply.disabled = _settings_port == null
	_add_button(
		actions,
		&"system_menu.back",
		&"settings.back",
		_on_back_pressed
	)
	_finish_focus_graph()


func _build_confirmation(
	node_name: StringName,
	status_key: StringName,
	confirm_action: StringName,
	cancel_action: StringName,
	confirm_callback: Callable
) -> void:
	var content := _new_panel(node_name, Vector2(840.0, 330.0), true)
	var status := _add_label(content, status_key, "Status")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_add_button(content, confirm_action, confirm_action, confirm_callback)
	_add_button(content, cancel_action, cancel_action, _on_back_pressed)
	_finish_focus_graph()


func _new_panel(
	node_name: StringName,
	minimum: Vector2,
	is_confirmation: bool
) -> VBoxContainer:
	_surface = Control.new()
	_surface.name = "Surface"
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_surface)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_surface.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = String(node_name)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	ExpeditionLayoutMetrics.set_fixed_min(panel, minimum.x, minimum.y)
	panel.theme_type_variation = &"ExpeditionModalPanel"
	panel.z_index = 21 if is_confirmation else 10
	_surface.add_child(panel)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return content


func _add_label(
	parent: Control,
	text_key: StringName,
	node_name: String
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = _text(text_key)
	label.set_meta(&"localization_key", text_key)
	label.set_meta(&"accessible_text", label.text)
	parent.add_child(label)
	return label


func _add_button(
	parent: Control,
	action_id: StringName,
	text_key: StringName,
	callback: Callable
) -> Button:
	var button := Button.new()
	button.name = "%sButton" % String(action_id).replace(".", "_").to_pascal_case()
	button.text = _text(text_key)
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta(&"action_id", action_id)
	button.set_meta(&"localization_key", text_key)
	button.set_meta(&"accessible_text", button.text)
	button.set_meta(&"system_menu_owned", true)
	button.pressed.connect(callback)
	parent.add_child(button)
	_active_focus_controls.append(button)
	return button


func _finish_focus_graph() -> void:
	var focusable: Array[Control] = []
	for control: Control in _active_focus_controls:
		if (
			control != null
			and control.is_visible_in_tree()
			and control.focus_mode != Control.FOCUS_NONE
			and (not control is BaseButton or not (control as BaseButton).disabled)
		):
			focusable.append(control)
	_active_focus_controls = focusable
	if _active_focus_controls.is_empty():
		return
	for index: int in _active_focus_controls.size():
		var current := _active_focus_controls[index]
		var previous := _active_focus_controls[
			posmod(index - 1, _active_focus_controls.size())
		]
		var next := _active_focus_controls[
			posmod(index + 1, _active_focus_controls.size())
		]
		current.focus_previous = current.get_path_to(previous)
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)
		current.focus_neighbor_bottom = current.get_path_to(next)
	call_deferred(&"_grab_first_focus")


func _grab_first_focus() -> void:
	if (
		not _active_focus_controls.is_empty()
		and is_instance_valid(_active_focus_controls[0])
		and _active_focus_controls[0].is_inside_tree()
	):
		_active_focus_controls[0].grab_focus()


func _capture_background_focus(
	controls: Array[Control],
	background_root: Control
) -> void:
	_background_controls.clear()
	_background_focus_modes.clear()
	_background_root = (
		background_root
		if background_root != null
		and is_instance_valid(background_root)
		and background_root != self
		and background_root.is_ancestor_of(self)
		else null
	)
	if _background_root != null:
		_background_root_focus_behavior = (
			_background_root.focus_behavior_recursive
		)
		_background_root.focus_behavior_recursive = (
			Control.FOCUS_BEHAVIOR_DISABLED
		)
		for node: Node in _background_root.find_children(
			"*", "Control", true, false
		):
			_suppress_background_control(node as Control)
		var tree := get_tree()
		if tree != null and not tree.node_added.is_connected(
			_on_tree_node_added
		):
			tree.node_added.connect(_on_tree_node_added)
	for control: Control in controls:
		_suppress_background_control(control)


func _on_tree_node_added(node: Node) -> void:
	_suppress_background_control(node as Control)


func _suppress_background_control(control: Control) -> void:
	if (
		control == null
		or not is_instance_valid(control)
		or control == self
		or is_ancestor_of(control)
		or (
			_background_root != null
			and control != _background_root
			and not _background_root.is_ancestor_of(control)
		)
		or control.focus_mode == Control.FOCUS_NONE
	):
		return
	var identity := control.get_instance_id()
	if not _background_controls.has(identity):
		_background_controls[identity] = control
		_background_focus_modes[identity] = control.focus_mode
	control.focus_mode = Control.FOCUS_NONE


func _restore_background_focus() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)
	for identity: int in _background_controls:
		var control := _background_controls[identity] as Control
		if control == null or not is_instance_valid(control):
			continue
		control.focus_mode = int(
			_background_focus_modes.get(identity, Control.FOCUS_NONE)
		)
	_background_controls.clear()
	_background_focus_modes.clear()
	if _background_root != null and is_instance_valid(_background_root):
		_background_root.focus_behavior_recursive = (
			_background_root_focus_behavior
		)
	_background_root = null
	_background_root_focus_behavior = Control.FOCUS_BEHAVIOR_INHERITED
	if (
		_previous_focus != null
		and is_instance_valid(_previous_focus)
		and _previous_focus.is_inside_tree()
		and _previous_focus.focus_mode != Control.FOCUS_NONE
	):
		_previous_focus.call_deferred(&"grab_focus")
	_previous_focus = null


func _clear_surface() -> void:
	_active_focus_controls.clear()
	if _surface == null or not is_instance_valid(_surface):
		_surface = null
		return
	if _surface.get_parent() != null:
		_surface.get_parent().remove_child(_surface)
	_surface.queue_free()
	_surface = null


func _on_continue_pressed() -> void:
	close()


func _on_settings_pressed() -> void:
	_set_state(State.SETTINGS_EMBEDDED)


func _on_menu_pressed() -> void:
	_set_state(State.CONFIRM_MENU)


func _on_exit_pressed() -> void:
	_set_state(State.CONFIRM_EXIT)


func _on_back_pressed() -> void:
	_set_state(State.ROOT)


func _on_settings_apply_pressed() -> void:
	var composition := settings_composition()
	if composition == null:
		return
	var result := composition.submit_through(_settings_port)
	if result != null and result.snapshot != null:
		_settings_snapshot = result.snapshot.deep_clone()
	settings_applied.emit(result)


func _on_return_to_menu_confirmed() -> void:
	return_to_menu_requested.emit()


func _on_exit_confirmed() -> void:
	exit_requested.emit()


func _text(key: StringName) -> String:
	return _localized_text.get(key, String(key))
