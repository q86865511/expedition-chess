class_name NodeServicePendingResolutionState
extends ResolutionState

var service_kind: StringName
var node_id: StringName
var choice_receipt_digest: String

func _init(
	p_service_kind: StringName,
	p_node_id: StringName,
	p_choice_receipt_digest: String
) -> void:
	super(Kind.NODE_SERVICE_PENDING)
	service_kind = p_service_kind
	node_id = p_node_id
	choice_receipt_digest = p_choice_receipt_digest

func deep_clone() -> ResolutionState:
	return NodeServicePendingResolutionState.new(
		service_kind, node_id, choice_receipt_digest
	)
