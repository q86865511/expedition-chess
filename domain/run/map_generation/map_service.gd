class_name MapService
extends RefCounted

const ACT_COUNT: int = 3
const LAYER_COUNT: int = 7

func generate_map(request: MapGenerationRequest) -> MapGenerationResult:
	if request == null or request.run_id.is_empty() or request.run_seed == null or request.catalog == null:
		return MapGenerationResult.failure(MapGenerationError.INPUT_INVALID, &"request")
	var derived := RngService.new().derive_stream(
		request.run_seed, &"map", StringName("%s:expedition_map_v1" % String(request.run_id))
	)
	if not derived.ok:
		return MapGenerationResult.failure(MapGenerationError.RNG_FAILED, derived.error.field_path)
	var stream := derived.stream
	var nodes: Array[MapNodeState] = []
	var edges: Array[MapEdgeState] = []
	var previous_layer: Array[MapNodeState] = []
	for act_index: int in range(1, ACT_COUNT + 1):
		for layer_index: int in range(LAYER_COUNT):
			var width := 1
			if layer_index >= 1 and layer_index <= 4:
				var width_draw := stream.next_bounded(2)
				if not width_draw.ok:
					return MapGenerationResult.failure(MapGenerationError.RNG_FAILED, &"width")
				width = 2 + width_draw.value_u32.low_u32()
			var current_layer: Array[MapNodeState] = []
			for slot_index: int in range(width):
				var kind_result := _kind_for_layer(layer_index, stream)
				if kind_result < 0:
					return MapGenerationResult.failure(MapGenerationError.RNG_FAILED, &"node_kind")
				var rules := request.catalog.map_nodes_for(kind_result)
				if rules.is_empty():
					return MapGenerationResult.failure(MapGenerationError.RULE_MISSING, &"map_nodes")
				var rule_draw := stream.next_bounded(rules.size())
				if not rule_draw.ok:
					return MapGenerationResult.failure(MapGenerationError.RNG_FAILED, &"definition")
				var rule := rules[rule_draw.value_u32.low_u32()]
				var key_result := RuntimeKeySchemaRegistry.new().build_node(
					request.run_id, act_index, MapNodeState.node_kind_to_token(kind_result), layer_index, slot_index
				)
				if not key_result.ok:
					return MapGenerationResult.failure(MapGenerationError.KEY_FAILED, key_result.error.field_path)
				var key := key_result.key_state as NodeKeyState
				var payload_digest := _payload_digest(request.catalog.manifest_digest_value(), rule.definition_id, key.digest)
				if payload_digest.is_empty():
					return MapGenerationResult.failure(MapGenerationError.DIGEST_FAILED, &"payload_digest")
				var node := MapNodeState.new(
					String(key.digest), key, rule.definition_id, act_index, layer_index,
					slot_index, kind_result, payload_digest, null, false
				)
				nodes.append(node)
				current_layer.append(node)
			for left: MapNodeState in previous_layer:
				for right: MapNodeState in current_layer:
					edges.append(MapEdgeState.new(left.node_id, right.node_id))
			previous_layer = current_layer
	_sort_edges(edges)
	var completed: Array[String] = []
	return MapGenerationResult.success(MapState.new(nodes, edges, null, completed), stream.snapshot())

func _kind_for_layer(layer_index: int, stream: Pcg32Stream) -> int:
	match layer_index:
		0:
			return MapNodeState.NodeKind.NORMAL
		5:
			return MapNodeState.NodeKind.REST
		6:
			return MapNodeState.NodeKind.BOSS
		1, 3:
			var draw := stream.next_bounded(4)
			if not draw.ok:
				return -1
			return MapNodeState.NodeKind.ELITE if draw.value_u32.low_u32() == 0 else MapNodeState.NodeKind.NORMAL
		2, 4:
			var draw := stream.next_bounded(3)
			if not draw.ok:
				return -1
			return [MapNodeState.NodeKind.MERCHANT, MapNodeState.NodeKind.EVENT, MapNodeState.NodeKind.TREASURE][draw.value_u32.low_u32()]
	return -1

func _payload_digest(manifest_digest: String, definition_id: StringName, node_digest: StringName) -> String:
	var bytes := ("MAP1|%s|%s|%s" % [manifest_digest, String(definition_id), String(node_digest)]).to_utf8_buffer()
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

func _sort_edges(edges: Array[MapEdgeState]) -> void:
	edges.sort_custom(func(left: MapEdgeState, right: MapEdgeState) -> bool:
		return left.from_node_id + "/" + left.to_node_id < right.from_node_id + "/" + right.to_node_id
	)
