class_name ResultInvariant
extends RefCounted

const ERROR_MESSAGE: String = "RESULT_MUTUAL_EXCLUSION"

static func is_valid(
	p_ok: bool,
	p_error: RefCounted,
	p_success_payload_valid: bool,
	p_failure_payload_clear: bool
) -> bool:
	if p_ok:
		return p_error == null and p_success_payload_valid
	return p_error != null and p_failure_payload_clear

static func require(
	p_ok: bool,
	p_error: RefCounted,
	p_success_payload_valid: bool,
	p_failure_payload_clear: bool
) -> void:
	assert(
		is_valid(
			p_ok, p_error, p_success_payload_valid, p_failure_payload_clear
		),
		ERROR_MESSAGE
	)
