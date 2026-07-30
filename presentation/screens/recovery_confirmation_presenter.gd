class_name RecoveryConfirmationPresenter
extends RefCounted

const RECOVERY_PORT_INVALID: StringName = &"RECOVERY_PORT_INVALID"
const RECOVERY_TOKEN_INVALID: StringName = &"RECOVERY_TOKEN_INVALID"
const CONFIRMATION_ALREADY_OPEN: StringName = &"RECOVERY_CONFIRMATION_ALREADY_OPEN"
const CONFIRMATION_NOT_OPEN: StringName = &"RECOVERY_CONFIRMATION_NOT_OPEN"

var _port: Object
var _pending_token: RetainedRunRecoveryToken
var _status_key: StringName = &""
var _confirmation_open: bool = false


func bind(port: Object) -> StringName:
	if port == null or not port.has_method(&"submit_discard"):
		return RECOVERY_PORT_INVALID
	_port = port
	return &""


func begin_confirmation(
	token: RetainedRunRecoveryToken,
	localized_status_key: StringName
) -> StringName:
	if _port == null:
		return RECOVERY_PORT_INVALID
	if token == null or not token.is_issued():
		return RECOVERY_TOKEN_INVALID
	if _confirmation_open:
		return CONFIRMATION_ALREADY_OPEN
	_pending_token = token
	_status_key = localized_status_key
	_confirmation_open = true
	return &""


func is_confirmation_open() -> bool:
	return _confirmation_open


func cancel_confirmation() -> StringName:
	if not _confirmation_open:
		return CONFIRMATION_NOT_OPEN
	_confirmation_open = false
	_pending_token = null
	return &""


func confirm_confirmation() -> SaveResult:
	if not _confirmation_open or _port == null or _pending_token == null:
		return SaveResult.failure(
			SaveError.new(
				CONFIRMATION_NOT_OPEN,
				&"recovery.confirmation"
			)
		)
	var token := _pending_token
	_confirmation_open = false
	_pending_token = null
	return _port.call(&"submit_discard", token) as SaveResult


func status_key() -> StringName:
	return _status_key
