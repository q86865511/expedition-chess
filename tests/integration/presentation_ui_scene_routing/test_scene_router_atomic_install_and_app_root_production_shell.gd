extends GutTest

const LifecycleSupport = preload(
	"res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd"
)
const ROOT_PATH := "res://app/app_root.gd"


class FaultScreen:
	extends ProductionScreen

	func bind(context: StagedScreenContext) -> StringName:
		return &"TEST_SCREEN_BIND_FAULT"


class FaultCatalog:
	extends ProductionSceneCatalog

	func instantiate(route_kind: StringName) -> ProductionScreen:
		if route_kind == &"SETTINGS":
			var screen := FaultScreen.new()
			screen.route_kind = route_kind
			return screen
		return super.instantiate(route_kind)


func test_scene_router_stages_binds_and_preserves_live_scene_on_fault() -> void:
	var router := SceneRouterService.new()
	add_child_autofree(router)
	var host := Control.new()
	add_child_autofree(host)
	router.bind_presentation_host(host)
	assert_true(
		router.has_method(&"bind_production_catalog"),
		"T07 router must accept the production scene catalog"
	)
	assert_true(
		router.has_method(&"install_production"),
		"T07 router must stage/bind before replacing the live scene"
	)
	if not router.has_method(&"bind_production_catalog") \
		or not router.has_method(&"install_production"):
		return

	var catalog_error: StringName = router.call(
		&"bind_production_catalog", ProductionSceneCatalog.new()
	)
	assert_eq(catalog_error, &"")
	var menu_error: StringName = router.call(
		&"install_production",
		&"MENU_MAIN",
		StagedScreenContext.new(&"MENU_MAIN", null)
	)
	assert_eq(menu_error, &"")
	assert_eq(host.get_child_count(), 1)
	var menu_screen := host.get_child(0) as ProductionScreen
	assert_not_null(menu_screen)
	assert_eq(menu_screen.route_kind, &"MENU_MAIN")
	var live_identity := menu_screen.get_instance_id()

	assert_eq(router.call(&"bind_production_catalog", FaultCatalog.new()), &"")
	var fault_error: StringName = router.call(
		&"install_production",
		&"SETTINGS",
		StagedScreenContext.new(&"SETTINGS", null)
	)
	assert_eq(fault_error, &"TEST_SCREEN_BIND_FAULT")
	assert_eq(host.get_child_count(), 1, "bind fault must keep the old live child")
	assert_eq(
		host.get_child(0).get_instance_id(),
		live_identity,
		"bind fault must not destroy or replace the old live child"
	)
	assert_eq((host.get_child(0) as ProductionScreen).route_kind, &"MENU_MAIN")

	var legacy_error := router.replace_presentation(null)
	assert_eq(legacy_error, SceneRouterService.ERROR_SCENE_INVALID)
	assert_eq(
		host.get_child(0).get_instance_id(),
		live_identity,
		"invalid legacy candidate must also preserve the live scene"
	)


func test_application_root_boot_and_camp_use_production_shell_without_dev_casts() -> void:
	var harness := LifecycleSupport.boot(self, FakeSaveStorage.new())
	assert_eq(harness.boot_error, &"")
	assert_true(harness.root.is_booted())
	assert_eq(harness.host.get_child_count(), 1, "successful boot must install MENU_MAIN")
	if harness.host.get_child_count() != 1:
		return
	var menu_screen := harness.host.get_child(0) as ProductionScreen
	assert_not_null(menu_screen, "boot screen must use the production contract")
	if menu_screen == null:
		return
	assert_eq(menu_screen.route_kind, &"MENU_MAIN")

	var camp_result := harness.root.open_camp()
	assert_true(camp_result.ok, "menu Start/Camp action must remain available")
	assert_eq(harness.host.get_child_count(), 1)
	if harness.host.get_child_count() != 1:
		return
	var camp_screen := harness.host.get_child(0) as ProductionScreen
	assert_not_null(camp_screen, "camp route must use the production contract")
	if camp_screen == null:
		return
	assert_eq(camp_screen.route_kind, &"CAMP_WORLD")

	var root_source := FileAccess.get_file_as_string(ROOT_PATH)
	for forbidden_token: String in [
		"const CAMP_SCENE_PATH",
		"const RUN_SCENE_PATH",
		"const RESULTS_SCENE_PATH",
		"as CampScreen",
		"as RunScreen",
		"as ResultsScreen",
	]:
		assert_false(
			root_source.contains(forbidden_token),
			"ApplicationRoot production routing must not depend on `%s`" % forbidden_token
		)
