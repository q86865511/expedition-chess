extends GutTest


func test_main_scene_has_fixed_node_contract() -> void:
	var scene: PackedScene = load("res://app/main.tscn") as PackedScene
	assert_not_null(scene)
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	var app_root := instance.get_node_or_null("AppRoot") as ApplicationRoot
	assert_not_null(app_root)
	if app_root == null:
		instance.free()
		return
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var repository := SaveRepository.new(FakeSaveStorage.new())
	add_child_autofree(repository)
	var router := SceneRouterService.new()
	add_child_autofree(router)
	assert_eq(
		app_root.bind_services(registry, repository, router), &"",
		"main-scene test must inject in-memory save storage before tree entry"
	)
	add_child_autofree(instance)
	assert_eq(instance.name, &"Main")
	assert_not_null(instance.get_node_or_null("AppRoot/PresentationHost"))
	assert_eq(app_root.app_state(), AppStateMachine.State.CAMP)
	assert_false(app_root.has_active_run())


func test_autoload_instances_do_not_match_implementation_classes() -> void:
	var project_text: String = FileAccess.get_file_as_string("res://project.godot")
	var pairs: Dictionary = {
		"ContentRegistry": "ContentRegistryService",
		"SaveService": "SaveRepository",
		"SettingsService": "SettingsRepository",
		"AudioService": "AudioCoordinator",
		"SceneRouter": "SceneRouterService",
	}
	for instance_name: String in pairs:
		assert_ne(instance_name, str(pairs[instance_name]))
		assert_true(project_text.contains(instance_name + "=\"*res://"))


func test_scene_router_rejects_invalid_input_without_mutation() -> void:
	var router: SceneRouterService = SceneRouterService.new()
	add_child_autofree(router)
	assert_eq(router.replace_presentation(null), SceneRouterService.ERROR_HOST_NOT_BOUND)
	var host: Control = Control.new()
	add_child_autofree(host)
	router.bind_presentation_host(host)
	assert_eq(router.replace_presentation(null), SceneRouterService.ERROR_SCENE_INVALID)
	assert_eq(host.get_child_count(), 0)


func test_settings_reject_invalid_pixel_scale() -> void:
	var repository: SettingsRepository = SettingsRepository.new()
	add_child_autofree(repository)
	assert_false(repository.set_pixel_scale(0))
	assert_eq(repository.pixel_scale(), 1)
	assert_true(repository.set_pixel_scale(2))
	assert_eq(repository.pixel_scale(), 2)
