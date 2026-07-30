extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)

const COMBAT_SCENE_PATH := "res://scenes/production/run_combat.tscn"
const REWARD_SCENE_PATH := "res://scenes/production/run_reward.tscn"
const PHASE_ACTIONS: Dictionary = {
	PendingRewardState.Phase.CHOOSING: [
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD,
	],
	PendingRewardState.Phase.UNIT_RESOLUTION: [
		RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD,
	],
	PendingRewardState.Phase.ITEM_RESOLUTION: [
		RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD,
		RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW,
	],
	PendingRewardState.Phase.RELIC_RESOLUTION: [
		RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD,
		RunPresentationIntent.Kind.REPLACE_RELIC,
		RunPresentationIntent.Kind.ABANDON_RELIC,
	],
	PendingRewardState.Phase.READY_TO_ADVANCE: [
		RunPresentationIntent.Kind.ADVANCE_REWARD,
	],
}


func test_run_combat_and_reward_render_authoritative_reloadable_snapshots() -> void:
	if Support.require_script(
		self,
		Support.RUN_COMBAT_SCREEN_PATH,
		"AC-006 RUN_COMBAT composition"
	) == null:
		return
	if Support.require_script(
		self,
		Support.RUN_REWARD_SCREEN_PATH,
		"AC-020/072 RUN_REWARD composition"
	) == null:
		return
	var combat: Object = Support.instantiate_scene(
		self,
		COMBAT_SCENE_PATH,
		Support.RUN_COMBAT_SCREEN_PATH
	)
	if combat == null:
		return
	if not Support.require_methods(
		self,
		combat,
		[
			&"compose",
			&"enemy_rows",
			&"active_trait_ids",
			&"boss_phase_rows",
		],
		"AC-006 RUN_COMBAT intel"
	):
		return

	var combat_session: Variant = \
		Support.SpyRunPresentationSession.new()
	combat_session.current_snapshot = Support.combat_snapshot()
	var combat_port_values: Array = Support.live_intent_port(combat_session)
	assert_eq(
		combat.call(
			&"compose",
			combat_session.snapshot(),
			combat_port_values[0]
		),
		&""
	)
	var enemies: Array = combat.call(&"enemy_rows")
	assert_eq(enemies.size(), 1)
	var enemy: Variant = enemies[0]
	assert_eq(enemy.get("unit_id"), &"unit.enemy.alpha")
	assert_eq(enemy.get("logical_x"), 5)
	assert_eq(enemy.get("logical_y"), 6)
	assert_eq(enemy.get("ability_id"), &"ability.enemy.alpha")
	assert_eq(enemy.get("effect_ids"), [&"effect.mark_target"])
	assert_eq(enemy.get("target_ids"), [&"player.front"])
	assert_eq(combat.call(&"active_trait_ids"), [&"trait.enemy.arcane"])
	var phases: Array = combat.call(&"boss_phase_rows")
	assert_eq(phases.size(), 1)
	assert_eq(phases[0].get("phase_index"), 1)
	assert_eq(phases[0].get("hp_threshold_bps"), 5000)
	assert_eq(phases[0].get("effect_ids"), [&"effect.boss.enrage"])
	enemy.set("logical_x", 99)
	assert_eq(combat.call(&"enemy_rows")[0].get("logical_x"), 5)
	assert_eq(combat_session.dispatch_count, 0, "intel rendering is read-only")

	var initial: RunPresentationSnapshot = Support.reward_snapshot(
		PendingRewardState.Phase.CHOOSING
	)
	var first: Object = _reward_screen()
	var reloaded: Object = _reward_screen()
	if first == null or reloaded == null:
		return
	var first_session: Variant = \
		Support.SpyRunPresentationSession.new()
	first_session.current_snapshot = initial
	var first_port_values: Array = Support.live_intent_port(first_session)
	var reload_session: Variant = \
		Support.SpyRunPresentationSession.new()
	reload_session.current_snapshot = initial.deep_clone()
	var reload_port_values: Array = Support.live_intent_port(reload_session)
	assert_eq(first.call(&"compose", initial, first_port_values[0]), &"")
	assert_eq(
		reloaded.call(
			&"compose",
			initial.deep_clone(),
			reload_port_values[0]
		),
		&""
	)
	for accessor: StringName in [
		&"reward_identity",
		&"stage_id",
		&"phase_id",
		&"offer_ids",
	]:
		assert_eq(
			first.call(accessor),
			reloaded.call(accessor),
			"pre-claim reload must render identical authoritative reward data"
		)
	assert_eq(first.call(&"offer_ids"), ["choice.0", "choice.1", "choice.2"])

	first_session.next_snapshot = Support.post_claim_snapshot()
	var choose: RunPresentationIntent = RunPresentationIntent.new(
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD
	)
	choose.choice_id = "choice.0"
	var claimed: Variant = first.call(&"request", choose)
	assert_true(bool(claimed.get("ok")))
	assert_eq(first_session.dispatch_count, 1)
	assert_eq(
		first.call(&"phase_id"),
		PendingRewardState.Phase.UNIT_RESOLUTION
	)
	var repeated: Variant = first.call(&"request", choose)
	assert_false(bool(repeated.get("ok")))
	assert_eq(Support.error_code(repeated), &"ACTION_NOT_AVAILABLE")
	assert_eq(first_session.dispatch_count, 1, "old reward choice dispatches exactly once")

	for phase: int in PHASE_ACTIONS:
		var screen: Object = _reward_screen()
		if screen == null:
			return
		var session: Variant = \
			Support.SpyRunPresentationSession.new()
		session.current_snapshot = Support.reward_snapshot(phase)
		var port_values: Array = Support.live_intent_port(
			session,
			phase + 10
		)
		assert_eq(
			screen.call(&"compose", session.snapshot(), port_values[0]),
			&""
		)
		assert_eq(
			screen.call(&"available_action_kinds"),
			PHASE_ACTIONS[phase],
			"each persisted reward/overflow phase must restore its exact action set"
		)
		assert_eq(screen.call(&"overflow_ids"), ["overflow.item"])
		assert_true(
			screen.call(&"shop_retained_visible"),
			"elite shop remains visible until the final advance commits"
		)


func _reward_screen() -> Object:
	var screen: Object = Support.instantiate_scene(
		self,
		REWARD_SCENE_PATH,
		Support.RUN_REWARD_SCREEN_PATH
	)
	if screen == null:
		return null
	if not Support.require_methods(
		self,
		screen,
		[
			&"compose",
			&"reward_identity",
			&"stage_id",
			&"phase_id",
			&"offer_ids",
			&"available_action_kinds",
			&"overflow_ids",
			&"shop_retained_visible",
			&"request",
		],
		"AC-020/072 RUN_REWARD recovery"
	):
		return null
	return screen
