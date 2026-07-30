class_name MenuExitPresenter
extends RefCounted

const BIND_TARGET_INVALID: StringName = &"MENU_EXIT_BIND_TARGET_INVALID"
const HOST_INVALID: StringName = &"MENU_EXIT_HOST_INVALID"
const ALREADY_BOUND: StringName = &"MENU_EXIT_ALREADY_BOUND"

var _host: Object
var _button: BaseButton


func bind_exit_button(button: BaseButton, host: Object) -> StringName:
	if button == null:
		return BIND_TARGET_INVALID
	if host == null or not host.has_method(&"request_exit"):
		return HOST_INVALID
	if _button != null:
		return ALREADY_BOUND
	_button = button
	_host = host
	_button.pressed.connect(_on_exit_pressed)
	return &""


func _on_exit_pressed() -> void:
	if _host != null:
		_host.call(&"request_exit")
