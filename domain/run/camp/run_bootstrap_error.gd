class_name RunBootstrapError
extends RefCounted

## T05 (specs/meta-progression/design.md SS4.2): RunBootstrapService performs no
## *business* validation -- commander-locked / challenge-prerequisite are
## StartExpeditionCommand's job, checked BEFORE calling build(). The only failure
## the service itself can surface is structural (malformed profile / commander_def
## / pinned_receipt / derived key), so a single INPUT_INVALID code suffices.

const INPUT_INVALID: StringName = &"RUN_BOOTSTRAP_INPUT_INVALID"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> RunBootstrapError:
	return RunBootstrapError.new(code, field_path)
