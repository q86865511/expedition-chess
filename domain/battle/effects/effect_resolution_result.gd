class_name EffectResolutionResult
extends RefCounted

var ok: bool
var resolution: EffectResolution
var error: EffectResolverError

static func success(value: EffectResolution) -> EffectResolutionResult:
	return EffectResolutionResult.new(true, value, null)

static func failure(code: StringName, path: StringName = &"") -> EffectResolutionResult:
	return EffectResolutionResult.new(false, null, EffectResolverError.new(code, path))

func _init(
	p_ok: bool,
	p_resolution: EffectResolution,
	p_error: EffectResolverError
) -> void:
	ResultInvariant.require(
		p_ok, p_error, p_resolution != null, p_resolution == null
	)
	ok = p_ok
	resolution = p_resolution.deep_clone() if p_resolution != null else null
	error = p_error.deep_clone() if p_error != null else null
