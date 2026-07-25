class_name StartExpeditionError
extends RefCounted

## T05 (specs/meta-progression/design.md SS4.2, SS13; requirements.md S5-AC-002,
## S5-AC-009 前置檢查段): the two named start-rejection codes plus a structural
## INPUT_INVALID. StartExpeditionCommand is the sole producer of these codes.
## `code` is an open StringName so CampController can pass a domain rejection
## straight through into CampCommandError.code without remapping (same convention
## as UnlockPurchaseError; see tests/fixtures/camp/start_expedition_test_fixture.gd).

const EXPEDITION_COMMANDER_LOCKED: StringName = &"EXPEDITION_COMMANDER_LOCKED"
const EXPEDITION_CHALLENGE_PREREQUISITE_UNMET: StringName = &"EXPEDITION_CHALLENGE_PREREQUISITE_UNMET"
const INPUT_INVALID: StringName = &"EXPEDITION_INPUT_INVALID"
## profile.next_run_serial is bumped on every successful start; U64Bits.add() wraps
## silently at the ceiling, so the exhausted case gets its own code -- the same
## convention every other serial bump in the project follows (see
## battle_settlement_service.gd's next_transaction_serial guard).
const SERIAL_EXHAUSTED: StringName = &"EXPEDITION_SERIAL_EXHAUSTED"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> StartExpeditionError:
	return StartExpeditionError.new(code, field_path)
