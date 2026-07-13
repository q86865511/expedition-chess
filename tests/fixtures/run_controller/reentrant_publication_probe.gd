class_name ReentrantPublicationProbe
extends RefCounted

var controller: RunController
var result: CommandResult
var callback_count: int = 0

func _init(p_controller: RunController) -> void:
	controller = p_controller

func capture(_view: RunViewState) -> void:
	callback_count += 1
	result = controller.dispatch(
		TestMutationCommand.new(TestMutationCommand.Kind.SET_HP, 1)
	)
