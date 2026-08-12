class_name ProductionViewportCoordinator
extends Node

const INVALID_TREE: StringName = &"PRODUCTION_VIEWPORT_TREE_INVALID"
const INVALID_WORLD_SURFACE: StringName = &"PRODUCTION_VIEWPORT_WORLD_SURFACE_INVALID"
const COORDINATOR_GROUP: StringName = &"production_viewport_coordinator"

@export var world_container_path: NodePath = ^"../WorldViewportContainer"
@export var world_viewport_path: NodePath = ^"../WorldViewportContainer/WorldViewport"
@export var ui_layer_path: NodePath = ^"../UiLayer"
@export var ui_root_path: NodePath = ^"../UiLayer/UiRoot"
@export var presentation_host_path: NodePath = ^"../UiLayer/UiRoot/PresentationHost"

var _world_policy := WorldViewportPolicy.new()
var _ui_policy := UiScaleRoot.new()
var _mapper := WindowCoordinateMapper.new()
var _ui_scale_percent: int = 100
var _last_window_size := Vector2i.ZERO


func _ready() -> void:
	add_to_group(COORDINATOR_GROUP)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(
		_on_viewport_size_changed
	):
		viewport.size_changed.connect(_on_viewport_size_changed)
	call_deferred(&"_on_viewport_size_changed")


func apply_ui_scale(scale_percent: int) -> StringName:
	if scale_percent not in UiScaleRoot.SUPPORTED_UI_SCALES:
		return UiScaleRoot.UNSUPPORTED_SCALE
	_ui_scale_percent = scale_percent
	return synchronize(_visible_window_size())


func synchronize(window_size: Vector2i) -> StringName:
	var world_container := get_node_or_null(
		world_container_path
	) as SubViewportContainer
	var world_viewport := get_node_or_null(
		world_viewport_path
	) as SubViewport
	var ui_layer := get_node_or_null(ui_layer_path) as CanvasLayer
	var ui_root := get_node_or_null(ui_root_path) as Control
	var presentation_host := get_node_or_null(
		presentation_host_path
	) as Control
	if (
		world_container == null
		or world_viewport == null
		or ui_layer == null
		or ui_root == null
		or presentation_host == null
	):
		return INVALID_TREE
	var world_layout := _world_policy.layout_for_window(window_size)
	var ui_layout := _ui_policy.configure(window_size, _ui_scale_percent)
	if (
		not bool(world_layout.get("ok", false))
		or not bool(ui_layout.get("ok", false))
	):
		return StringName(
			world_layout.get(
				"error",
				ui_layout.get("error", INVALID_TREE)
			)
		)
	var mapper_error := _mapper.configure(
		world_layout,
		_ui_scale_percent
	)
	if not mapper_error.is_empty():
		return mapper_error
	var world_rect: Rect2 = world_layout["world_rect"]
	world_viewport.canvas_item_default_texture_filter = (
		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	)
	world_container.position = world_rect.position
	world_container.size = world_rect.size
	world_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# stretch + stretch_shrink 讓 SubViewport 恆為 world_rect/scale = 640×360
	# （§10.1）；先前先關再開 stretch 的寫法會被 stretch=true 的
	# recalc 覆寫回容器尺寸，authored 解析度從未生效。
	world_container.stretch = true
	world_container.stretch_shrink = maxi(
		1, int(world_layout["integer_scale"])
	)

	var screen_rect: Rect2 = ui_layout["screen_rect"]
	var reference := Vector2(UiScaleRoot.REFERENCE_SIZE)
	var fit_scale := screen_rect.size.x / reference.x
	ui_root.position = Vector2.ZERO
	ui_root.size = reference
	ui_layer.transform = Transform2D(
		0.0,
		Vector2(fit_scale, fit_scale),
		0.0,
		screen_rect.position
	)
	presentation_host.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_last_window_size = window_size
	set_meta(&"window_size", window_size)
	set_meta(&"world_rect", world_rect)
	set_meta(&"ui_screen_rect", screen_rect)
	set_meta(&"ui_scale_percent", _ui_scale_percent)
	return _push_coordinate_mapper_to_world_surfaces()


func window_size() -> Vector2i:
	return _last_window_size


func pointer_to_world(window_point: Vector2) -> Vector2:
	return _mapper.screen_to_world(window_point)


func pointer_to_ui(window_point: Vector2) -> Vector2:
	return _mapper.screen_to_ui(window_point)


func coordinate_mapper_clone() -> WindowCoordinateMapper:
	if not coordinate_mapper_ready():
		return null
	return _mapper.deep_clone()


func coordinate_mapper_ready() -> bool:
	return coordinate_mapper_error().is_empty()


func coordinate_mapper_error() -> StringName:
	return _mapper.configuration_error()


func _push_coordinate_mapper_to_world_surfaces() -> StringName:
	var tree := get_tree()
	if tree == null:
		return INVALID_TREE
	var first_error: StringName = &""
	for candidate: Node in tree.get_nodes_in_group(
		ProductionWorldSurface.MOUNT_GROUP
	):
		if not candidate is ProductionWorldSurface:
			if first_error.is_empty():
				first_error = INVALID_WORLD_SURFACE
			continue
		var surface := candidate as ProductionWorldSurface
		var refresh_error := surface.refresh_coordinate_mapper(
			_mapper.deep_clone()
		)
		if first_error.is_empty() and not refresh_error.is_empty():
			first_error = refresh_error
	return first_error


func _visible_window_size() -> Vector2i:
	var viewport := get_viewport()
	return (
		Vector2i(viewport.get_visible_rect().size)
		if viewport != null
		else Vector2i.ZERO
	)


func _on_viewport_size_changed() -> void:
	synchronize(_visible_window_size())
