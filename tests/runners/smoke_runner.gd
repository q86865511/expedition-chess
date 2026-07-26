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
			# Smoke must never touch the real user:// save, especially when multiple
			# worktrees execute concurrently. Inject the same production services with
			# an in-memory storage before AppRoot enters the scene tree.
			var registry := ContentRegistryService.new()
			var repository := SaveRepository.new(FakeSaveStorage.new())
			var router := SceneRouterService.new()
			get_root().add_child(registry)
			get_root().add_child(repository)
			get_root().add_child(router)
			var app_root: ApplicationRoot = (
				main_instance.get_node_or_null("AppRoot") as ApplicationRoot
			)
			if app_root == null:
				failures.append("Main/AppRoot is missing")
				infrastructure_error = true
			else:
				var bind_error: StringName = app_root.bind_services(
					registry, repository, router
				)
				if not bind_error.is_empty():
					failures.append("AppRoot service binding failed: " + String(bind_error))
					infrastructure_error = true
			get_root().add_child(main_instance)
			await process_frame
			if main_instance.name != &"Main":
				failures.append("Main scene root must be named Main")
			if app_root == null:
				pass
			elif app_root.get_node_or_null("PresentationHost") == null:
				failures.append("Main/AppRoot/PresentationHost is missing")
			elif not app_root.has_method("is_booted") or not bool(app_root.call("is_booted")):
				failures.append("AppRoot did not complete minimal boot")
			# S5 T11 (specs/meta-progression/design.md §4.4): boot now branches on
			# SaveRepository.load() -- an active run resumes straight into RUN, and
			# "otherwise CAMP". A smoke run has no committed save, so the expected
			# resting state is CAMP (BOOT -> MENU -> CAMP), not the S1-era MENU.
			elif app_root.app_state() != AppStateMachine.State.CAMP:
				failures.append("AppRoot did not transition BOOT to CAMP")
			elif app_root.has_active_run():
				failures.append("Minimal boot fabricated an active run")
			get_root().remove_child(main_instance)
			main_instance.free()
			get_root().remove_child(router)
			router.free()
			get_root().remove_child(repository)
			repository.free()
			get_root().remove_child(registry)
			registry.free()

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
