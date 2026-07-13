class_name DtoValidationResult
extends RefCounted

var ok: bool
var error: DtoValidationError

static func success() -> DtoValidationResult:
	return DtoValidationResult.new(true, null)

static func failure(p_error: DtoValidationError) -> DtoValidationResult:
	return DtoValidationResult.new(false, p_error)

func _init(p_ok: bool, p_error: DtoValidationError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error.deep_clone() if p_error != null else null

func deep_clone() -> DtoValidationResult:
	return DtoValidationResult.new(ok, error)
