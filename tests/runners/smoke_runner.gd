extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const ARTIFACT_PATH: String = "res://artifacts/test/smoke.json"

var _started_at_utc: String = ""


func _init() -> void:
	_started_at_utc = Support.utc_now()
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var infrastructure_error: bool = false
	var required_autoloads: Array[String] = [
		"ContentRegistry",
		"SaveService",
		"SettingsService",
		"AudioService",
		"SceneRouter",
	]
	for autoload_name: String in required_autoloads:
		if not get_root().has_node(NodePath(autoload_name)):
			failures.append("Missing autoload: " + autoload_name)

	var packed_scene: PackedScene = load("res://app/main.tscn") as PackedScene
	if packed_scene == null:
		failures.append("Unable to load res://app/main.tscn")
		infrastructure_error = true
	else:
		var main_instance: Node = packed_scene.instantiate()
		if main_instance == null:
			failures.append("Unable to instantiate main scene")
			infrastructure_error = true
		else:
			get_root().add_child(main_instance)
			await process_frame
			if main_instance.name != &"Main":
				failures.append("Main scene root must be named Main")
			var app_root: ApplicationRoot = main_instance.get_node_or_null("AppRoot") as ApplicationRoot
			if app_root == null:
				failures.append("Main/AppRoot is missing")
			elif app_root.get_node_or_null("PresentationHost") == null:
				failures.append("Main/AppRoot/PresentationHost is missing")
			elif not app_root.has_method("is_booted") or not bool(app_root.call("is_booted")):
				failures.append("AppRoot did not complete minimal boot")
			elif app_root.app_state() != AppStateMachine.State.MENU:
				failures.append("AppRoot did not transition BOOT to MENU")
			elif app_root.has_active_run():
				failures.append("Minimal S1 boot fabricated an active run")
			get_root().remove_child(main_instance)
			main_instance.free()

	var completed: Array[String] = ["main_scene", "autoload_set", "minimal_boot"]
	var deferred: Array[String] = ["gameplay_ui", "combat", "shop", "effects"]
	var report: Dictionary = Support.base_report("smoke", _started_at_utc, completed, deferred)
	report["case_count"] = 5 + required_autoloads.size()
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var artifact_error: int = Support.write_json_artifact(ARTIFACT_PATH, report)
	if artifact_error != OK:
		quit(3)
		return
	if infrastructure_error:
		quit(3)
	elif failures.is_empty():
		quit(0)
	else:
		quit(2)
