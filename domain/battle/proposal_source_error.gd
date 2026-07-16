class_name ProposalSourceError
extends RefCounted

const TOKEN_INVALID: StringName = &"PROPOSAL_SOURCE_TOKEN_INVALID"
const UNIT_ID_INVALID: StringName = &"PROPOSAL_SOURCE_UNIT_ID_INVALID"
const STABLE_ID_INVALID: StringName = &"PROPOSAL_SOURCE_STABLE_ID_INVALID"
const SLOT_INVALID: StringName = &"PROPOSAL_SOURCE_SLOT_INVALID"

var code: StringName
var field_path: StringName


func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path


func deep_clone() -> ProposalSourceError:
	return ProposalSourceError.new(code, field_path)
