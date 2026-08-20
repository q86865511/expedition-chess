extends GutTest

const Frames = preload("res://assets/production/units/slice_player_00.tres")
const ALLY_ID: StringName = &"u_0000000000000001"
const ENEMY_ID: StringName = &"u_0000000000000002"
const ENVIRONMENT_MANIFEST := \
	"res://assets/production/environment/inventory.json"
const PROVENANCE_PATH := \
	"res://assets/production/provenance/run_combat_environment.json"
const COMBAT_BACKGROUND := \
	"res://assets/production/environment/run_combat.png"
const COMBAT_VFX := "res://assets/production/shared/combat_vfx.png"
const STATUS_DAMAGE := "res://assets/production/shared/status_damage.png"


func test_skill_hit_status_use_both_adopted_atlases_on_world_projection() -> void:
	var renderer := _renderer()
	var events: Array = [
		_event(&"cast", 1),
		_event(&"attack", 2),
		_event(&"damage", 3),
		_event(&"status", 4),
	]
	var report := renderer.present_events(events, _snapshot(), 96)
	assert_eq(int(report.get("processed", -1)), 4)
	assert_eq(int(report.get("spawned_vfx", -1)), 4)
	assert_eq(int(report.get("spawned_damage_labels", -1)), 1)
	assert_eq(renderer.processed_sequences(), [1, 2, 3, 4])
	var atlas_ids: Dictionary = {}
	var effect_kinds: Dictionary = {}
	for child: Node in renderer.get_children():
		if child.has_meta(&"atlas_id"):
			atlas_ids[StringName(child.get_meta(&"atlas_id"))] = true
		if child.has_meta(&"effect_kind"):
			effect_kinds[StringName(child.get_meta(&"effect_kind"))] = true
	assert_true(atlas_ids.has(&"combat_vfx"))
	assert_true(atlas_ids.has(&"status_damage"))
	for kind: StringName in [&"skill", &"attack", &"hit", &"status"]:
		assert_true(effect_kinds.has(kind), "missing visual kind: %s" % kind)


func test_damage_density_samples_labels_without_filtering_event_order() -> void:
	var events: Array = []
	for sequence: int in range(1, 31):
		events.append(_event(&"damage", sequence))
	var expected_sequences: Array[int] = []
	for sequence: int in range(1, 31):
		expected_sequences.append(sequence)
	var expected_labels := {
		0: 0,
		24: 24,
		96: 30,
	}
	for budget: int in [0, 24, 96]:
		var renderer := _renderer()
		var report := renderer.present_events(events, _snapshot(), budget)
		assert_eq(
			int(report.get("spawned_damage_labels", -1)),
			int(expected_labels[budget]),
			"budget %d" % budget
		)
		assert_eq(
			renderer.processed_sequences(),
			expected_sequences,
			"density must not filter or reorder canonical events"
		)


func test_visual_clock_fades_and_moves_only_when_explicitly_advanced() -> void:
	var renderer := _renderer()
	renderer.present_events([_event(&"damage", 7)], _snapshot(), 96)
	var label := _first_track(renderer, &"floating_damage") as Label
	assert_not_null(label)
	if label == null:
		return
	var initial_position := label.position
	var initial_alpha := label.modulate.a
	# A paused playback frame makes no renderer call, so visual state is inert.
	assert_eq(label.position, initial_position)
	assert_eq(label.modulate.a, initial_alpha)
	renderer.advance_playback(240.0)
	assert_lt(label.position.y, initial_position.y)
	assert_lt(label.modulate.a, initial_alpha)
	var after_x1 := float(label.get_meta(&"age_ms", -1.0))
	renderer.advance_playback(240.0 * 2.0)
	var after_x2 := float(label.get_meta(&"age_ms", -1.0))
	assert_eq(after_x2 - after_x1, 480.0)
	renderer.advance_playback(120.0 * 4.0)
	assert_eq(float(label.get_meta(&"age_ms", -1.0)) - after_x2, 480.0)


func test_world_surface_owns_effects_and_route_clear_removes_background() -> void:
	var surface := ProductionWorldSurface.new()
	add_child_autofree(surface)
	var background := load(COMBAT_BACKGROUND) as Texture2D
	assert_not_null(background)
	var board := surface.board_renderer()
	board.set_background_texture(background)
	assert_eq(board.background_texture(), background)
	var effects := surface.combat_effects_renderer()
	assert_eq(effects.get_parent(), board)
	assert_eq(effects.z_index, ExpeditionLayoutMetrics.COMBAT_EFFECT_LAYER)
	surface.clear_board_snapshot()
	assert_null(board.background_texture())


func test_combat_environment_inventory_provenance_and_sha_match_disk() -> void:
	var manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ENVIRONMENT_MANIFEST)
	)
	assert_true(manifest is Dictionary)
	if not manifest is Dictionary:
		return
	var combat_entry: Dictionary = {}
	for value: Variant in (manifest as Dictionary).get("visuals", []):
		if (
			value is Dictionary
			and String((value as Dictionary).get("visual_id", ""))
			== "environment.run_combat"
		):
			combat_entry = (value as Dictionary).duplicate(true)
	assert_false(combat_entry.is_empty())
	assert_eq(String(combat_entry.get("status", "")), "adopted")
	assert_eq(int(combat_entry.get("width", 0)), 1672)
	assert_eq(int(combat_entry.get("height", 0)), 941)
	assert_eq(
		FileAccess.get_sha256(COMBAT_BACKGROUND),
		String(combat_entry.get("sha256", ""))
	)
	var provenance: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PROVENANCE_PATH)
	)
	assert_true(provenance is Dictionary)
	if provenance is Dictionary:
		assert_eq(
			String((provenance as Dictionary).get("asset_id", "")),
			"environment.run_combat"
		)
		assert_eq(
			int(((provenance as Dictionary).get("selection", {}) as Dictionary).get(
				"candidate_count", 0
			)),
			2
		)
		assert_true(bool(
			((provenance as Dictionary).get("selection", {}) as Dictionary).get(
				"pending_user_visual_approval", false
			)
		))
	assert_eq(
		FileAccess.get_sha256(COMBAT_VFX),
		"1d9752d3e38b804952d82b7656fef619aeabfcf658b6a84035b38661f42bf0c6"
	)
	assert_eq(
		FileAccess.get_sha256(STATUS_DAMAGE),
		"e5f66139c3fb82ccfe1fcf6698e8cf12641f2cca0ac0a9a682dc7b60f3ed65fb"
	)


func test_visual_scripts_do_not_touch_gameplay_rng_service() -> void:
	for path: String in [
		"res://presentation/viewport/combat_world_effects_renderer.gd",
		"res://presentation/screens/run_combat_screen.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_false(source.contains("RngService"), path)
		assert_false(source.contains("gameplay_stream"), path)


func _renderer() -> CombatWorldEffectsRenderer:
	var renderer := CombatWorldEffectsRenderer.new()
	add_child_autofree(renderer)
	return renderer


func _snapshot() -> WorldBoardSnapshot:
	var snapshot := WorldBoardSnapshot.new()
	for entry: Dictionary in [
		{"id": ALLY_ID, "cell": Vector2i(2, 2)},
		{"id": ENEMY_ID, "cell": Vector2i(5, 5)},
	]:
		var unit := WorldBoardUnitSnapshot.new()
		unit.presentation_instance_id = entry["id"]
		unit.logical_cell = entry["cell"]
		unit.sprite_frames = Frames
		unit.animation = &"idle_s_star1"
		unit.health = 100
		unit.max_health = 100
		unit.mana = 0
		unit.max_mana = 100
		snapshot.append_unit(unit)
	return snapshot


func _event(type: StringName, sequence: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.tick = sequence
	event.sequence = sequence
	event.type = type
	event.source_instance_id = OptionalStringNameValue.of(ALLY_ID)
	event.target_instance_ids = [ENEMY_ID]
	match type:
		&"cast":
			var payload := CastEventPayload.new()
			payload.ability_id = &"ability.fixture"
			payload.action = &"started"
			payload.resolve_tick = sequence + 1
			event.payload = payload
		&"damage":
			var payload := DamageEventPayload.new()
			payload.damage_type = &"physical"
			payload.raw_amount = 12
			payload.post_resistance_amount = 10
			payload.health_damage = 10
			payload.health_after = 90
			event.payload = payload
		&"status":
			var payload := StatusEventPayload.new()
			payload.status_id = &"status.fixture"
			payload.action = &"applied"
			payload.stacks = 1
			payload.remaining_ticks = 3
			event.payload = payload
		_:
			event.payload = BattleEventPayload.new()
	return event


func _first_track(
	renderer: CombatWorldEffectsRenderer,
	kind: StringName
) -> CanvasItem:
	for child: Node in renderer.get_children():
		if StringName(child.get_meta(&"combat_effect_track", &"")) == kind:
			return child as CanvasItem
	return null
