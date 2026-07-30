class_name SettingsApplicationPort
extends RefCounted

const NOT_IMPLEMENTED: StringName = &"SETTINGS_APPLICATION_NOT_IMPLEMENTED"


func apply(candidate: SettingsSnapshot) -> SettingsApplicationResult:
	return SettingsApplicationResult.failure(
		DiagnosticError.new(NOT_IMPLEMENTED, &"error.settings.application_not_implemented")
	)
