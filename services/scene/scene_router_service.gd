class_name SceneRouterService
extends Node

const ERROR_HOST_NOT_BOUND: StringName = &"SCENE_ROUTER_HOST_NOT_BOUND"
const ERROR_SCENE_INVALID: StringName = &"SCENE_ROUTER_SCENE_INVALID"
const ERROR_CATALOG_NOT_BOUND: StringName = &"SCENE_ROUTER_CATALOG_NOT_BOUND"
const ERROR_CATALOG_INVALID: StringName = &"SCENE_ROUTER_CATALOG_INVALID"
const ERROR_CONTEXT_INVALID: StringName = &"SCENE_ROUTER_CONTEXT_INVALID"
const ERROR_ROUTE_INVALID: StringName = &"SCENE_ROUTER_ROUTE_INVALID"
const ERROR_ROUTE_MISMATCH: StringName = &"SCENE_ROUTER_ROUTE_MISMATCH"
const ERROR_PREPARED_FORGED: StringName = &"SCENE_ROUTER_PREPARED_FORGED"
const ERROR_PREPARED_WRONG_ROUTER: StringName = \
	&"SCENE_ROUTER_PREPARED_WRONG_ROUTER"
const ERROR_PREPARED_REPLAYED: StringName = \
	&"SCENE_ROUTER_PREPARED_REPLAYED"

var _presentation_host: Control
var _production_catalog: ProductionSceneCatalog
var _router_identity: StringName = StringName(
	"scene.router.%d" % _next_router_sequence()
)
var _prepared_issuer := RefCounted.new()
var _next_prepared_nonce: int = 1
var _pending_prepared: Dictionary[int, PreparedProductionRoute] = {}


func bind_presentation_host(host: Control) -> void:
	_presentation_host = host


func bind_production_catalog(catalog: ProductionSceneCatalog) -> StringName:
	if catalog == null:
		return ERROR_CATALOG_INVALID
	_production_catalog = catalog
	return &""


func install_production(
	route_kind: StringName,
	context: StagedScreenContext
) -> StringName:
	var prepared := prepare_production(route_kind, context, null)
	if not prepared.ok:
		return prepared.error.source_code
	return commit_prepared(prepared.prepared)


func prepare_production(
	route_kind: StringName,
	context: StagedScreenContext,
	live_context: ProductionLiveScreenContext = null
) -> PreparedProductionRouteResult:
	if _presentation_host == null or not is_instance_valid(_presentation_host):
		return PreparedProductionRouteResult.failure(ERROR_HOST_NOT_BOUND)
	if _production_catalog == null:
		return PreparedProductionRouteResult.failure(ERROR_CATALOG_NOT_BOUND)
	if context == null or context.route_kind != route_kind:
		return PreparedProductionRouteResult.failure(ERROR_CONTEXT_INVALID)
	if route_kind.is_empty() or _production_catalog.scene_path(route_kind).is_empty():
		return PreparedProductionRouteResult.failure(ERROR_ROUTE_INVALID)

	var candidate: ProductionScreen = _production_catalog.instantiate(route_kind)
	if candidate == null:
		return PreparedProductionRouteResult.failure(ERROR_SCENE_INVALID)
	if candidate.route_kind != route_kind:
		candidate.free()
		return PreparedProductionRouteResult.failure(ERROR_ROUTE_MISMATCH)

	candidate.visible = false
	var bind_error: StringName = candidate.bind(context)
	if not bind_error.is_empty():
		candidate.free()
		return PreparedProductionRouteResult.failure(bind_error)
	if live_context != null:
		var live_error := candidate.prepare_live_binding(live_context)
		if not live_error.is_empty():
			candidate.free()
			return PreparedProductionRouteResult.failure(live_error)
	var issue_nonce := _next_prepared_nonce
	_next_prepared_nonce += 1
	var prepared := PreparedProductionRoute.new(
		_prepared_issuer,
		route_kind,
		candidate,
		issue_nonce
	)
	_pending_prepared[issue_nonce] = prepared
	return PreparedProductionRouteResult.success(prepared)


func commit_prepared(prepared: PreparedProductionRoute) -> StringName:
	var validation_error := prepared_error(prepared)
	if not validation_error.is_empty():
		return validation_error
	var candidate: ProductionScreen = prepared._candidate
	_pending_prepared.erase(prepared._issue_nonce)
	prepared._consumed = true
	prepared._candidate = null

	var old_children: Array[Node] = []
	old_children.assign(_presentation_host.get_children())
	_presentation_host.add_child(candidate)
	candidate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child: Node in old_children:
		_retire_live_child(child)
	candidate.activate_live()
	candidate.visible = true
	return &""


func discard_prepared(prepared: PreparedProductionRoute) -> StringName:
	var validation_error := prepared_error(prepared)
	if not validation_error.is_empty():
		return validation_error
	_pending_prepared.erase(prepared._issue_nonce)
	prepared._consumed = true
	var candidate: ProductionScreen = prepared._candidate
	prepared._candidate = null
	if candidate != null:
		candidate.free()
	return &""


func prepared_error(prepared: PreparedProductionRoute) -> StringName:
	if prepared == null or prepared._issuer == null:
		return ERROR_PREPARED_FORGED
	if prepared._issuer != _prepared_issuer:
		return ERROR_PREPARED_WRONG_ROUTER
	if prepared._consumed:
		return ERROR_PREPARED_REPLAYED
	if (
		prepared._issue_nonce < 1
		or _pending_prepared.get(prepared._issue_nonce) != prepared
		or prepared._candidate == null
		or prepared._candidate.route_kind != prepared._route_kind
	):
		return ERROR_PREPARED_FORGED
	return &""


func replace_presentation(scene: PackedScene) -> StringName:
	if _presentation_host == null or not is_instance_valid(_presentation_host):
		return ERROR_HOST_NOT_BOUND
	if scene == null:
		return ERROR_SCENE_INVALID
	var candidate: Node = scene.instantiate()
	if candidate == null:
		return ERROR_SCENE_INVALID
	if candidate is CanvasItem:
		(candidate as CanvasItem).visible = false

	var old_children: Array[Node] = []
	old_children.assign(_presentation_host.get_children())
	_presentation_host.add_child(candidate)
	if candidate is Control:
		(candidate as Control).set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
	for child: Node in old_children:
		_retire_live_child(child)
	if candidate is CanvasItem:
		(candidate as CanvasItem).visible = true
	return &""


func presentation_host() -> Control:
	return _presentation_host


func _retire_live_child(child: Node) -> void:
	if child is CanvasItem:
		(child as CanvasItem).visible = false
	child.process_mode = Node.PROCESS_MODE_DISABLED
	child.reparent(self, false)
	child.queue_free()


static var _router_sequence: int = 1


static func _next_router_sequence() -> int:
	var result := _router_sequence
	_router_sequence += 1
	return result
