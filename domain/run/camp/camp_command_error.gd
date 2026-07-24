class_name CampCommandError
extends RefCounted

## T04 (design.md §4.1): structural/mechanical failures of the CampController
## transaction pipeline itself, namespaced CAMP_*. `code` is an open StringName,
## not a closed enum: when a command's apply_to() rejects for a *domain* reason
## (e.g. UNLOCK_INSUFFICIENT_CURRENCY) CampController passes that domain code
## straight through into this same `code` field -- both namespaces coexist
## without collision (see tests/fixtures/camp/purchase_unlock_test_fixture.gd).

const INVALID_COMMAND: StringName = &"CAMP_INVALID_COMMAND"
const VALIDATION_FAILED: StringName = &"CAMP_VALIDATION_FAILED"
const SAVE_FAILED: StringName = &"CAMP_SAVE_FAILED"
const TRANSACTION_BUSY: StringName = &"CAMP_TRANSACTION_BUSY"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> CampCommandError:
	return CampCommandError.new(code, field_path)
