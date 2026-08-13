extends RefCounted

## G2 審查修補（H3／M1／M2／L3／L4＋兩項建議）的共用夾具。
## 一律走正式 composition root（ApplicationRoot＋SceneRouterService），
## 只有需要注入 route commit 失敗時才換上 FailingCommitRouter。

const LifecycleSupport = preload(
	"res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd"
)


## commit_prepared 可被單次武裝成失敗；其餘行為與正式 router 相同。
class FailingCommitRouter:
	extends SceneRouterService

	var fail_next_commit: bool = false
	var commit_failures: int = 0
	var steal_activation: ScreenActivationCapability
	var steal_registry: LiveScreenLeaseRegistry

	func commit_prepared(prepared: PreparedProductionRoute) -> StringName:
		if fail_next_commit:
			fail_next_commit = false
			commit_failures += 1
			return &"SCENE_BIND_FAILED"
		var error := super(prepared)
		# activate-null 分支的可測化：場景已經 commit，但 activation 在
		# activate_prepared 之前就被消費掉了。
		if steal_activation != null and steal_registry != null:
			steal_registry.activate_prepared(steal_activation)
			steal_activation = null
		return error


static func boot(
	test: GutTest,
	router: SceneRouterService = null
) -> Variant:
	var harness := LifecycleSupport.BootHarness.new()
	harness.registry = ContentRegistryService.new()
	test.add_child_autofree(harness.registry)
	harness.repository = SaveRepository.new(FakeSaveStorage.new())
	test.add_child_autofree(harness.repository)
	harness.router = router if router != null else SceneRouterService.new()
	test.add_child_autofree(harness.router)
	harness.root = ApplicationRoot.new()
	harness.root.name = "AppRoot"
	harness.host = Control.new()
	harness.host.name = "PresentationHost"
	harness.root.add_child(harness.host)
	harness.root.boot_failed.connect(func(error_code: StringName) -> void:
		harness.boot_error = error_code
	)
	test.assert_eq(
		harness.root.bind_services(
			harness.registry,
			harness.repository,
			harness.router
		),
		&""
	)
	test.add_child_autofree(harness.root)
	return harness


static func active_screen(harness: Variant) -> ProductionScreen:
	if harness == null or harness.host == null \
		or harness.host.get_child_count() != 1:
		return null
	return harness.host.get_child(0) as ProductionScreen


static func button(
	screen: ProductionScreen,
	action_id: StringName
) -> Button:
	if screen == null:
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var candidate := node as Button
		if (
			candidate != null
			and candidate.has_meta(&"action_id")
			and StringName(candidate.get_meta(&"action_id")) == action_id
		):
			return candidate
	return null


static func press(
	test: GutTest,
	screen: ProductionScreen,
	action_id: StringName
) -> bool:
	if (
		action_id == &"run.menu"
		and screen != null
		and screen.system_menu_state() == &"CLOSED"
	):
		var menu_button := screen.system_menu_button()
		test.assert_not_null(
			menu_button,
			"live run routes expose SystemMenuButton instead of resident run.menu"
		)
		if menu_button == null:
			return false
		menu_button.pressed.emit()
	var control := button(screen, action_id)
	test.assert_not_null(control, "missing Button for %s" % String(action_id))
	if control == null:
		return false
	control.pressed.emit()
	return true


## MENU→CAMP→（選遠征）→RUN。回傳 RUN 的 live screen。
static func enter_run(test: GutTest, harness: Variant) -> ProductionScreen:
	if not press(test, active_screen(harness), &"menu.start"):
		return null
	var camp := active_screen(harness)
	var composition := camp.get_node_or_null("Composition") as CampWorldScreen
	test.assert_not_null(composition)
	if composition == null:
		return null
	var view_model := (harness.root as ApplicationRoot).try_camp_view_model()
	var commanders: Array[StringName] = (
		view_model.commander_hall_unlocked_commander_ids()
	)
	test.assert_false(commanders.is_empty())
	if commanders.is_empty():
		return null
	test.assert_eq(
		StringName(composition.select_expedition(commanders[0], 0)),
		&""
	)
	if not press(test, camp, &"camp.start"):
		return null
	test.assert_eq(
		(harness.root as ApplicationRoot).app_state(),
		AppStateMachine.State.RUN
	)
	return active_screen(harness)


static func lease_registry(root: ApplicationRoot) -> LiveScreenLeaseRegistry:
	return root.get(&"_live_lease_registry") as LiveScreenLeaseRegistry


static func focus_action_order(
	screen: ProductionScreen
) -> Array[StringName]:
	var result: Array[StringName] = []
	var controls: Array = screen.call(&"_ordered_focus_controls")
	for control: Variant in controls:
		var candidate := control as Button
		if candidate != null and candidate.has_meta(&"action_id"):
			result.append(StringName(candidate.get_meta(&"action_id")))
	return result


static func localized(action_ids: Array[StringName]) -> Dictionary:
	var values: Dictionary = {}
	for action_id: StringName in action_ids:
		values[action_id] = String(action_id)
	return values
