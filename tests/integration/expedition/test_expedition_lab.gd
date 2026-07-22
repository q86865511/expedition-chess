extends GutTest

func test_lab_scene_exposes_route_status_combat_and_reward_controls() -> void:
	var packed := load("res://scenes/dev/expedition_lab/expedition_lab.tscn") as PackedScene
	assert_not_null(packed)
	if packed == null: return
	var screen := packed.instantiate() as ExpeditionLabScreen
	add_child_autofree(screen)
	await get_tree().process_frame
	assert_not_null(screen.get_node("%ActLabel"))
	assert_not_null(screen.get_node("%NodeLabel"))
	assert_not_null(screen.get_node("%EnterButton"))
	assert_not_null(screen.get_node("%WinButton"))
	assert_not_null(screen.get_node("%BossLossButton"))
	assert_not_null(screen.get_node("%RewardButton"))

func test_lab_session_demonstrates_income_boss_retry_and_commit_before_reward() -> void:
	var session := ExpeditionLabSession.new()
	var entered := session.enter_node()
	assert_eq(entered.phase, &"prepare")
	assert_eq(entered.gold, 15)
	var boss_loss := session.settle_demo(false, true)
	assert_eq(boss_loss.phase, &"prepare")
	assert_eq(boss_loss.expedition_hp, 80)
	assert_eq(boss_loss.gold, 15)
	var win := session.settle_demo(true, false)
	assert_eq(win.phase, &"reward")
	assert_true(win.reward_ready)
	var rewarded := session.choose_gold_reward()
	assert_eq(rewarded.phase, &"map")
	assert_eq(rewarded.gold, 18)
	assert_false(rewarded.reward_ready)
