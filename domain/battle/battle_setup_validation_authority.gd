class_name BattleSetupValidationAuthority
extends RefCounted

var _issuer_nonce: RefCounted = RefCounted.new()

# The production source scanner permits issuance only through
# BattleSetupInputsValidator's trusted authority.
func _issue_validated(inputs_digest: StringName) -> BattleSetupValidationReceipt:
	if not _is_digest(inputs_digest):
		return null
	return BattleSetupValidationReceipt.new(inputs_digest, _issuer_nonce)

func _verifies(
	receipt: BattleSetupValidationReceipt,
	expected_digest: StringName
) -> bool:
	return receipt != null \
		and _is_digest(expected_digest) \
		and receipt._matches(_issuer_nonce, expected_digest)

func _is_digest(value: StringName) -> bool:
	var text := String(value)
	if text.length() != 64:
		return false
	for index: int in range(text.length()):
		var code := text.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true
