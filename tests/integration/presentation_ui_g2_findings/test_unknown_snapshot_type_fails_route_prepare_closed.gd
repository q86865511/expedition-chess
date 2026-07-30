extends GutTest

## G2 F10（fresh review `.pipeline/reviews/fix-branch-fresh-review.md`）：
## L5 幫兩個 screen context 加了 `snapshot_type_error`，但全庫沒有任何 production
## 呼叫端讀它——`_compose_production_child` 仍拿到 null 往下傳，於是「新增一種
## snapshot 型別忘了加 clone 分支」跟「本來就不需要 snapshot」在畫面上仍然無從分辨，
## 「fail-closed」實際只達成「可查詢的診斷」。
##
## 現在 `_prepare_route()` 是那個讀者：任一 context 帶著具名 type error 就
## fail-closed，不把半截畫面裝上去。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)


func test_route_prepare_rejects_a_snapshot_type_no_context_can_clone() -> void:
	var harness: Variant = Support.boot(self)
	var root := harness.root as ApplicationRoot
	var before := Support.active_screen(harness)
	assert_not_null(before)
	if before == null:
		return
	assert_eq(before.route_kind, &"MENU_MAIN")

	# RefCounted 但不是四種已知 snapshot 之一：正是「新增型別忘了加分支」的形狀。
	var prepared: Dictionary = root.call(
		&"_prepare_route",
		AppStateMachine.State.MENU,
		&"MENU_MAIN",
		RefCounted.new()
	)
	assert_false(
		bool(prepared.get("ok", false)),
		"an unclonable snapshot must not produce a mountable route"
	)
	var code := String(prepared.get("error", &""))
	assert_true(
		code.begins_with("STAGED_SCREEN_CONTEXT_SNAPSHOT_TYPE_UNKNOWN"),
		"the failure must carry the named diagnostic, not a generic code: %s" % code
	)
	assert_eq(
		Support.active_screen(harness),
		before,
		"a rejected prepare must leave the live screen untouched"
	)
	assert_not_null(Support.lease_registry(root).active_lease())


func test_both_contexts_still_record_the_named_diagnostic() -> void:
	var staged := StagedScreenContext.new(&"MENU_MAIN", RefCounted.new())
	assert_true(
		String(staged.snapshot_type_error).begins_with(
			"STAGED_SCREEN_CONTEXT_SNAPSHOT_TYPE_UNKNOWN"
		)
	)
	assert_null(staged.snapshot)
	var live := ProductionLiveScreenContext.new(&"MENU_MAIN", RefCounted.new())
	assert_true(
		String(live.snapshot_type_error).begins_with(
			"PRODUCTION_LIVE_SCREEN_CONTEXT_SNAPSHOT_TYPE_UNKNOWN"
		)
	)
	assert_null(live.snapshot)
