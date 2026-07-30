class_name SettingsActivationToken
extends RefCounted

const ACTIVATION_NOT_IMPLEMENTED: StringName = &"SETTINGS_ACTIVATION_NOT_IMPLEMENTED"

var candidate_digest: String


func _init(p_candidate_digest: String = "") -> void:
	candidate_digest = p_candidate_digest


# A concrete token captures only already-validated primitive assignments.  The
# base contract deliberately owns no snapshot, repository, or adapter reference.
func activate() -> StringName:
	return ACTIVATION_NOT_IMPLEMENTED
