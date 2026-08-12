extends GutTest

## in-run-hud T10：備戰期焦點圖與畫面動作清單的覆蓋契約。
##
## KeyboardFocusGraph 是焦點順序的唯一權威（keyboard_focus_graph.gd:85-91）。
## RUN_PREPARE 的商店／鍛造／裝備／移動動作以前沒有登記在焦點圖裡，順序因此落到
## ProductionScreen 的補掃迴圈（production_screen.gd:2618-2623）決定——鍵盤玩家仍能
## Tab 到，但順序不由權威決定，且「新增動作忘了登記」不會有任何測試變紅。
##
## 這個測試就是那個守門員：它不鏡像一份寫死清單，而是直接向 ProductionScreen 問
## RUN_PREPARE 實際會渲染哪些 action，再要求焦點圖恰好覆蓋同一組 id。

func test_run_prepare_focus_graph_covers_exactly_the_screen_actions() -> void:
	var screen := ProductionScreen.new()
	screen.route_kind = &"RUN_PREPARE"
	var required: Array[StringName] = []
	required.assign(screen.call(&"_required_action_ids"))
	screen.free()
	assert_false(required.is_empty(), "RUN_PREPARE 必須有可渲染的動作")

	var order: Array[StringName] = []
	order.assign(KeyboardFocusGraph.new().focus_order(&"RUN_PREPARE", 100, []))
	for action_id: StringName in required:
		assert_true(
			order.has(action_id),
			"%s 是畫面會渲染的動作，焦點圖必須登記它" % action_id
		)
	for action_id: StringName in order:
		assert_true(
			required.has(action_id),
			"%s 不在 RUN_PREPARE 的動作清單裡，焦點圖不該登記它" % action_id
		)
	assert_eq(
		order.size(),
		required.size(),
		"焦點圖不得重複登記同一個動作"
	)


func test_run_prepare_high_cost_action_stays_at_the_end_of_the_button_run() -> void:
	var graph := KeyboardFocusGraph.new()
	var order: Array[StringName] = []
	order.assign(graph.focus_order(&"RUN_PREPARE", 100, []))
	var deferred: Array[StringName] = graph.deferred_actions(&"RUN_PREPARE")

	assert_eq(deferred, [&"prepare.start"] as Array[StringName])
	assert_eq(
		order[order.size() - 1],
		&"prepare.start",
		"誤觸代價高的開戰動作必須留在按鈕段最後（G2 建議項2／F9）"
	)


func test_blocked_prepare_actions_are_dropped_from_the_order() -> void:
	var blocked: Array[StringName] = [&"prepare.buy", &"prepare.forge.confirm"]
	var order: Array[StringName] = []
	order.assign(
		KeyboardFocusGraph.new().focus_order(&"RUN_PREPARE", 150, blocked)
	)

	assert_false(order.has(&"prepare.buy"), "停用中的動作不得留在焦點環")
	assert_false(order.has(&"prepare.forge.confirm"))
	assert_true(order.has(&"prepare.sell"), "其餘動作不受影響")
