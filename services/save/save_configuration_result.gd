class_name SaveConfigurationResult
extends RefCounted

var ok: bool
var error: SaveConfigurationError

static func success() -> SaveConfigurationResult:
	return SaveConfigurationResult.new(true, null)

static func failure(p_error: SaveConfigurationError) -> SaveConfigurationResult:
	return SaveConfigurationResult.new(false, p_error)

func _init(p_ok: bool, p_error: SaveConfigurationError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error.deep_clone() if p_error != null else null
