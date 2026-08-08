class_name ProductionLayoutShell
extends Control

const REFERENCE_SIZE: Vector2 = Vector2(1280.0, 720.0)
const SAFE_MARGIN: float = 24.0
const GUTTER: float = 16.0
const TOP_HEIGHT: float = 84.0
const BOTTOM_HEIGHT: float = 136.0
const PREPARE_BOTTOM_HEIGHT: float = 140.0
const SIDE_WIDTH: float = 280.0
const PANEL_CONTENT_MARGIN: Vector2 = Vector2(16.0, 12.0)
const STATUS_HEIGHT: float = 44.0
const STATUS_GUTTER: float = 8.0

const REGION_TOP: StringName = &"top"
const REGION_LEFT: StringName = &"left"
const REGION_CENTER: StringName = &"center"
const REGION_RIGHT: StringName = &"right"
const REGION_BOTTOM: StringName = &"bottom"
const REGION_OVERLAY: StringName = &"overlay"
const REGION_STATUS: StringName = &"status"

var _contents: Dictionary = {}
var _panels: Dictionary = {}
var _bottom_height: float = BOTTOM_HEIGHT
var _status_visible: bool = false


func build(route_kind: StringName = &"") -> void:
	_bottom_height = (
		PREPARE_BOTTOM_HEIGHT
		if route_kind == &"RUN_PREPARE"
		else BOTTOM_HEIGHT
	)
	_status_visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := Panel.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.theme_type_variation = &"ExpeditionBackground"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_add_panel(REGION_TOP, "TopRegion", current_region_rect(REGION_TOP), &"ExpeditionTopBar", HBoxContainer.new())
	var left_variation := &"ExpeditionPrimaryPanel" if route_kind == &"CAMP_WORLD" else &"ExpeditionSecondaryPanel"
	var center_variation := &"ExpeditionBoardPanel" if route_kind == &"RUN_PREPARE" else &"ExpeditionSecondaryPanel"
	_add_panel(REGION_LEFT, "LeftRegion", current_region_rect(REGION_LEFT), left_variation, VBoxContainer.new())
	_add_panel(REGION_CENTER, "CenterRegion", current_region_rect(REGION_CENTER), center_variation, VBoxContainer.new())
	_add_panel(REGION_RIGHT, "RightRegion", current_region_rect(REGION_RIGHT), &"ExpeditionSecondaryPanel", VBoxContainer.new())
	_add_panel(REGION_BOTTOM, "BottomRegion", current_region_rect(REGION_BOTTOM), &"ExpeditionActionBar", HBoxContainer.new())
	_add_panel(REGION_STATUS, "StatusRegion", current_region_rect(REGION_STATUS), &"ExpeditionStatusPanel", HBoxContainer.new())
	set_status_visible(false)
	_add_control_region(REGION_OVERLAY, "OverlayRegion", Rect2(Vector2.ZERO, REFERENCE_SIZE))


func content(region: StringName) -> Control:
	return _contents.get(region) as Control


static func region_rect(region: StringName) -> Rect2:
	return region_rect_for(region, BOTTOM_HEIGHT)


static func region_rect_for(region: StringName, bottom_height: float) -> Rect2:
	return _region_rect_for_state(region, bottom_height, true)


static func _region_rect_for_state(
	region: StringName,
	bottom_height: float,
	status_visible: bool
) -> Rect2:
	var content_top := SAFE_MARGIN + TOP_HEIGHT + GUTTER
	var footer_top := REFERENCE_SIZE.y - SAFE_MARGIN - bottom_height
	var status_top := footer_top - STATUS_GUTTER - STATUS_HEIGHT
	var content_bottom := (
		status_top - STATUS_GUTTER
		if status_visible
		else footer_top - GUTTER
	)
	var content_height := content_bottom - content_top
	match region:
		REGION_TOP:
			return Rect2(SAFE_MARGIN, SAFE_MARGIN, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, TOP_HEIGHT)
		REGION_LEFT:
			return Rect2(SAFE_MARGIN, content_top, SIDE_WIDTH, content_height)
		REGION_RIGHT:
			return Rect2(REFERENCE_SIZE.x - SAFE_MARGIN - SIDE_WIDTH, content_top, SIDE_WIDTH, content_height)
		REGION_CENTER:
			var center_x := SAFE_MARGIN + SIDE_WIDTH + GUTTER
			return Rect2(center_x, content_top, REFERENCE_SIZE.x - center_x - SAFE_MARGIN - SIDE_WIDTH - GUTTER, content_height)
		REGION_BOTTOM:
			return Rect2(SAFE_MARGIN, REFERENCE_SIZE.y - SAFE_MARGIN - bottom_height, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, bottom_height)
		REGION_STATUS:
			return Rect2(SAFE_MARGIN, status_top, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, STATUS_HEIGHT)
	return Rect2(Vector2.ZERO, REFERENCE_SIZE)


func current_region_rect(region: StringName) -> Rect2:
	return _region_rect_for_state(region, _bottom_height, _status_visible)


func set_status_visible(value: bool) -> void:
	_status_visible = value
	for region: StringName in [REGION_LEFT, REGION_CENTER, REGION_RIGHT]:
		var panel := _panels.get(region) as Control
		if panel == null:
			continue
		var rect := current_region_rect(region)
		panel.position = rect.position
		panel.size = rect.size
		panel.custom_minimum_size = rect.size
	var status_panel := _panels.get(REGION_STATUS) as Control
	if status_panel != null:
		status_panel.visible = value


func is_status_visible() -> bool:
	return _status_visible


func current_content_rect(region: StringName) -> Rect2:
	var rect := current_region_rect(region)
	if region in [REGION_TOP, REGION_LEFT, REGION_CENTER, REGION_RIGHT, REGION_BOTTOM, REGION_STATUS]:
		return Rect2(
			rect.position + PANEL_CONTENT_MARGIN,
			rect.size - PANEL_CONTENT_MARGIN * 2.0
		)
	return rect


func _add_panel(
	region: StringName,
	node_name: String,
	rect: Rect2,
	variation: StringName,
	content_control: Control
) -> void:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.custom_minimum_size = rect.size
	panel.theme_type_variation = variation
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_control.name = "Content"
	content_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(content_control)
	add_child(panel)
	_contents[region] = content_control
	_panels[region] = panel


func _add_control_region(
	region: StringName,
	node_name: String,
	rect: Rect2
) -> void:
	var control := Control.new()
	control.name = node_name
	control.position = rect.position
	control.size = rect.size
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)
	_contents[region] = control
