extends GutTest

## in-run-hud T10：局內 ESC 系統選單的內嵌設定必須能經 AppRoot 注入的 typed
## SettingsApplicationPort 就地提交（REQ-UX-006／spec §10.7）。
##
## 這裡守住的縫是「composition root 有沒有在畫面組裝時呼叫
## ProductionScreen.bind_system_menu_settings()」：port 與 committed snapshot 只能
## 由 AppRoot 注入，畫面自己不得接 SettingsService 或存檔。沒有注入時內嵌套用鍵
## 是 disabled（system_menu_overlay.gd:_build_settings），玩家在局內改不了設定。
##
## 第二個測試守住新鮮度：ProductionScreen 是 route-scoped 物件，settings 套用後的
## route 重載會換一個新實例——新畫面必須拿到「當下的」port 與剛提交的 snapshot，
## 不是上一輪的舊物件。
##
## 使用 r14 accessibility joint 的 boot harness（真 SaveRepository／SettingsRepository／
## AudioCoordinator ＋ 正式 main.tscn composition），不另建第二套 AppRoot fixture。

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)
const SETTINGS_BUTTON: String = "SystemMenuSettingsButton"
const APPLY_BUTTON: String = "SettingsApplyButton"


func test_in_run_system_menu_applies_settings_through_the_injected_port() -> void:
	var harness := Support.boot(self)
	assert_eq(harness.settings_bind_error, &"")
	assert_eq(harness.boot_error, &"")
	if not harness.settings_bind_error.is_empty() or not harness.boot_error.is_empty():
		return
	var driven := Support.drive_to_run_prepare(harness)
	assert_true(
		bool(driven.get("ok", false)),
		"production intent flow must reach RUN_PREPARE: %s"
		% String(driven.get("error", &""))
	)
	if not bool(driven.get("ok", false)):
		return
	await wait_process_frames(2)

	var screen := Support.active_screen(harness)
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.get(&"_system_menu_settings_port"),
		harness.root.settings_application_port(),
		"AppRoot 必須在畫面組裝時注入它自己的 typed port"
	)
	assert_true(screen.open_system_menu(), "局內 route 必須能開啟系統選單")
	var overlay := screen.system_menu_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	var settings_button := overlay.find_child(SETTINGS_BUTTON, true, false) as Button
	assert_not_null(settings_button, "系統選單必須有設定入口")
	if settings_button == null:
		return
	settings_button.pressed.emit()
	assert_eq(screen.system_menu_state(), &"SETTINGS_EMBEDDED")
	var composition := overlay.settings_composition()
	assert_not_null(composition)
	if composition == null:
		return
	var apply_button := overlay.find_child(APPLY_BUTTON, true, false) as Button
	assert_not_null(apply_button)
	if apply_button == null:
		return
	assert_false(
		apply_button.disabled,
		"注入 port 之後內嵌套用鍵才可按（未注入時 overlay 會停用它）"
	)

	var candidate := Support.candidate(125, &"tritanopia")
	assert_eq(
		composition.replace_settings_draft(candidate),
		&"",
		"draft 必須通過既有欄位驗證"
	)
	# GDScript lambda 以值捕捉區域變數，因此用容器收訊號結果。
	var emitted: Array[SettingsApplicationResult] = []
	overlay.settings_applied.connect(
		func(result: SettingsApplicationResult) -> void:
			emitted.append(result)
	)
	apply_button.pressed.emit()
	await wait_process_frames(2)

	assert_eq(emitted.size(), 1, "內嵌套用必須經 port 回傳 typed 結果")
	if emitted.size() != 1:
		return
	var applied := emitted[0]
	assert_not_null(applied)
	if applied == null:
		return
	assert_true(applied.ok, "局內套用必須成功提交")
	assert_null(applied.error)
	assert_true(
		Support.snapshots_equal(
			harness.settings_repository.current_snapshot(),
			candidate
		),
		"真正的 SettingsRepository 必須持有這次提交的 committed clone"
	)


func test_route_reload_rebinds_the_current_port_and_committed_snapshot() -> void:
	var harness := Support.boot(self)
	assert_eq(harness.settings_bind_error, &"")
	assert_eq(harness.boot_error, &"")
	if not harness.settings_bind_error.is_empty() or not harness.boot_error.is_empty():
		return
	var driven := Support.drive_to_run_prepare(harness)
	assert_true(
		bool(driven.get("ok", false)),
		"production intent flow must reach RUN_PREPARE: %s"
		% String(driven.get("error", &""))
	)
	if not bool(driven.get("ok", false)):
		return
	await wait_process_frames(2)
	var old_screen_id := Support.active_screen(harness).get_instance_id()

	# 先經 AppRoot 的 port 提交一組新設定，再讓 route 重載（換一個 ProductionScreen
	# 實例）——新畫面必須拿到當下的 port 與剛提交的 snapshot。
	var candidate := Support.candidate(125, &"deuteranopia")
	var applied: SettingsApplicationResult = \
		harness.root.settings_application_port().apply(candidate)
	assert_true(applied.ok)
	if not applied.ok:
		return
	await wait_process_frames(2)
	assert_eq(
		Support.reload_current_route(harness),
		&"",
		"same-state route reload 必須仍走 SceneRouter"
	)
	await wait_process_frames(3)

	var reloaded := Support.active_screen(harness)
	assert_not_null(reloaded)
	if reloaded == null:
		return
	assert_ne(
		reloaded.get_instance_id(),
		old_screen_id,
		"證據必須觀察到真正的畫面替換"
	)
	assert_eq(
		reloaded.get(&"_system_menu_settings_port"),
		harness.root.settings_application_port(),
		"重載後的畫面必須握著 AppRoot 當下的 port，不是上一輪的實例"
	)
	assert_true(
		Support.snapshots_equal(
			reloaded.get(&"_system_menu_settings_snapshot") as SettingsSnapshot,
			candidate
		),
		"重載後注入的必須是剛提交的 committed snapshot，不是 boot 當時的值"
	)

	assert_true(reloaded.open_system_menu())
	var overlay := reloaded.system_menu_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	var settings_button := overlay.find_child(SETTINGS_BUTTON, true, false) as Button
	assert_not_null(settings_button)
	if settings_button == null:
		return
	settings_button.pressed.emit()
	var composition := overlay.settings_composition()
	assert_not_null(composition)
	if composition == null:
		return
	var draft := composition.settings_draft()
	assert_not_null(draft)
	if draft == null:
		return
	assert_eq(
		draft.ui_scale_percent,
		candidate.ui_scale_percent,
		"內嵌 editor 的起始值必須是新的 committed 設定"
	)
	assert_eq(draft.color_vision_mode, candidate.color_vision_mode)

	var emitted: Array[SettingsApplicationResult] = []
	overlay.settings_applied.connect(
		func(result: SettingsApplicationResult) -> void:
			emitted.append(result)
	)
	var next_candidate := Support.candidate(150, &"tritanopia")
	assert_eq(composition.replace_settings_draft(next_candidate), &"")
	var apply_button := overlay.find_child(APPLY_BUTTON, true, false) as Button
	assert_not_null(apply_button)
	if apply_button == null:
		return
	apply_button.pressed.emit()
	await wait_process_frames(2)
	assert_eq(emitted.size(), 1, "重載後的畫面必須經 port 回傳 typed 結果")
	if emitted.size() != 1:
		return
	var second := emitted[0]
	assert_true(second.ok, "重載後的畫面必須能用新 port 再提交一次")
	assert_true(
		Support.snapshots_equal(
			harness.settings_repository.current_snapshot(),
			next_candidate
		)
	)
