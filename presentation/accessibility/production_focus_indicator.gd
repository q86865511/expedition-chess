class_name ProductionFocusIndicator
extends Panel

const PADDING: float = 5.0

var _owner_screen: Control


func bind_owner(owner_screen: Control) -> void:
	_owner_screen = owner_screen


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1000
	visible = false
	theme_type_variation = &"ExpeditionFocus"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var viewport := get_viewport()
	if viewport != null and not viewport.gui_focus_changed.is_connected(
		_on_gui_focus_changed
	):
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)
	if viewport != null:
		_on_gui_focus_changed(viewport.gui_get_focus_owner())
	set_process(true)


func _process(_delta: float) -> void:
	var viewport := get_viewport()
	if viewport != null:
		_on_gui_focus_changed(viewport.gui_get_focus_owner())


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.gui_focus_changed.is_connected(
		_on_gui_focus_changed
	):
		viewport.gui_focus_changed.disconnect(_on_gui_focus_changed)


func _on_gui_focus_changed(control: Control) -> void:
	if (
		_owner_screen == null
		or control == null
		or control == self
		or not _owner_screen.is_ancestor_of(control)
		or not control.is_visible_in_tree()
	):
		visible = false
		return
	var owner_inverse := (
		_owner_screen.get_global_transform_with_canvas().affine_inverse()
	)
	var global_rect := control.get_global_rect()
	var local_origin := owner_inverse * global_rect.position
	var local_end := owner_inverse * global_rect.end
	position = local_origin - Vector2(PADDING, PADDING)
	size = local_end - local_origin + Vector2(PADDING, PADDING) * 2.0
	visible = true
