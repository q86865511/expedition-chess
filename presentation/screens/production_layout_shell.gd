class_name ProductionLayoutShell
extends Control

const REFERENCE_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const SAFE_MARGIN: float = 36.0
const GUTTER: float = 24.0
const TOP_HEIGHT: float = 126.0
const BOTTOM_HEIGHT: float = 204.0
const PREPARE_BOTTOM_HEIGHT: float = 210.0
const SIDE_WIDTH: float = 420.0
const PANEL_CONTENT_MARGIN: Vector2 = Vector2(24.0, 18.0)
const STATUS_HEIGHT: float = 66.0
const STATUS_GUTTER: float = 12.0
## BoardProjection's exact 8x8 AABB ends at reference y=804 for every
## supported 16:9 output. Board routes therefore keep the bottom band at or
## below that edge; enlarged controls reflow through the bottom scroll host
## instead of covering the player's half of the world board.
const BOARD_ROUTE_BOTTOM_HEIGHT_CAP: float = 240.0
const ACTION_BAR_VARIATION: StringName = &"ExpeditionActionBar"
const ACTION_BAR_COMPACT_VARIATION: StringName = &"ExpeditionActionBarCompact"
## 頂欄標題保留欄：內縮 12 ＋ 標題 450 ＋ 與 metrics 的間隔 48。
## camp/prepare 的頂欄 metrics 一律從這裡起排，基線與間距才會一致。
const TITLE_INSET: float = 12.0
const TITLE_WIDTH: float = 450.0
const TITLE_COLUMN_WIDTH: float = TITLE_INSET + TITLE_WIDTH + 48.0

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
var _bottom_height_cap: float = INF
var _bottom_scroll_enabled: bool = false
var _status_visible: bool = false
## UI 縮放（REQ-UX-003）：頂欄/底部帶/狀態帶「高度」隨字級放大，
## 中央內容區吃剩餘高度（內部由 follow_focus 捲動吸收）；寬度維持 reference。
var _scale_factor: float = 1.0


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.gui_focus_changed.is_connected(
		_on_gui_focus_changed
	):
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.gui_focus_changed.is_connected(
		_on_gui_focus_changed
	):
		viewport.gui_focus_changed.disconnect(_on_gui_focus_changed)


func build(route_kind: StringName = &"") -> void:
	_bottom_scroll_enabled = route_kind in [&"RUN_PREPARE", &"RUN_COMBAT"]
	_bottom_height_cap = (
		BOARD_ROUTE_BOTTOM_HEIGHT_CAP
		if _bottom_scroll_enabled
		else INF
	)
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
	if route_kind in [&"RUN_PREPARE", &"RUN_COMBAT"]:
		# The world SubViewport is the authoritative board surface for in-run
		# board routes; full-screen UI background must not cover it.
		background.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(background)
	_add_panel(REGION_TOP, "TopRegion", current_region_rect(REGION_TOP), &"ExpeditionTopBar", HBoxContainer.new())
	var left_variation := &"ExpeditionPrimaryPanel" if route_kind == &"CAMP_WORLD" else &"ExpeditionSecondaryPanel"
	var center_variation := &"ExpeditionBoardPanel" if route_kind == &"RUN_PREPARE" else &"ExpeditionSecondaryPanel"
	_add_panel(REGION_LEFT, "LeftRegion", current_region_rect(REGION_LEFT), left_variation, VBoxContainer.new())
	_add_panel(REGION_CENTER, "CenterRegion", current_region_rect(REGION_CENTER), center_variation, VBoxContainer.new())
	if route_kind in [&"RUN_PREPARE", &"RUN_COMBAT"]:
		var center_panel := _panels.get(REGION_CENTER) as PanelContainer
		if center_panel != null:
			# World SubViewport owns the board pixels; the shell keeps only a faint
			# framing surface so projected tiles/sprites remain visible underneath.
			center_panel.self_modulate = Color(1.0, 1.0, 1.0, 0.18)
	_add_panel(REGION_RIGHT, "RightRegion", current_region_rect(REGION_RIGHT), &"ExpeditionSecondaryPanel", VBoxContainer.new())
	_add_panel(REGION_BOTTOM, "BottomRegion", current_region_rect(REGION_BOTTOM), ACTION_BAR_VARIATION, HBoxContainer.new())
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
	var effective_cap := _bottom_height_cap
	if _bottom_scroll_enabled and _status_visible:
		# Status is stacked immediately above the bottom band. Shrink only the
		# scrollable band by the exact status+gap footprint so the whole stack
		# starts at (or below) the projected board's reference y=804 edge.
		effective_cap -= (
			STATUS_GUTTER
			+ ceilf(STATUS_HEIGHT * _scale_factor)
		)
	return minf(height, maxf(0.0, effective_cap))


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
		ExpeditionLayoutMetrics.set_reference_min(panel, Vector2.ZERO)
		return
	panel.position = rect.position
	ExpeditionLayoutMetrics.set_reference_min(panel, rect.size)
	panel.size = rect.size


func set_status_visible(value: bool) -> void:
	_status_visible = value
	var bottom_panel := _panels.get(REGION_BOTTOM) as PanelContainer
	if bottom_panel != null:
		bottom_panel.theme_type_variation = (
			ACTION_BAR_COMPACT_VARIATION
			if _bottom_scroll_enabled and value
			else ACTION_BAR_VARIATION
		)
	# Status visibility changes the board-route bottom cap. Relayout every
	# region in one pass so BottomRegion and StatusRegion move together instead
	# of retaining the geometry calculated for the previous visibility state.
	_relayout_regions()
	var status_panel := _panels.get(REGION_STATUS) as Control
	if status_panel != null:
		status_panel.visible = value


func is_status_visible() -> bool:
	return _status_visible


## ScrollContainer's built-in follow_focus guarantees reachability, but an
## oversized focused descendant may remain edge-aligned. Center it vertically
## on the focus-change event so its full shorter dimension and text center stay
## visible even while the status band temporarily shortens the board footer.
func _on_gui_focus_changed(control: Control) -> void:
	if not _bottom_scroll_enabled or control == null:
		return
	var scroll := find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	if scroll == null or not scroll.is_ancestor_of(control):
		return
	call_deferred(&"_center_oversize_bottom_focus", scroll, control)


func _center_oversize_bottom_focus(
	scroll: ScrollContainer,
	control: Control
) -> void:
	if (
		scroll == null
		or control == null
		or not is_instance_valid(scroll)
		or not is_instance_valid(control)
		or not scroll.is_inside_tree()
		or not control.is_inside_tree()
		or not control.has_focus()
	):
		return
	var viewport_rect := scroll.get_global_rect()
	var control_rect := control.get_global_rect()
	if control_rect.size.y <= viewport_rect.size.y + 1.0:
		return
	var center_delta := control_rect.get_center().y - viewport_rect.get_center().y
	scroll.scroll_vertical += roundi(center_delta)


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
	if region == REGION_BOTTOM and _bottom_scroll_enabled:
		var scroll := ScrollContainer.new()
		scroll.name = "BottomContentScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.follow_focus = true
		scroll.clip_contents = true
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(scroll)
		scroll.add_child(content_control)
	else:
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
