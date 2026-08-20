class_name MapNodePresentation
extends RefCounted

var node_id: String
var def_id: StringName
var act_index: int
var layer_index: int
var slot_index: int
var kind: StringName
var completed: bool
var reachable: bool
var encounter_preview: EncounterPreviewSnapshot


func _init(
	p_node_id: String,
	p_def_id: StringName,
	p_act_index: int,
	p_layer_index: int,
	p_slot_index: int,
	p_kind: StringName,
	p_completed: bool,
	p_reachable: bool,
	p_encounter_preview: EncounterPreviewSnapshot
) -> void:
	node_id = p_node_id
	def_id = p_def_id
	act_index = p_act_index
	layer_index = p_layer_index
	slot_index = p_slot_index
	kind = p_kind
	completed = p_completed
	reachable = p_reachable
	encounter_preview = (
		p_encounter_preview.deep_clone() if p_encounter_preview != null else null
	)


## 「這個節點現在可不可以選」的呈現層入口，權威判準在 domain 的 MapFrontier：
## 自 map_state.current_node_id 出發、一步邊可達且尚未完成才成立。與 domain 的
## NodeEntryService.enter() 同源，畫面亮起的集合因此恆等於會被受理的集合。
##
## 語意變更（C-1）：本方法原本判的是「拓撲可達」——任一已完成節點指向它即可。
## 每層之間是完全二分連邊，於是上一層沒選走的兄弟分支永遠亮著且真的能進去。
## 現在只認目前所在節點的出邊；歷史分支一律不可選。
##
## 仍留在 presentation/run（豁免 PUI_SCREEN_WRITER_DEPENDENCY 掃描）是為了讓
## RunMapScreen 不必 import RunPresentationSession——後者在 presentation/screens/*.gd
## 會被靜態閘判定為 canonical writer 相依。
static func is_reachable(map_state: MapState, node: MapNodeState) -> bool:
	return MapFrontier.is_frontier_node(map_state, node)


static func from_state(
	state: MapNodeState,
	p_reachable: bool
) -> MapNodePresentation:
	return MapNodePresentation.new(
		state.node_id,
		state.def_id,
		state.act_index,
		state.layer_index,
		state.slot_index,
		MapNodeState.node_kind_to_token(state.node_kind),
		state.completed,
		p_reachable,
		state.encounter_preview
	)


func deep_clone() -> MapNodePresentation:
	return MapNodePresentation.new(
		node_id,
		def_id,
		act_index,
		layer_index,
		slot_index,
		kind,
		completed,
		reachable,
		encounter_preview
	)
