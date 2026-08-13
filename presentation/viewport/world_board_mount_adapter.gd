class_name WorldBoardMountAdapter
extends RefCounted

const COORDINATOR_MISSING: StringName = &"WORLD_BOARD_COORDINATOR_MISSING"
const COORDINATOR_AMBIGUOUS: StringName = &"WORLD_BOARD_COORDINATOR_AMBIGUOUS"
const SURFACE_MISSING: StringName = &"WORLD_BOARD_SURFACE_MISSING"
const SURFACE_AMBIGUOUS: StringName = &"WORLD_BOARD_SURFACE_AMBIGUOUS"


static func mount(
	tree: SceneTree,
	snapshot: WorldBoardSnapshot,
	cell_validator: Callable = Callable(),
	overlay_mount: Control = null
) -> StringName:
	if tree == null:
		return COORDINATOR_MISSING
	var surfaces := _world_surfaces(tree)
	if surfaces.is_empty():
		return SURFACE_MISSING
	if surfaces.size() != 1:
		return SURFACE_AMBIGUOUS
	var mapper_result := _mapper_clone_result(tree)
	var mapper_error := StringName(mapper_result.get("error", &""))
	if not mapper_error.is_empty():
		return mapper_error
	var mapper := mapper_result.get("mapper") as WindowCoordinateMapper
	if mapper == null:
		return WindowCoordinateMapper.NOT_CONFIGURED
	return surfaces[0].mount_board_snapshot(
		snapshot.deep_clone() if snapshot != null else null,
		mapper,
		overlay_mount,
		cell_validator
	)


static func clear(tree: SceneTree) -> StringName:
	if tree == null:
		return SURFACE_MISSING
	var surfaces := _world_surfaces(tree)
	if surfaces.is_empty():
		return SURFACE_MISSING
	if surfaces.size() != 1:
		return SURFACE_AMBIGUOUS
	surfaces[0].clear_board_snapshot()
	return &""


static func refresh_overlay(tree: SceneTree) -> StringName:
	if tree == null:
		return COORDINATOR_MISSING
	var surfaces := _world_surfaces(tree)
	if surfaces.is_empty():
		return SURFACE_MISSING
	if surfaces.size() != 1:
		return SURFACE_AMBIGUOUS
	var mapper_result := _mapper_clone_result(tree)
	var mapper_error := StringName(mapper_result.get("error", &""))
	if not mapper_error.is_empty():
		return mapper_error
	var mapper := mapper_result.get("mapper") as WindowCoordinateMapper
	if mapper == null:
		return WindowCoordinateMapper.NOT_CONFIGURED
	return surfaces[0].refresh_coordinate_mapper(mapper)


static func _world_surfaces(tree: SceneTree) -> Array[ProductionWorldSurface]:
	var surfaces: Array[ProductionWorldSurface] = []
	if tree == null:
		return surfaces
	for candidate: Node in tree.get_nodes_in_group(
		ProductionWorldSurface.MOUNT_GROUP
	):
		if candidate is ProductionWorldSurface:
			surfaces.append(candidate as ProductionWorldSurface)
	return surfaces


static func _mapper_clone_result(tree: SceneTree) -> Dictionary:
	var coordinators: Array[Node] = []
	for node: Node in tree.get_nodes_in_group(
		ProductionViewportCoordinator.COORDINATOR_GROUP
	):
		if node.has_method(&"coordinate_mapper_clone"):
			coordinators.append(node)
	if coordinators.is_empty():
		return {"error": COORDINATOR_MISSING}
	if coordinators.size() != 1:
		return {"error": COORDINATOR_AMBIGUOUS}
	var coordinator := coordinators[0]
	if coordinator.has_method(&"coordinate_mapper_error"):
		var coordinator_error := StringName(
			coordinator.call(&"coordinate_mapper_error")
		)
		if not coordinator_error.is_empty():
			return {"error": coordinator_error}
	var mapper_value: Variant = coordinator.call(&"coordinate_mapper_clone")
	if not mapper_value is WindowCoordinateMapper:
		return {"error": WindowCoordinateMapper.NOT_CONFIGURED}
	var mapper := mapper_value as WindowCoordinateMapper
	var mapper_error := mapper.configuration_error()
	if not mapper_error.is_empty():
		return {"error": mapper_error}
	return {"mapper": mapper, "error": &""}
