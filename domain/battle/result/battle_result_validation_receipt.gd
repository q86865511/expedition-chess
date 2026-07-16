class_name BattleResultValidationReceipt
extends RefCounted

var battle_setup_hash: StringName
var battle_setup_envelope_digest: StringName
var result_hash: StringName

func _init(
	p_setup_hash: StringName,
	p_envelope_digest: StringName,
	p_result_hash: StringName
) -> void:
	battle_setup_hash = p_setup_hash
	battle_setup_envelope_digest = p_envelope_digest
	result_hash = p_result_hash

func deep_clone() -> BattleResultValidationReceipt:
	return BattleResultValidationReceipt.new(
		battle_setup_hash, battle_setup_envelope_digest, result_hash
	)
