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
## 頂欄標題保留欄：內縮 8 ＋ 標題 300 ＋ 與 metrics 的間隔 32。
## camp/prepare 的頂欄 metrics 一律從這裡起排，基線與間距才會一致。
const TITLE_INSET: float = 8.0
const TITLE_WIDTH: float = 300.0
const TITLE_COLUMN_WIDTH: float = TITLE_INSET + TITLE_WIDTH + 32.0

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
## UI 縮放（REQ-UX-003）：頂欄/底部帶/狀態帶「高度」隨字級放大，
## 中央內容區吃剩餘高度（內部由 follow_focus 捲動吸收）；寬度維持 reference。
var _scale_factor: float = 1.0


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
	status_visible: bool,
	factor: float = 1.0
) -> Rect2:
	var top_height := ceilf(TOP_HEIGHT * factor)
	var scaled_bottom := ceilf(bottom_height * factor)
	var status_height := ceilf(STATUS_HEIGHT * factor)
	var content_top := SAFE_MARGIN + top_height + GUTTER
	var footer_top := REFERENCE_SIZE.y - SAFE_MARGIN - scaled_bottom
	var status_top := footer_top - STATUS_GUTTER - status_height
	var content_bottom := (
		status_top - STATUS_GUTTER
		if status_visible
		else footer_top - GUTTER
	)
	var content_height := content_bottom - content_top
	match region:
		REGION_TOP:
			return Rect2(SAFE_MARGIN, SAFE_MARGIN, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, top_height)
		REGION_LEFT:
			return Rect2(SAFE_MARGIN, content_top, SIDE_WIDTH, content_height)
		REGION_RIGHT:
			return Rect2(REFERENCE_SIZE.x - SAFE_MARGIN - SIDE_WIDTH, content_top, SIDE_WIDTH, content_height)
		REGION_CENTER:
			var center_x := SAFE_MARGIN + SIDE_WIDTH + GUTTER
			return Rect2(center_x, content_top, REFERENCE_SIZE.x - center_x - SAFE_MARGIN - SIDE_WIDTH - GUTTER, content_height)
		REGION_BOTTOM:
			return Rect2(SAFE_MARGIN, footer_top, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, scaled_bottom)
		REGION_STATUS:
			return Rect2(SAFE_MARGIN, status_top, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, status_height)
	return Rect2(Vector2.ZERO, REFERENCE_SIZE)


func current_region_rect(region: StringName) -> Rect2:
	return _region_rect_for_state_with_bottom(region)


## 底部帶的有效高度＝max(基準×factor、實測內容 min＋內距)。
## 內容（分組頁高度、node-choice 動作）在建構後才定案，靜態回填追不上
## 時序；每次取 rect 時實測，面板永不被內容撐出安全區。
func _effective_bottom_height() -> float:
	var height := ceilf(_bottom_height * _scale_factor)
	var content := _contents.get(REGION_BOTTOM) as Control
	if content != null:
		height = maxf(
			height,
			content.get_combined_minimum_size().y
			+ PANEL_CONTENT_MARGIN.y * 2.0
		)
	return height


## 頂/狀態帶照 factor 縮放；底部帶採 _effective_bottom_height 的實測值。
func _region_rect_for_state_with_bottom(region: StringName) -> Rect2:
	var top_height := ceilf(TOP_HEIGHT * _scale_factor)
	var status_height := ceilf(STATUS_HEIGHT * _scale_factor)
	var scaled_bottom := _effective_bottom_height()
	var content_top := SAFE_MARGIN + top_height + GUTTER
	var footer_top := REFERENCE_SIZE.y - SAFE_MARGIN - scaled_bottom
	var status_top := footer_top - STATUS_GUTTER - status_height
	var content_bottom := (
		status_top - STATUS_GUTTER
		if _status_visible
		else footer_top - GUTTER
	)
	var content_height := content_bottom - content_top
	match region:
		REGION_TOP:
			return Rect2(SAFE_MARGIN, SAFE_MARGIN, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, top_height)
		REGION_LEFT:
			return Rect2(SAFE_MARGIN, content_top, SIDE_WIDTH, content_height)
		REGION_RIGHT:
			return Rect2(REFERENCE_SIZE.x - SAFE_MARGIN - SIDE_WIDTH, content_top, SIDE_WIDTH, content_height)
		REGION_CENTER:
			var center_x := SAFE_MARGIN + SIDE_WIDTH + GUTTER
			return Rect2(center_x, content_top, REFERENCE_SIZE.x - center_x - SAFE_MARGIN - SIDE_WIDTH - GUTTER, content_height)
		REGION_BOTTOM:
			return Rect2(SAFE_MARGIN, footer_top, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, scaled_bottom)
		REGION_STATUS:
			return Rect2(SAFE_MARGIN, status_top, REFERENCE_SIZE.x - SAFE_MARGIN * 2.0, status_height)
	return Rect2(Vector2.ZERO, REFERENCE_SIZE)


func set_scale_factor(factor: float) -> void:
	_scale_factor = maxf(factor, 0.01)
	_relayout_regions()


## 外部觸發重排（例如分組切換改變底部帶內容 min 之後）。
func relayout() -> void:
	_relayout_regions()


func _relayout_regions() -> void:
	for region: StringName in _panels:
		var panel := _panels.get(region) as Control
		if panel == null:
			continue
		_place_panel(region, panel, current_region_rect(region))


## 底部帶錨定畫面底、向上生長：內容 min 晚到（主題切換後的延遲重算、
## 分組切換、node-choice）也絕不會把底緣推出安全區。其餘區域維持
## 顯式 rect（P6：先 minimum 再 size）。
func _place_panel(region: StringName, panel: Control, rect: Rect2) -> void:
	if region == REGION_BOTTOM:
		panel.anchor_left = 0.0
		panel.anchor_right = 1.0
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_left = SAFE_MARGIN
		panel.offset_right = -SAFE_MARGIN
		panel.offset_bottom = -SAFE_MARGIN
		panel.offset_top = -SAFE_MARGIN - rect.size.y
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		panel.custom_minimum_size = Vector2(0.0, 0.0)
		return
	panel.position = rect.position
	panel.custom_minimum_size = rect.size
	panel.size = rect.size


func set_status_visible(value: bool) -> void:
	_status_visible = value
	for region: StringName in [REGION_LEFT, REGION_CENTER, REGION_RIGHT]:
		var panel := _panels.get(region) as Control
		if panel == null:
			continue
		var rect := current_region_rect(region)
		# P6：先更新 minimum 再設 size——順序相反時縮小會被舊 minimum 夾住，
		# 面板不回縮、狀態帶壓在內容上。
		panel.position = rect.position
		panel.custom_minimum_size = rect.size
		panel.size = rect.size
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
	_place_panel(region, panel, rect)
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
