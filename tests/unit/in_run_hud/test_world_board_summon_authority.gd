extends GutTest

## IRH-REQ-007 的最後一塊：戰鬥途中被召喚出來的實體也要能上世界層棋盤。
##
## 契約：spawn 事件只帶身分、陣營、origin 與格位，血條／魔力上限與 sprite 都不在
## transcript 裡。權威只有兩處——pinned `SummonedUnitRuleSnapshot`（domain 已算好星級
## 縮放）與已採用的 production 視覺清單。因此本 suite 守住三件事：
##   1. 產出的 renderer DTO 與 domain 直查的模板逐欄位一致，呈現層不得自行換算；
##   2. 缺模板／缺 sprite／模板不合法一律 fail closed（回 null，維持 unrenderable），
##      不得虛構 sprite 或上限；
##   3. 進出都是 clone：改動傳入的模板或拿到的 DTO 都影響不了之後的讀取。

const Frames = preload("res://assets/production/units/slice_player_00.tres")
## 視覺清單只認 production unit id；domain 合成內容用的是 unit.monster_01（無 sprite），
## 兩者剛好構成「有模板有視覺」與「有模板缺視覺」兩個案例。
const RENDERABLE_UNIT_ID: StringName = &"unit.slice_monster_00"
const SUMMONED_UNIT_ID: StringName = &"unit.summoned"
const ALLY_ID: StringName = &"u_0000000000000001"
const SUMMON_ID: StringName = &"s_0000000000000001"
const OTHER_SUMMON_ID: StringName = &"s_0000000000000002"


# ---------------------------------------------------------------------------
# 權威本身：與 domain 直查逐欄位一致
# ---------------------------------------------------------------------------

func test_spawned_unit_matches_pinned_domain_template_field_by_field() -> void:
	var template := _domain_summoned_template()
	assert_not_null(template, "BattleRulesSnapshotBuilder 應由 pinned catalog 產出召喚模板")
	if template == null:
		return
	# 只換掛 unit_id 到有 sprite 的 production 單位上；其餘欄位仍是 domain 算好的值。
	var renderable := template.deep_clone()
	renderable.unit_id = RENDERABLE_UNIT_ID
	var authority := _authority([renderable])

	var unit := authority.try_spawned_unit(
		RENDERABLE_UNIT_ID, SUMMON_ID, Vector2i(3, 4)
	)
	assert_not_null(unit)
	if unit == null:
		return
	assert_eq(unit.presentation_instance_id, SUMMON_ID, "身分只能來自 spawn 事件")
	assert_eq(unit.logical_cell, Vector2i(3, 4), "格位只能來自 spawn payload")
	assert_eq(unit.health, template.health, "初始血量＝模板血量，不得另算")
	assert_eq(unit.max_health, template.health, "血條上限＝模板血量")
	assert_eq(unit.mana, template.start_mana)
	assert_eq(unit.max_mana, maxi(1, template.max_mana))
	assert_eq(
		unit.animation,
		StringName("idle_s_star%d" % template.star),
		"召喚模板固定 1 星，動畫必須跟著模板星級"
	)
	assert_eq(
		unit.sprite_frames,
		ProductionUnitVisualCatalog.new().try_sprite_frames(RENDERABLE_UNIT_ID),
		"sprite 只能來自已採用的視覺清單"
	)
	assert_true(unit.is_valid(), "產出必須是 renderer 可直接用的合法 DTO")


func test_missing_template_visual_or_invalid_stats_fail_closed() -> void:
	var template := _domain_summoned_template()
	assert_not_null(template)
	if template == null:
		return
	var renderable := template.deep_clone()
	renderable.unit_id = RENDERABLE_UNIT_ID

	# 1) 完全沒有模板：畫面不知道血條上限，不能畫。
	assert_null(
		_authority([]).try_spawned_unit(
			RENDERABLE_UNIT_ID, SUMMON_ID, Vector2i(3, 4)
		),
		"沒有 pinned 模板就沒有 max-stat 權威"
	)
	# 2) 有模板但視覺清單沒有這個 unit_id：不得挑一張 sprite 頂替。
	assert_null(
		_authority([template.deep_clone()]).try_spawned_unit(
			template.unit_id, SUMMON_ID, Vector2i(3, 4)
		),
		"缺 sprite 不得虛構視覺"
	)
	# 3) 空 unit_id 與未登記的 unit_id。
	assert_null(_authority([renderable]).try_spawned_unit(&"", SUMMON_ID, Vector2i(3, 4)))
	assert_null(
		_authority([renderable]).try_spawned_unit(
			&"unit.not_a_template", SUMMON_ID, Vector2i(3, 4)
		)
	)
	# 4) 模板不合法（血量 0）：不夾擠成 1，直接沒有權威。
	var broken := renderable.deep_clone()
	broken.health = 0
	assert_null(
		_authority([broken]).try_spawned_unit(
			RENDERABLE_UNIT_ID, SUMMON_ID, Vector2i(3, 4)
		),
		"不合法模板不得被夾擠成看起來正常的單位"
	)
	# 5) 格位或身分不合法時同樣不產出半成品 DTO。
	assert_null(
		_authority([renderable]).try_spawned_unit(
			RENDERABLE_UNIT_ID, SUMMON_ID, Vector2i(8, 0)
		)
	)
	assert_null(
		_authority([renderable]).try_spawned_unit(
			RENDERABLE_UNIT_ID, &"", Vector2i(3, 4)
		)
	)


func test_authority_is_clone_isolated_from_pinned_input_and_callers() -> void:
	var template := _domain_summoned_template()
	assert_not_null(template)
	if template == null:
		return
	var renderable := template.deep_clone()
	renderable.unit_id = RENDERABLE_UNIT_ID
	var pinned_health := renderable.health
	var authority := _authority([renderable])

	# 傳入端之後怎麼改都影響不了已收下的權威。
	renderable.health = 1
	renderable.max_mana = 1
	renderable.unit_id = &"unit.mutated"
	var unit := authority.try_spawned_unit(
		RENDERABLE_UNIT_ID, SUMMON_ID, Vector2i(3, 4)
	)
	assert_not_null(unit)
	if unit == null:
		return
	assert_eq(unit.max_health, pinned_health)

	# 拿到的 DTO 也是 clone：改它不影響下一次讀取。
	unit.health = 1
	unit.max_health = 1
	unit.logical_cell = Vector2i(0, 0)
	var again := authority.try_spawned_unit(
		RENDERABLE_UNIT_ID, OTHER_SUMMON_ID, Vector2i(5, 5)
	)
	assert_not_null(again)
	if again == null:
		return
	assert_eq(again.max_health, pinned_health)
	assert_eq(again.logical_cell, Vector2i(5, 5))
	assert_eq(again.presentation_instance_id, OTHER_SUMMON_ID)


# ---------------------------------------------------------------------------
# 播放投影：有權威就畫得出來，沒權威維持既有 unrenderable 生命週期
# ---------------------------------------------------------------------------

func test_projection_renders_summon_from_authority_and_keeps_after_values() -> void:
	var template := _domain_summoned_template()
	assert_not_null(template)
	if template == null:
		return
	var renderable := template.deep_clone()
	renderable.unit_id = RENDERABLE_UNIT_ID
	var projection := CombatWorldEventProjection.new(_authority([renderable]))
	assert_eq(projection.compose(_setup_snapshot()), &"")

	var events: Array = [
		_spawn(SUMMON_ID, RENDERABLE_UNIT_ID, &"player", &"summon", Vector2i(2, 3)),
		# 缺模板的召喚仍舊只能追蹤為不可渲染，且不得回滾同一 window 的其他更新。
		_spawn(OTHER_SUMMON_ID, template.unit_id, &"enemy", &"summon", Vector2i(6, 3)),
		_mana(SUMMON_ID, 5),
		_move(SUMMON_ID, Vector2i(2, 3), Vector2i(3, 3)),
		_damage(SUMMON_ID, 7),
		_damage(ALLY_ID, 63),
	]
	for event: BattleEvent in events:
		assert_true(BattleEventCodecV1.new().encode(event).ok, String(event.type))

	assert_eq(projection.apply_window(events), &"")
	var presented := projection.snapshot_clone()
	var summoned := _unit(presented, SUMMON_ID)
	assert_not_null(summoned, "有 pinned 權威的召喚實體必須畫得出來")
	if summoned == null:
		return
	assert_eq(summoned.logical_cell, Vector2i(3, 3), "移動只複製 domain 目的地")
	assert_eq(summoned.health, 7, "血量只複製 health_after")
	assert_eq(summoned.max_health, template.health, "血條上限只能來自 pinned 模板")
	assert_eq(summoned.mana, 5)
	assert_true(presented.is_valid())
	assert_null(
		_unit(presented, OTHER_SUMMON_ID),
		"缺視覺權威的召喚不得被虛構出來"
	)
	assert_eq(_unit(presented, ALLY_ID).health, 63)

	# 死亡後同樣退場；之後的遲到事件是 no-op，不是整段 window 失敗。
	assert_eq(
		projection.apply_window([
			_death(SUMMON_ID, &"summon", Vector2i(3, 3)),
			_damage(ALLY_ID, 40),
		]),
		&""
	)
	assert_null(_unit(projection.snapshot_clone(), SUMMON_ID))
	assert_eq(projection.apply_window([_mana(SUMMON_ID, 9)]), &"")
	assert_eq(_unit(projection.snapshot_clone(), ALLY_ID).health, 40)

	# 同一個 id 再被召喚一次：完全由 pinned 權威與 payload 格位重建，不留舊值。
	assert_eq(
		projection.apply_window([
			_spawn(SUMMON_ID, RENDERABLE_UNIT_ID, &"player", &"summon", Vector2i(4, 4)),
		]),
		&""
	)
	var respawned := _unit(projection.snapshot_clone(), SUMMON_ID)
	assert_not_null(respawned)
	if respawned != null:
		assert_eq(respawned.logical_cell, Vector2i(4, 4))
		assert_eq(respawned.health, template.health)
	assert_true(projection.snapshot_clone().is_valid(), "重生不得留下重複身分")


# ---------------------------------------------------------------------------
# 供給鏈：session 只轉發 pinned 模板，且是 clone
# ---------------------------------------------------------------------------

func test_session_forwards_pinned_summoned_templates_clone_only() -> void:
	var save_root := SaveRootFixture.create_valid_root()
	var inputs := _inputs_with_summon_template()
	var setup := BattleSimulationFixture.build_setup(inputs, save_root.run.run_seed)
	assert_not_null(setup, "帶召喚模板的 setup 必須通過 domain 驗證")
	if setup == null:
		return
	save_root.run.run_phase = RunState.RunPhase.COMBAT
	save_root.run.resolution_state = CombatPendingResolutionState.new(setup)
	var run_session := RunSession.new(save_root.profile, save_root.run, null)
	var controller := RunController.new(run_session, null)
	var no_effects: Array[StringName] = []
	var session := RunPresentationSession.new(
		controller,
		RunCommandFactory.new(null, null),
		null,
		no_effects,
		CombatCoordinator.new(controller)
	)

	var forwarded := session.combat_summoned_unit_templates()
	var pinned := inputs.battle_rules.summoned_unit_templates
	assert_eq(forwarded.size(), pinned.size())
	assert_eq(forwarded.size(), 1)
	if forwarded.is_empty():
		return
	assert_eq(forwarded[0].unit_id, pinned[0].unit_id)
	assert_eq(forwarded[0].star, pinned[0].star)
	assert_eq(forwarded[0].health, pinned[0].health)
	assert_eq(forwarded[0].start_mana, pinned[0].start_mana)
	assert_eq(forwarded[0].max_mana, pinned[0].max_mana)
	assert_eq(forwarded[0].attack, pinned[0].attack)

	# clone-out：改動回傳值不影響 canonical，也不影響之後的讀取。
	forwarded[0].health = 1
	forwarded[0].unit_id = &"unit.mutated"
	assert_eq(session.combat_summoned_unit_templates()[0].health, pinned[0].health)
	assert_eq(session.combat_summoned_unit_templates()[0].unit_id, pinned[0].unit_id)

	# 權威接得起來：轉發的模板直接餵給世界層權威即可畫出召喚實體。
	var authority := WorldBoardSummonAuthority.new(
		session.combat_summoned_unit_templates()
	)
	assert_null(
		authority.try_spawned_unit(SUMMONED_UNIT_ID, SUMMON_ID, Vector2i(2, 2)),
		"fixture 的召喚單位不在視覺清單內，必須 fail closed"
	)

	# 供給缺席（沒有 controller）時回空陣列，而不是 crash 或假資料。
	assert_eq(RunPresentationSession.new().combat_summoned_unit_templates().size(), 0)
	session.release()
	assert_eq(session.combat_summoned_unit_templates().size(), 0)


# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------

func _authority(
	templates: Array
) -> WorldBoardSummonAuthority:
	var typed: Array[SummonedUnitRuleSnapshot] = []
	for template: SummonedUnitRuleSnapshot in templates:
		typed.append(template)
	return WorldBoardSummonAuthority.new(typed)


## domain 直查：以合成內容裝進 registry，經 BattleRuleCatalogBuilder pin 住世代，
## 再由 BattleRulesSnapshotBuilder 產出召喚閉包（星級縮放已在 domain 算完）。
func _domain_summoned_template() -> SummonedUnitRuleSnapshot:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(
		SyntheticContentFixture.build_valid(),
		"fixture.summon",
		[&"pack.core"]
	)
	assert_true(installed.ok)
	if not installed.ok:
		return null
	var required: Array[StringName] = [
		&"encounter.boss_0",
		&"equipment.c0_c0",
		&"unit.player_00",
	]
	var built := BattleRuleCatalogBuilder.new().build(
		registry, installed.handle.manifest_digest, required
	)
	assert_true(built.ok)
	if not built.ok:
		return null
	var inputs := BattleSetupInputs.new()
	inputs.manifest_digest = StringName(installed.handle.manifest_digest)
	inputs.encounter_snapshot = EncounterPreviewSnapshot.new()
	inputs.encounter_snapshot.manifest_digest = inputs.manifest_digest
	var summoner := UnitBattleSnapshot.new()
	summoner.ability_id = OptionalStringNameValue.of(&"ability.summon")
	inputs.encounter_snapshot.enemy_units.append(summoner)
	var closure := BattleRulesSnapshotBuilder.new().build(
		built.catalog, inputs, 1, &"boss"
	)
	assert_true(closure.ok)
	if not closure.ok or closure.snapshot.summoned_unit_templates.is_empty():
		return null
	return closure.snapshot.summoned_unit_templates[0]


## 在既有 setup fixture 上加一條 summon 規則與對應模板；effect_id 必須維持字典序，
## 故 effect.summoner 插在 effect.test 之前。
func _inputs_with_summon_template() -> BattleSetupInputs:
	var inputs := BattleSimulationFixture.create_inputs()
	var operation := BattleOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"summon"
	operation.unit_id = OptionalStringNameValue.of(SUMMONED_UNIT_ID)
	operation.count = 1
	operation.max_active_per_source = 1
	operation.placement_rule = &"adjacent"
	var effect := BattleEffectRuleSnapshot.new()
	effect.effect_id = &"effect.summoner"
	effect.trigger = &"cast"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	effect.battle_operations.append(operation)
	inputs.battle_rules.effect_rules.insert(0, effect)
	var template := SummonedUnitRuleSnapshot.new()
	template.unit_id = SUMMONED_UNIT_ID
	template.star = 1
	template.health = 45
	template.attack = 7
	template.armor = 0
	template.magic_resist = 0
	template.attack_speed_milli = 900
	template.attack_range_cells = 1
	template.start_mana = 3
	template.max_mana = 30
	template.move_speed_milli = 1000
	template.ai_profile = &"frontline"
	template.basic_attack_profile = &"melee"
	inputs.battle_rules.summoned_unit_templates.append(template)
	return inputs


func _setup_snapshot() -> WorldBoardSnapshot:
	var result := WorldBoardSnapshot.new()
	var ally := WorldBoardUnitSnapshot.new()
	ally.presentation_instance_id = ALLY_ID
	ally.logical_cell = Vector2i(1, 2)
	ally.sprite_frames = Frames
	ally.animation = &"idle_s_star1"
	ally.health = 100
	ally.max_health = 100
	ally.mana = 10
	ally.max_mana = 100
	result.append_unit(ally)
	return result


func _spawn(
	instance_id: StringName,
	unit_id: StringName,
	side: StringName,
	origin: StringName,
	cell: Vector2i
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"spawn"
	event.target_instance_ids.assign([instance_id])
	var payload := SpawnEventPayload.new()
	payload.unit_id = unit_id
	payload.side = side
	payload.origin = origin
	payload.logical_x = cell.x
	payload.logical_y = cell.y
	event.payload = payload
	return event


func _damage(target_id: StringName, health_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"damage"
	event.target_instance_ids.assign([target_id])
	var payload := DamageEventPayload.new()
	payload.damage_type = &"physical"
	payload.health_after = health_after
	event.payload = payload
	return event


func _mana(target_id: StringName, mana_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"mana"
	event.target_instance_ids.assign([target_id])
	var payload := ManaEventPayload.new()
	payload.reason = &"effect"
	payload.mana_after = mana_after
	event.payload = payload
	return event


func _move(
	source_id: StringName,
	from_cell: Vector2i,
	to_cell: Vector2i
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"move"
	event.source_instance_id = OptionalStringNameValue.of(source_id)
	var payload := MoveEventPayload.new()
	payload.from_x = from_cell.x
	payload.from_y = from_cell.y
	payload.to_x = to_cell.x
	payload.to_y = to_cell.y
	event.payload = payload
	return event


func _death(
	source_id: StringName,
	origin: StringName,
	cell: Vector2i
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"death"
	event.source_instance_id = OptionalStringNameValue.of(source_id)
	var payload := DeathEventPayload.new()
	payload.origin = origin
	payload.logical_x = cell.x
	payload.logical_y = cell.y
	event.payload = payload
	return event


func _unit(
	snapshot: WorldBoardSnapshot,
	presentation_id: StringName
) -> WorldBoardUnitSnapshot:
	if snapshot == null:
		return null
	for unit: WorldBoardUnitSnapshot in snapshot.units:
		if unit.presentation_instance_id == presentation_id:
			return unit
	return null
