extends GutTest

const AUDIO_INVENTORY := "res://assets/production/audio/inventory.json"
const DIRECTOR_SOURCE := \
	"res://presentation/common/production_audio_director.gd"


func test_five_music_cues_cover_every_production_route() -> void:
	assert_eq(ProductionAudioDirector.MUSIC_CUE_IDS.size(), 5)
	assert_eq(
		ProductionAudioDirector.ROUTE_MUSIC_CUES.size(),
		ProductionSceneCatalog.REQUIRED_ROUTES.size()
	)
	var observed: Dictionary = {}
	for route_kind: StringName in ProductionSceneCatalog.REQUIRED_ROUTES:
		var cue_id := ProductionAudioDirector.music_cue_id_for_route(route_kind)
		assert_false(cue_id.is_empty(), "unmapped route: %s" % route_kind)
		assert_has(ProductionAudioDirector.MUSIC_CUE_IDS, cue_id)
		observed[cue_id] = true
	assert_eq(observed.size(), 5)
	assert_eq(
		ProductionAudioDirector.music_cue_id_for_route(&"RUN_MAP"),
		&"audio.expedition"
	)
	assert_eq(
		ProductionAudioDirector.music_cue_id_for_route(&"RUN_COMBAT"),
		&"audio.combat"
	)


func test_twenty_one_sfx_resources_match_adopted_inventory_sha_and_bus() -> void:
	assert_eq(ProductionAudioDirector.SFX_CUE_IDS.size(), 21)
	var inventory_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(AUDIO_INVENTORY)
	)
	assert_true(inventory_value is Dictionary)
	if not inventory_value is Dictionary:
		return
	var inventory_by_id: Dictionary = {}
	for section: String in ["music", "sfx"]:
		for entry: Dictionary in (inventory_value as Dictionary).get(section, []):
			inventory_by_id[StringName(entry.get("cue_id", &""))] = entry
	var reports := ProductionAudioDirector.cue_manifest_report()
	assert_eq(reports.size(), 26)
	var observed_paths: Dictionary = {}
	for report: Dictionary in reports:
		var cue_id := StringName(report.get("cue_id", &""))
		assert_true(inventory_by_id.has(cue_id), String(cue_id))
		if not inventory_by_id.has(cue_id):
			continue
		var inventory: Dictionary = inventory_by_id[cue_id]
		var stream_path := String(report.get("stream_path", ""))
		assert_eq(stream_path.trim_prefix("res://"), String(inventory["path"]))
		assert_eq(String(report.get("stream_sha256", "")), String(inventory["sha256"]))
		assert_eq(StringName(report.get("bus", &"")), StringName(inventory["bus"]))
		assert_eq(bool(report.get("loop", false)), bool(inventory["loop"]))
		assert_false(String(report.get("resource_sha256", "")).is_empty())
		assert_false(observed_paths.has(stream_path), "duplicate stream: %s" % stream_path)
		observed_paths[stream_path] = true


func test_intent_and_ui_semantics_reach_all_noncombat_sfx() -> void:
	assert_eq(ProductionAudioDirector.SFX_SEMANTIC_BINDINGS.size(), 21)
	for mapping: Dictionary in ProductionAudioDirector.sfx_mapping_report():
		assert_false((mapping.get("triggers", []) as Array).is_empty())
	var observed: Dictionary = {
		ProductionAudioDirector.cue_id_for_action(&"menu.confirm", true): true,
		ProductionAudioDirector.cue_id_for_action(&"menu.cancel", true): true,
		ProductionAudioDirector.cue_id_for_action(&"menu.confirm", false): true,
		&"audio.ui_focus": true,
	}
	for kind: int in [
		RunPresentationIntent.Kind.REFRESH_SHOP,
		RunPresentationIntent.Kind.BUY_UNIT,
		RunPresentationIntent.Kind.SELL_UNIT,
		RunPresentationIntent.Kind.FORGE_EQUIPMENT,
		RunPresentationIntent.Kind.EQUIP_ITEM,
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD,
		RunPresentationIntent.Kind.ENTER_NODE,
	]:
		observed[ProductionAudioDirector.cue_id_for_intent_kind(kind)] = true
	for cue_id: StringName in [
		&"audio.ui_confirm", &"audio.ui_cancel", &"audio.ui_focus",
		&"audio.ui_error", &"audio.shop_buy", &"audio.shop_sell",
		&"audio.shop_refresh", &"audio.forge", &"audio.equip",
		&"audio.reward_select", &"audio.event_select",
	]:
		assert_true(observed.has(cue_id), "unwired semantic: %s" % cue_id)
	assert_eq(
		ProductionAudioDirector.cue_id_for_action(&"prepare.refresh", true),
		&"audio.shop_refresh"
	)
	assert_eq(
		ProductionAudioDirector.cue_id_for_action(&"prepare.buy", true),
		&"audio.shop_buy"
	)
	assert_eq(
		ProductionAudioDirector.cue_id_for_action(&"prepare.forge.confirm", true),
		&"audio.forge"
	)
	assert_eq(
		ProductionAudioDirector.cue_id_for_action(&"reward.confirm", true),
		&"audio.reward_select"
	)


func test_combat_event_audio_mapping_preserves_input_order() -> void:
	var events: Array = [
		_attack_event(11, &"basic.ranged"),
		_attack_event(12, &"basic.magic_projectile"),
		_event(13, &"cast"),
		_damage_event(14, &"physical"),
		_damage_event(15, &"magical"),
		_event(16, &"shield"),
		_event(17, &"heal"),
		_event(18, &"death"),
		_event(19, &"boss_phase"),
		_event(20, &"summon_failure"),
		_finished_event(21, &"player_win"),
		_finished_event(22, &"player_loss"),
	]
	var original_sequences: Array[int] = []
	for event: BattleEvent in events:
		original_sequences.append(event.sequence)
	var mappings := ProductionAudioDirector.combat_cue_sequence(events)
	var mapped_sequences: Array[int] = []
	var cues: Array[StringName] = []
	for mapping: Dictionary in mappings:
		mapped_sequences.append(int(mapping["event_sequence"]))
		cues.append(StringName(mapping["cue_id"]))
	assert_eq(mapped_sequences, original_sequences)
	assert_eq(cues, [
		&"audio.combat_ranged_attack",
		&"audio.combat_cast",
		&"audio.combat_cast",
		&"audio.combat_melee_hit",
		&"audio.combat_magic_hit",
		&"audio.combat_shield",
		&"audio.combat_heal",
		&"audio.combat_death",
		&"audio.combat_boss_warning",
		&"audio.ui_error",
		&"audio.combat_victory",
		&"audio.combat_defeat",
	])
	var sequences_after: Array[int] = []
	for event: BattleEvent in events:
		sequences_after.append(event.sequence)
	assert_eq(sequences_after, original_sequences, "audio must not mutate events")


func test_combat_sampling_scans_every_event_and_keeps_terminal_cues() -> void:
	var director := ProductionAudioDirector.new()
	add_child_autofree(director)
	var events: Array = []
	for sequence: int in range(1, 18):
		events.append(_damage_event(sequence, &"physical"))
	events.append(_finished_event(18, &"player_win"))
	var report := director.present_combat_events(events)
	assert_eq(int(report.get("processed_events", -1)), 18)
	assert_eq(int(report.get("mapped_events", -1)), 18)
	assert_eq(
		int(report.get("played_cues", -1)),
		ProductionAudioDirector.COMBAT_WINDOW_SFX_BUDGET + 1
	)
	var mapping_sequence: Array = report.get("mapping_sequence", [])
	assert_eq(int((mapping_sequence[-1] as Dictionary)["event_sequence"]), 18)
	var history: Array = director.playback_report().get("history", [])
	assert_eq(
		StringName((history[-1] as Dictionary).get("cue_id", &"")),
		&"audio.combat_victory"
	)


func test_production_screen_route_music_and_audio_sources_are_rng_free() -> void:
	var screen := ProductionScreen.new()
	screen.route_kind = &"RUN_COMBAT"
	var composition := RunCombatScreen.new()
	composition.name = "Composition"
	screen.add_child(composition)
	add_child_autofree(screen)
	var report := screen.audio_playback_report()
	assert_eq(StringName(report.get("route_kind", &"")), &"RUN_COMBAT")
	assert_eq(StringName(report.get("music_cue_id", &"")), &"audio.combat")
	assert_eq(StringName(report.get("music_bus", &"")), &"Music")
	assert_eq(
		screen.find_children("*", "ProductionAudioDirector", true, false).size(),
		1,
		"only the route root may own an audio director"
	)
	for path: String in [
		DIRECTOR_SOURCE,
		"res://presentation/screens/production_screen.gd",
		"res://presentation/screens/run_combat_screen.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_false(source.contains("RngService"), path)
		assert_false(source.contains("gameplay_stream"), path)
		assert_false(source.contains("randf("), path)
		assert_false(source.contains("randi("), path)
		assert_false(source.contains("randomize("), path)


func _event(sequence: int, type: StringName) -> BattleEvent:
	var event := BattleEvent.new()
	event.tick = sequence
	event.sequence = sequence
	event.type = type
	event.payload = BattleEventPayload.new()
	return event


func _attack_event(sequence: int, profile: StringName) -> BattleEvent:
	var event := _event(sequence, &"attack")
	var payload := AttackEventPayload.new()
	payload.presentation_profile = profile
	event.payload = payload
	return event


func _damage_event(sequence: int, damage_type: StringName) -> BattleEvent:
	var event := _event(sequence, &"damage")
	var payload := DamageEventPayload.new()
	payload.damage_type = damage_type
	event.payload = payload
	return event


func _finished_event(sequence: int, outcome: StringName) -> BattleEvent:
	var event := _event(sequence, &"battle_finished")
	var payload := BattleFinishedEventPayload.new()
	payload.outcome = outcome
	event.payload = payload
	return event
