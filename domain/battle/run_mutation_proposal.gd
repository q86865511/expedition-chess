class_name RunMutationProposal
extends RefCounted

const CLAIM_SCOPES: Array[StringName] = [&"once_per_node", &"on_first_clear"]
const OPERATION_KINDS: Array[StringName] = [&"add_gold", &"add_xp", &"heal_expedition_hp"]
const _MAX_U32: int = 0xffffffff

var claim_scope: StringName
var source_instance_or_slot: String
var effect_id: StringName
var operation_index: int
var operation_kind: StringName
var amount: int
var payload_digest: String


static func create(
	p_claim_scope: StringName,
	p_source_instance_or_slot: String,
	p_effect_id: StringName,
	p_operation_index: int,
	p_operation_kind: StringName,
	p_amount: int
) -> RunMutationProposalBuildResult:
	var validation_error := _validate_fields(
		p_claim_scope,
		p_source_instance_or_slot,
		p_effect_id,
		p_operation_index,
		p_operation_kind,
		p_amount
	)
	if validation_error != null:
		return RunMutationProposalBuildResult.failure(validation_error)
	var digest := _digest(
		p_claim_scope,
		p_source_instance_or_slot,
		p_effect_id,
		p_operation_index,
		p_operation_kind,
		p_amount
	)
	return RunMutationProposalBuildResult.success(
		RunMutationProposal.new(
			p_claim_scope,
			p_source_instance_or_slot,
			p_effect_id,
			p_operation_index,
			p_operation_kind,
			p_amount,
			digest
		)
	)


static func restore(
	p_claim_scope: StringName,
	p_source_instance_or_slot: String,
	p_effect_id: StringName,
	p_operation_index: int,
	p_operation_kind: StringName,
	p_amount: int,
	p_payload_digest: String
) -> RunMutationProposalBuildResult:
	var built := create(
		p_claim_scope,
		p_source_instance_or_slot,
		p_effect_id,
		p_operation_index,
		p_operation_kind,
		p_amount
	)
	if not built.ok:
		return built
	if built.proposal.payload_digest != p_payload_digest:
		return RunMutationProposalBuildResult.failure(
			RunMutationProposalError.new(
				RunMutationProposalError.DIGEST_MISMATCH,
				&"payload_digest"
			)
		)
	return built


static func _validate_fields(
	p_claim_scope: StringName,
	p_source_instance_or_slot: String,
	p_effect_id: StringName,
	p_operation_index: int,
	p_operation_kind: StringName,
	p_amount: int
) -> RunMutationProposalError:
	if not CLAIM_SCOPES.has(p_claim_scope):
		return RunMutationProposalError.new(
			RunMutationProposalError.CLAIM_SCOPE_INVALID,
			&"claim_scope"
		)
	if not ProposalSourceCodecV1.new().validate(p_source_instance_or_slot).ok:
		return RunMutationProposalError.new(
			RunMutationProposalError.SOURCE_INVALID,
			&"source_instance_or_slot"
		)
	if not StableIdValidator.new().is_valid(p_effect_id):
		return RunMutationProposalError.new(
			RunMutationProposalError.EFFECT_ID_INVALID,
			&"effect_id"
		)
	if not OPERATION_KINDS.has(p_operation_kind):
		return RunMutationProposalError.new(
			RunMutationProposalError.OPERATION_INVALID,
			&"operation_kind"
		)
	if p_operation_index < 0 or p_operation_index > _MAX_U32 \
		or p_amount < 0 or p_amount > _MAX_U32:
		return RunMutationProposalError.new(
			RunMutationProposalError.RANGE_INVALID,
			&"operation_index" if p_operation_index < 0 or p_operation_index > _MAX_U32 \
				else &"amount"
		)
	return null


static func _digest(
	p_claim_scope: StringName,
	p_source_instance_or_slot: String,
	p_effect_id: StringName,
	p_operation_index: int,
	p_operation_kind: StringName,
	p_amount: int
) -> String:
	var bytes := "RMP2".to_ascii_buffer()
	_append_ascii(bytes, String(p_claim_scope))
	_append_ascii(bytes, p_source_instance_or_slot)
	_append_ascii(bytes, String(p_effect_id))
	_append_u32(bytes, p_operation_index)
	_append_ascii(bytes, String(p_operation_kind))
	_append_u32(bytes, p_amount)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


static func _append_ascii(bytes: PackedByteArray, value: String) -> void:
	var raw := value.to_ascii_buffer()
	_append_u32(bytes, raw.size())
	bytes.append_array(raw)


static func _append_u32(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 24) & 0xff)
	bytes.append((value >> 16) & 0xff)
	bytes.append((value >> 8) & 0xff)
	bytes.append(value & 0xff)


func _init(
	p_claim_scope: StringName,
	p_source_instance_or_slot: String,
	p_effect_id: StringName,
	p_operation_index: int,
	p_operation_kind: StringName,
	p_amount: int,
	p_payload_digest: String
) -> void:
	claim_scope = p_claim_scope
	source_instance_or_slot = p_source_instance_or_slot
	effect_id = p_effect_id
	operation_index = p_operation_index
	operation_kind = p_operation_kind
	amount = p_amount
	payload_digest = p_payload_digest


func identity_key() -> String:
	return "%s|%s|%s|%010d" % [
		String(claim_scope),
		source_instance_or_slot,
		String(effect_id),
		operation_index,
	]


func deep_clone() -> RunMutationProposal:
	return RunMutationProposal.new(
		claim_scope,
		source_instance_or_slot,
		effect_id,
		operation_index,
		operation_kind,
		amount,
		payload_digest
	)
