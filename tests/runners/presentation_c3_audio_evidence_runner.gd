extends SceneTree

const DEFAULT_OUTPUT := \
	"res://specs/ui-art-refresh/evidence/c-3/audio-routing-report.json"
const SOURCE_PATHS: Array[String] = [
	"res://presentation/common/production_audio_director.gd",
	"res://presentation/screens/production_screen.gd",
	"res://presentation/screens/run_combat_screen.gd",
]


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var issues: Array[String] = []
	var output_path := _output_path()
	var output_dir := output_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_dir)
	) != OK:
		push_error("C3 evidence output directory is unavailable")
		quit(3)
		return
	var director := ProductionAudioDirector.new()
	root.add_child(director)
	await process_frame

	var runtime_music: Array[Dictionary] = []
	for route_kind: StringName in [
		&"MENU_MAIN", &"CAMP_WORLD", &"RUN_MAP", &"RUN_COMBAT", &"RESULTS",
	]:
		var played := director.present_route(route_kind)
		var playback := director.playback_report()
		runtime_music.append({
			"route_kind": route_kind,
			"expected_cue_id": ProductionAudioDirector.music_cue_id_for_route(
				route_kind
			),
			"actual_cue_id": playback.get("music_cue_id", &""),
			"bus": playback.get("music_bus", &""),
			"played": played,
		})
		if not played or playback.get("music_cue_id", &"") != \
		ProductionAudioDirector.music_cue_id_for_route(route_kind):
			issues.append("music_playback_mismatch:%s" % route_kind)

	var runtime_sfx: Array[Dictionary] = []
	for cue_id: StringName in ProductionAudioDirector.SFX_CUE_IDS:
		var played := director.play_cue(cue_id, {"source": &"evidence_probe"})
		runtime_sfx.append({"cue_id": cue_id, "played": played})
		if not played:
			issues.append("sfx_playback_failed:%s" % cue_id)

	var routes := ProductionAudioDirector.route_music_report()
	var music_ids: Dictionary = {}
	for mapping: Dictionary in routes:
		var cue_id := StringName(mapping.get("cue_id", &""))
		if cue_id.is_empty():
			issues.append("route_unmapped:%s" % mapping.get("route_kind", &""))
		music_ids[cue_id] = true
	if routes.size() != ProductionSceneCatalog.REQUIRED_ROUTES.size():
		issues.append("route_count_mismatch")
	if music_ids.size() != 5:
		issues.append("music_cue_count_mismatch")

	var sfx_mappings := ProductionAudioDirector.sfx_mapping_report()
	if sfx_mappings.size() != 21:
		issues.append("sfx_mapping_count_mismatch")
	for mapping: Dictionary in sfx_mappings:
		if (mapping.get("triggers", []) as Array).is_empty():
			issues.append("sfx_trigger_missing:%s" % mapping.get("cue_id", &""))

	var assets := ProductionAudioDirector.cue_manifest_report()
	if assets.size() != 26:
		issues.append("asset_count_mismatch")
	for asset: Dictionary in assets:
		for hash_key: String in ["resource_sha256", "stream_sha256"]:
			if String(asset.get(hash_key, "")).is_empty():
				issues.append("asset_hash_missing:%s:%s" % [
					asset.get("cue_id", &""), hash_key,
				])

	var rng_scan: Array[Dictionary] = []
	for source_path: String in SOURCE_PATHS:
		var source := FileAccess.get_file_as_string(source_path)
		var findings: Array[String] = []
		for token: String in [
			"RngService", "gameplay_stream", "randf(", "randi(", "randomize(",
		]:
			if source.contains(token):
				findings.append(token)
		rng_scan.append({"path": source_path, "findings": findings})
		if not findings.is_empty():
			issues.append("rng_reference:%s" % source_path)

	var combat_events: Array = [
		_attack_event(101, &"basic.ranged"),
		_damage_event(102, &"physical"),
		_damage_event(103, &"magical"),
		_event(104, &"heal"),
		_event(105, &"boss_phase"),
		_finished_event(106, &"player_win"),
	]
	var combat_report := director.present_combat_events(combat_events)
	var event_sequences: Array[int] = []
	for event: BattleEvent in combat_events:
		event_sequences.append(event.sequence)
	var mapped_sequences: Array[int] = []
	for mapping: Dictionary in combat_report.get("mapping_sequence", []):
		mapped_sequences.append(int(mapping.get("event_sequence", -1)))
	if mapped_sequences != event_sequences:
		issues.append("combat_event_order_changed")

	var report := {
		"schema_version": 1,
		"phase": "C-3",
		"ok": issues.is_empty(),
		"music_route_count": routes.size(),
		"music_cue_count": music_ids.size(),
		"sfx_mapping_count": sfx_mappings.size(),
		"asset_count": assets.size(),
		"route_music_mappings": routes,
		"sfx_semantic_mappings": sfx_mappings,
		"asset_manifest": assets,
		"runtime_music_probe": runtime_music,
		"runtime_sfx_probe": runtime_sfx,
		"combat_order_probe": combat_report,
		"rng_boundary_scan": rng_scan,
		"issues": issues,
	}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("C3 evidence report is not writable")
		director.queue_free()
		quit(3)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("C3_AUDIO_EVIDENCE ok=%s routes=%d music=%d sfx=%d assets=%d" % [
		report["ok"], report["music_route_count"], report["music_cue_count"],
		report["sfx_mapping_count"], report["asset_count"],
	])
	director.queue_free()
	await process_frame
	quit(0 if issues.is_empty() else 2)


func _output_path() -> String:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and not String(args[0]).is_empty():
		return String(args[0])
	return DEFAULT_OUTPUT


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
