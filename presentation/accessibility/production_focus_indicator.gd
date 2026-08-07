class_name ProductionFocusIndicator
extends Panel

const PADDING: float = 5.0
const BORDER_WIDTH: int = 4
const BORDER_COLOR: Color = Color(1.0, 0.9, 0.2, 1.0)

var _owner_screen: Control


func bind_owner(owner_screen: Control) -> void:
	_owner_screen = owner_screen


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1000
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = BORDER_COLOR
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(3)
	add_theme_stylebox_override(&"panel", style)
	var viewport := get_viewport()
	if viewport != null and not viewport.gui_focus_changed.is_connected(
		_on_gui_focus_changed
	):
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)
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
