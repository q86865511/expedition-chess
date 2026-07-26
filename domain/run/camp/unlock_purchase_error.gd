class_name UnlockPurchaseError
extends RefCounted

## T04 (specs/meta-progression/design.md §4.3, §13; requirements.md S5-AC-011):
## the three named purchase-rejection codes plus a structural INPUT_INVALID.
## UnlockPurchaseService is the sole producer of these codes. `code` is an open
## StringName so CampController can pass a domain rejection straight through
## into CampCommandError.code without remapping (see the binding contract in
## tests/fixtures/camp/purchase_unlock_test_fixture.gd).

const UNLOCK_INSUFFICIENT_CURRENCY: StringName = &"UNLOCK_INSUFFICIENT_CURRENCY"
const UNLOCK_ALREADY_OWNED: StringName = &"UNLOCK_ALREADY_OWNED"
const UNLOCK_PREREQUISITE_UNMET: StringName = &"UNLOCK_PREREQUISITE_UNMET"
const INPUT_INVALID: StringName = &"UNLOCK_INPUT_INVALID"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> UnlockPurchaseError:
	return UnlockPurchaseError.new(code, field_path)
