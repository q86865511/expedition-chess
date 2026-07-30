class_name SettingsAdapterPort
extends RefCounted

const NOT_IMPLEMENTED: StringName = &"SETTINGS_ADAPTER_NOT_IMPLEMENTED"


func preflight(
	plan: SettingsSnapshot,
	candidate_digest: String
) -> SettingsAdapterPreflightResult:
	return SettingsAdapterPreflightResult.failure(
		DiagnosticError.new(
			NOT_IMPLEMENTED,
			&"error.settings.adapter_not_implemented"
		)
	)


func activate_safe_fallback() -> void:
	pass


func rebuild_from_committed(snapshot: SettingsSnapshot) -> void:
	pass
