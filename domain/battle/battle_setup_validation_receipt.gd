class_name BattleSetupValidationReceipt
extends RefCounted

var _inputs_digest: StringName
var _issuer_nonce: RefCounted

func _init(p_inputs_digest: StringName, p_issuer_nonce: RefCounted) -> void:
	_inputs_digest = p_inputs_digest
	_issuer_nonce = p_issuer_nonce

func _matches(issuer_nonce: RefCounted, expected_digest: StringName) -> bool:
	return _issuer_nonce != null \
		and _issuer_nonce == issuer_nonce \
		and _inputs_digest == expected_digest

func deep_clone() -> BattleSetupValidationReceipt:
	return BattleSetupValidationReceipt.new(_inputs_digest, _issuer_nonce)
