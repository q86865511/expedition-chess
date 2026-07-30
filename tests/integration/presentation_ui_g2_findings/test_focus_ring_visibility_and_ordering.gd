extends GutTest

## G2 L3：焦點蒐集用 `visible` 而非 `is_visible_in_tree()`，整列 row 隱藏時
## 編輯器仍會進焦點環。
## G2 建議項2：`prepare.start`（開始戰鬥）誤觸代價高，退出焦點環前段。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)


func test_hidden_row_removes_its_editor_from_the_focus_ring() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"SETTINGS")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"SETTINGS",
				SettingsSnapshot.new(),
				null,
				&"zh_TW",
				Support.localized([&"settings.apply", &"settings.back"])
			)
		),
		&""
	)
	add_child_autofree(screen)
	var row := screen.get_node_or_null(
		^"Composition/SettingEditors/LocaleRow"
	) as Control
	var editor := screen.get_node_or_null(
		^"Composition/SettingEditors/LocaleRow/Locale"
	) as Control
	assert_not_null(row)
	assert_not_null(editor)
	if row == null or editor == null:
		return

	var before: Array = screen.call(&"_ordered_focus_controls")
	assert_true(before.has(editor), "a visible editor belongs to the focus ring")

	row.visible = false
	var after: Array = screen.call(&"_ordered_focus_controls")
	assert_false(
		after.has(editor),
		"an editor inside a hidden row must leave the focus ring"
	)
	assert_true(
		editor.visible,
		"the editor's own visible flag is still true; only the tree is hidden"
	)


func test_start_combat_is_the_last_action_in_the_prepare_focus_ring() -> void:
	var action_ids: Array[StringName] = [
		&"prepare.unit",
		&"prepare.refresh",
		&"prepare.buy",
		&"prepare.xp",
		&"prepare.sell",
		&"prepare.forge",
		&"prepare.forge.confirm",
		&"prepare.forge.cancel",
		&"prepare.equip",
		&"prepare.dismantle",
		&"prepare.move_board",
		&"prepare.move_bench",
		&"prepare.start",
		&"run.menu",
	]
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"RUN_PREPARE",
				RunPresentationSnapshot.new(),
				null,
				&"zh_TW",
				Support.localized(action_ids)
			)
		),
		&""
	)
	add_child_autofree(screen)

	var order := Support.focus_action_order(screen)
	assert_false(order.is_empty())
	if order.is_empty():
		return
	assert_true(
		order.has(&"prepare.start"),
		"the action must stay reachable by keyboard"
	)
	assert_eq(
		order[order.size() - 1],
		&"prepare.start",
		"start combat must not sit at the front of the tab ring"
	)
	assert_eq(
		order[0],
		&"prepare.unit",
		"the first focus stop stays the harmless party editor"
	)
	assert_true(
		order.find(&"prepare.start") > order.find(&"prepare.buy"),
		"every shop action comes before start combat"
	)
