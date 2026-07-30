class_name ProjectContentBootstrapError
extends RefCounted

var code: StringName
var message: String


func _init(p_code: StringName, p_message: String) -> void:
	code = p_code
	message = p_message
