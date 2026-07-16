class_name RunMutationProposalError
extends RefCounted

const CLAIM_SCOPE_INVALID: StringName = &"RUN_PROPOSAL_CLAIM_SCOPE_INVALID"
const SOURCE_INVALID: StringName = &"RUN_PROPOSAL_SOURCE_INVALID"
const EFFECT_ID_INVALID: StringName = &"RUN_PROPOSAL_EFFECT_ID_INVALID"
const OPERATION_INVALID: StringName = &"RUN_PROPOSAL_OPERATION_INVALID"
const RANGE_INVALID: StringName = &"RUN_PROPOSAL_RANGE_INVALID"
const DIGEST_MISMATCH: StringName = &"RUN_PROPOSAL_DIGEST_MISMATCH"

var code: StringName
var field_path: StringName


func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path


func deep_clone() -> RunMutationProposalError:
	return RunMutationProposalError.new(code, field_path)
