extends GutTest

## G2 F1（fresh review `.pipeline/reviews/fix-branch-fresh-review.md`）：
## H3 的第一版把 PresentationErrorMapper 這條鏈接上了 `Label.text`，但那個 Label
## 沒有 position／size／z_index——autowrap Label 的最小寬度是 1px，不在 Container 內
## 又沒有 anchors 時 size 會被夾成 1px；預設 z_index=0 又會被 scenes/production/*.tscn
## 那個 z_index=1 的全 rect Composition 蓋住。也就是說鏈接上了、玩家還是看不到，
## finding 沒有真正封閉。
##
## 既有測試只斷言 `status_message_text().is_empty() == false`（純讀屬性），量不到這個
## 缺陷。本檔驗的是「rect 與 z 序」：狀態列有可讀的版面、在設計空間內、疊在
## Composition 與標題之上、且真的在場景樹裡可見。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)
## scenes/production/*.tscn 的設計空間（run_combat.tscn 的 design_size）。
const DESIGN_SIZE := Vector2(1280.0, 720.0)
## 「可讀」的下限：夠寬能放一句在地化訊息、夠高能放一行字。
const MIN_READABLE_SIZE := Vector2(600.0, 24.0)


func test_failed_action_status_bar_has_a_readable_rect_inside_the_design_space() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.press(self, Support.active_screen(harness), &"menu.start"))
	var camp := Support.active_screen(harness)
	assert_eq(camp.route_kind, &"CAMP_WORLD")
	var commander := camp.find_child(
		"CommanderSelector", true, false
	) as OptionButton
	assert_not_null(commander)
	if commander == null:
		return
	commander.item_selected.emit(-1)
	assert_true(Support.press(self, camp, &"camp.start"))
	assert_false(
		camp.status_message_text().is_empty(),
		"precondition: the failure must have reached the surface"
	)

	var bar := camp.status_message_control()
	assert_not_null(bar, "the status surface must be a real node on the screen")
	if bar == null:
		return
	assert_true(
		bar.is_visible_in_tree(),
		"a status surface outside the visible tree is not player feedback"
	)
	assert_gte(
		bar.size.x,
		MIN_READABLE_SIZE.x,
		"an autowrap Label without layout collapses to ~1px wide"
	)
	assert_gte(bar.size.y, MIN_READABLE_SIZE.y)
	assert_gte(bar.position.x, 0.0)
	assert_gte(bar.position.y, 0.0)
	assert_lte(
		bar.position.x + bar.size.x,
		DESIGN_SIZE.x,
		"the status bar must stay inside the 1280x720 design space"
	)
	assert_lte(bar.position.y + bar.size.y, DESIGN_SIZE.y)


func test_status_bar_draws_above_the_full_rect_composition_and_title() -> void:
	# RUN_COMBAT 是 z 序最擁擠的正式畫面：Composition 是 z_index=1 的全 rect Control，
	# 標題 Label 是 z_index=10。狀態列必須高於兩者，否則畫面上被整片蓋掉。
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_COMBAT")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"RUN_COMBAT",
				RunPresentationSnapshot.new(),
				null,
				&"zh_TW",
				Support.localized([&"combat.pause", &"run.menu"])
			)
		),
		&""
	)
	add_child_autofree(screen)

	var composition := screen.get_node_or_null("Composition") as Control
	var title := screen.get_node_or_null("Label") as Control
	var bar := screen.status_message_control()
	assert_not_null(composition)
	assert_not_null(title)
	assert_not_null(bar)
	if composition == null or title == null or bar == null:
		return
	assert_gt(
		bar.z_index,
		composition.z_index,
		"a full-rect Composition above the status bar hides every message"
	)
	assert_gt(bar.z_index, title.z_index)
	assert_true(bar.is_visible_in_tree())
	assert_gte(bar.size.x, MIN_READABLE_SIZE.x)
	assert_gte(bar.size.y, MIN_READABLE_SIZE.y)


func test_settings_draft_status_bar_does_not_overlap_the_screen_status_bar() -> void:
	# SETTINGS 有兩條狀態列（畫面動作失敗一條、draft 驗證一條）。兩條同座標
	# 等於互相蓋住，等同看不到。
	var harness: Variant = Support.boot(self)
	assert_true(Support.press(self, Support.active_screen(harness), &"menu.start"))
	assert_true(Support.press(self, Support.active_screen(harness), &"camp.settings"))
	var settings := Support.active_screen(harness)
	assert_eq(settings.route_kind, &"SETTINGS")
	var composition := (
		settings.get_node_or_null("Composition") as SettingsScreenComposition
	)
	assert_not_null(composition)
	if composition == null:
		return

	var screen_bar := settings.status_message_control()
	var draft_bar := composition.get_node_or_null(
		PresentationStatusView.NODE_NAME
	) as Label
	assert_not_null(screen_bar)
	assert_not_null(draft_bar)
	if screen_bar == null or draft_bar == null:
		return
	assert_true(draft_bar.is_visible_in_tree())
	assert_gte(draft_bar.size.x, MIN_READABLE_SIZE.x)
	assert_false(
		Rect2(screen_bar.position, screen_bar.size).intersects(
			Rect2(draft_bar.position, draft_bar.size)
		),
		"two status bars stacked on the same rect hide each other"
	)

	var draft := composition.settings_draft()
	assert_not_null(draft)
	if draft == null:
		return
	draft.locale = &"xx_YY"
	assert_eq(
		StringName(composition.replace_settings_draft(draft)),
		SettingsScreenPresenter.SETTINGS_INVALID_ENUM
	)
	assert_false(composition.status_message_text().is_empty())
	assert_eq(
		draft_bar.text,
		composition.status_message_text(),
		"the rejected draft message must live on the laid-out Label"
	)
