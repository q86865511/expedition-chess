class_name SceneRouterService
extends Node

const ERROR_HOST_NOT_BOUND: StringName = &"SCENE_ROUTER_HOST_NOT_BOUND"
const ERROR_SCENE_INVALID: StringName = &"SCENE_ROUTER_SCENE_INVALID"

var _presentation_host: Control


func bind_presentation_host(host: Control) -> void:
	_presentation_host = host


func replace_presentation(scene: PackedScene) -> StringName:
	if _presentation_host == null:
		return ERROR_HOST_NOT_BOUND
	if scene == null:
		return ERROR_SCENE_INVALID
	for child: Node in _presentation_host.get_children():
		_presentation_host.remove_child(child)
		child.queue_free()
	var instance: Node = scene.instantiate()
	_presentation_host.add_child(instance)
	return &""


func presentation_host() -> Control:
	return _presentation_host

