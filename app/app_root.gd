class_name ApplicationRoot
extends Node

signal boot_completed
signal boot_failed(error_code: StringName)

@onready var presentation_host: Control = $PresentationHost

var _booted: bool = false
var _app_state_machine: AppStateMachine = AppStateMachine.new()
var _run_session: RunSession
var _run_controller: RunController


func _ready() -> void:
	if presentation_host == null:
		boot_failed.emit(&"APP_PRESENTATION_HOST_MISSING")
		return
	var content_registry := get_node_or_null("/root/ContentRegistry") as ContentRegistryService
	var save_repository := get_node_or_null("/root/SaveService") as SaveRepository
	var scene_router := get_node_or_null("/root/SceneRouter") as SceneRouterService
	if content_registry == null or save_repository == null or scene_router == null:
		boot_failed.emit(&"APP_REQUIRED_SERVICE_MISSING")
		return
	var receipt_port := ContentRegistryReceiptAdapter.new(content_registry)
	var migration_port := ContentRegistryMigrationAdapter.new(content_registry)
	var save_configuration: SaveConfigurationResult = (
		save_repository._configure_content_ports(receipt_port, migration_port)
	)
	if not save_configuration.ok:
		boot_failed.emit(save_configuration.error.code)
		return
	_app_state_machine = AppStateMachine.new(save_repository)
	scene_router.bind_presentation_host(presentation_host)
	var boot_transition := _app_state_machine.transition(
		AppEvent.new(AppEvent.Kind.BOOT_COMPLETED)
	)
	if not boot_transition.ok:
		boot_failed.emit(boot_transition.error.code)
		return
	_booted = true
	boot_completed.emit()


func is_booted() -> bool:
	return _booted


func get_presentation_host() -> Control:
	return presentation_host


func app_state() -> AppStateMachine.State:
	return _app_state_machine.state()


func has_active_run() -> bool:
	return _run_session != null and _run_controller != null
