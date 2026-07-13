class_name ClaimReceiptState
extends RefCounted

var key: EffectClaimKeyState
var payload_digest: String

func _init(p_key: EffectClaimKeyState, p_payload_digest: String) -> void:
	key = p_key.deep_clone()
	payload_digest = p_payload_digest

func deep_clone() -> ClaimReceiptState:
	return ClaimReceiptState.new(key, payload_digest)
