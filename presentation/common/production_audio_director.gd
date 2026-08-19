class_name ProductionAudioDirector
extends Node

## C-3 presentation-only 音訊路由。只讀既有 AudioCueDef 與呈現輸入；
## 不持有 canonical state，也不取得任何 gameplay RNG。

const SFX_VOICE_COUNT: int = 12
const COMBAT_WINDOW_SFX_BUDGET: int = 12
const MAX_HISTORY: int = 256

const MUSIC_CUE_IDS: Array[StringName] = [
	&"audio.menu", &"audio.camp", &"audio.expedition", &"audio.combat",
	&"audio.results",
]
const SFX_CUE_IDS: Array[StringName] = [
	&"audio.ui_confirm", &"audio.ui_cancel", &"audio.ui_focus",
	&"audio.ui_error", &"audio.shop_buy", &"audio.shop_sell",
	&"audio.shop_refresh", &"audio.forge", &"audio.equip",
	&"audio.reward_select", &"audio.event_select", &"audio.combat_cast",
	&"audio.combat_melee_hit", &"audio.combat_defeat",
	&"audio.combat_shield", &"audio.combat_heal", &"audio.combat_death",
	&"audio.combat_ranged_attack", &"audio.combat_magic_hit",
	&"audio.combat_boss_warning", &"audio.combat_victory",
]

const CUE_RESOURCES: Dictionary = {
	&"audio.menu": "res://content/packs/vertical_slice/audio_cues/menu.tres",
	&"audio.camp": "res://content/packs/vertical_slice/audio_cues/camp.tres",
	&"audio.expedition": "res://content/packs/vertical_slice/audio_cues/expedition.tres",
	&"audio.combat": "res://content/packs/vertical_slice/audio_cues/combat.tres",
	&"audio.results": "res://content/packs/vertical_slice/audio_cues/results.tres",
	&"audio.ui_confirm": "res://content/packs/vertical_slice/audio_cues/ui_confirm.tres",
	&"audio.ui_cancel": "res://content/packs/vertical_slice/audio_cues/ui_cancel.tres",
	&"audio.ui_focus": "res://content/packs/vertical_slice/audio_cues/ui_focus.tres",
	&"audio.ui_error": "res://content/packs/vertical_slice/audio_cues/ui_error.tres",
	&"audio.shop_buy": "res://content/packs/vertical_slice/audio_cues/shop_buy.tres",
	&"audio.shop_sell": "res://content/packs/vertical_slice/audio_cues/shop_sell.tres",
	&"audio.shop_refresh": "res://content/packs/vertical_slice/audio_cues/shop_refresh.tres",
	&"audio.forge": "res://content/packs/vertical_slice/audio_cues/forge.tres",
	&"audio.equip": "res://content/packs/vertical_slice/audio_cues/equip.tres",
	&"audio.reward_select": "res://content/packs/vertical_slice/audio_cues/reward_select.tres",
	&"audio.event_select": "res://content/packs/vertical_slice/audio_cues/event_select.tres",
	&"audio.combat_cast": "res://content/packs/vertical_slice/audio_cues/combat_cast.tres",
	&"audio.combat_melee_hit": "res://content/packs/vertical_slice/audio_cues/combat_melee_hit.tres",
	&"audio.combat_defeat": "res://content/packs/vertical_slice/audio_cues/combat_defeat.tres",
	&"audio.combat_shield": "res://content/packs/vertical_slice/audio_cues/combat_shield.tres",
	&"audio.combat_heal": "res://content/packs/vertical_slice/audio_cues/combat_heal.tres",
	&"audio.combat_death": "res://content/packs/vertical_slice/audio_cues/combat_death.tres",
	&"audio.combat_ranged_attack": "res://content/packs/vertical_slice/audio_cues/combat_ranged_attack.tres",
	&"audio.combat_magic_hit": "res://content/packs/vertical_slice/audio_cues/combat_magic_hit.tres",
	&"audio.combat_boss_warning": "res://content/packs/vertical_slice/audio_cues/combat_boss_warning.tres",
	&"audio.combat_victory": "res://content/packs/vertical_slice/audio_cues/combat_victory.tres",
}

const ROUTE_MUSIC_CUES: Dictionary = {
	&"MENU_MAIN": &"audio.menu",
	&"SETTINGS": &"audio.menu",
	&"APP_ROUTE_FALLBACK": &"audio.menu",
	&"CAMP_WORLD": &"audio.camp",
	&"FACILITY_EXPEDITION_GATE": &"audio.camp",
	&"FACILITY_COMMANDER_HALL": &"audio.camp",
	&"COLLECTION": &"audio.camp",
	&"FACILITY_UNLOCK_WORKSHOP": &"audio.camp",
	&"FACILITY_CHALLENGE_MONUMENT": &"audio.camp",
	&"RUN_CONTAINER": &"audio.expedition",
	&"RUN_MAP": &"audio.expedition",
	&"RUN_PREPARE": &"audio.expedition",
	&"RUN_REWARD": &"audio.expedition",
	&"RUN_ROUTE_FALLBACK": &"audio.expedition",
	&"RUN_COMBAT": &"audio.combat",
	&"RESULTS": &"audio.results",
	&"RESULTS_FALLBACK": &"audio.results",
}

## Evidence 與測試共讀的語意表。實際播放仍由下方 typed intent/event mapper
## 決定，這份表用來證明 21 個採用 cue 都有具名產品觸發點。
const SFX_SEMANTIC_BINDINGS: Dictionary = {
	&"audio.ui_confirm": ["action.success", "intent.default_success", "system_menu.open"],
	&"audio.ui_cancel": ["action.*.cancel", "system_menu.dismiss", "confirmation.cancel"],
	&"audio.ui_focus": ["viewport.gui_focus_changed"],
	&"audio.ui_error": ["result.failure", "battle.summon_failure"],
	&"audio.shop_buy": ["intent.BUY_UNIT", "intent.BUY_XP"],
	&"audio.shop_sell": ["intent.SELL_UNIT"],
	&"audio.shop_refresh": ["intent.REFRESH_SHOP"],
	&"audio.forge": ["intent.FORGE_EQUIPMENT"],
	&"audio.equip": ["intent.EQUIP_ITEM", "intent.DISMANTLE_EQUIPMENT", "intent.DISMANTLE_WITH_NODE_SERVICE"],
	&"audio.reward_select": ["intent.CHOOSE_STANDARD_REWARD", "intent.RESOLVE_*_REWARD", "intent.*_OVERFLOW", "intent.REPLACE_OR_ABANDON_RELIC"],
	&"audio.event_select": ["intent.ENTER_NODE", "intent.RESOLVE_NON_COMBAT", "intent.COMMIT_OR_ACK_NODE_CHOICE", "intent.EXIT_NODE_SERVICE"],
	&"audio.combat_cast": ["battle.cast", "battle.attack.basic.magic_projectile"],
	&"audio.combat_melee_hit": ["battle.damage.physical_or_true"],
	&"audio.combat_defeat": ["battle.finished.player_loss"],
	&"audio.combat_shield": ["battle.shield"],
	&"audio.combat_heal": ["battle.heal"],
	&"audio.combat_death": ["battle.death"],
	&"audio.combat_ranged_attack": ["battle.attack.basic.ranged"],
	&"audio.combat_magic_hit": ["battle.damage.magical"],
	&"audio.combat_boss_warning": ["battle.boss_phase"],
	&"audio.combat_victory": ["battle.finished.player_win"],
}

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _route_kind: StringName = &""
var _music_cue_id: StringName = &""
var _music_bus: StringName = &""
var _playback_sequence: int = 0
var _last_focus_instance_id: int = 0
var _history: Array[Dictionary] = []
var _last_combat_report: Dictionary = {}


func _ready() -> void:
	_build_players()
	var viewport := get_viewport()
	if (
		viewport != null
		and not viewport.gui_focus_changed.is_connected(_on_gui_focus_changed)
	):
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)


func _exit_tree() -> void:
	var viewport := get_viewport()
	if (
		viewport != null
		and viewport.gui_focus_changed.is_connected(_on_gui_focus_changed)
	):
		viewport.gui_focus_changed.disconnect(_on_gui_focus_changed)


func present_route(route_kind: StringName) -> bool:
	_route_kind = route_kind
	var cue_id := music_cue_id_for_route(route_kind)
	if cue_id.is_empty():
		_record(&"route_unmapped", &"", {"route_kind": route_kind})
		return false
	if _music_cue_id == cue_id and _music_player != null and _music_player.playing:
		return true
	return _play_music(cue_id)


func present_intent_result(
	intent: RunPresentationIntent,
	result: Variant
) -> StringName:
	var cue_id := (
		cue_id_for_intent_kind(intent.kind)
		if intent != null and result_is_ok(result)
		else &"audio.ui_error"
	)
	play_cue(cue_id, {
		"source": &"intent",
		"intent_kind": intent.kind if intent != null else -1,
	})
	return cue_id


func present_action_result(action_id: StringName, result: Variant) -> StringName:
	var cue_id := cue_id_for_action(action_id, result_is_ok(result))
	play_cue(cue_id, {"source": &"action", "action_id": action_id})
	return cue_id


func present_combat_events(events: Array) -> Dictionary:
	var mappings := combat_cue_sequence(events)
	var noncritical_played := 0
	var played := 0
	for mapping: Dictionary in mappings:
		var cue_id := StringName(mapping.get("cue_id", &""))
		var critical := cue_id in [
			&"audio.combat_death", &"audio.combat_boss_warning",
			&"audio.combat_victory", &"audio.combat_defeat",
		]
		if not critical and noncritical_played >= COMBAT_WINDOW_SFX_BUDGET:
			continue
		play_cue(cue_id, {
			"source": &"combat_event",
			"event_type": mapping.get("event_type", &""),
			"event_sequence": mapping.get("event_sequence", -1),
		})
		played += 1
		if not critical:
			noncritical_played += 1
	_last_combat_report = {
		"processed_events": events.size(),
		"mapped_events": mappings.size(),
		"played_cues": played,
		"mapping_sequence": mappings.duplicate(true),
		"noncritical_budget": COMBAT_WINDOW_SFX_BUDGET,
	}
	return _last_combat_report.duplicate(true)


func play_cue(cue_id: StringName, context: Dictionary = {}) -> bool:
	if cue_id.is_empty() or cue_id not in SFX_CUE_IDS:
		_record(&"cue_invalid", cue_id, context)
		return false
	var definition := cue_definition(cue_id)
	var stream := _stream_for_definition(definition)
	if definition == null or stream == null:
		_record(&"cue_load_failed", cue_id, context)
		return false
	var player := _next_sfx_player()
	if player == null:
		_record(&"cue_player_missing", cue_id, context)
		return false
	player.stop()
	player.bus = definition.bus
	player.stream = stream
	player.play()
	_record(&"sfx", cue_id, context)
	return true


func playback_sequence() -> int:
	return _playback_sequence


func playback_report() -> Dictionary:
	return {
		"route_kind": _route_kind,
		"music_cue_id": _music_cue_id,
		"music_bus": _music_bus,
		"playback_sequence": _playback_sequence,
		"history": _history.duplicate(true),
		"last_combat_report": _last_combat_report.duplicate(true),
	}


static func music_cue_id_for_route(route_kind: StringName) -> StringName:
	return StringName(ROUTE_MUSIC_CUES.get(route_kind, &""))


static func cue_id_for_intent_kind(kind: int) -> StringName:
	match kind:
		RunPresentationIntent.Kind.REFRESH_SHOP:
			return &"audio.shop_refresh"
		RunPresentationIntent.Kind.BUY_UNIT, RunPresentationIntent.Kind.BUY_XP:
			return &"audio.shop_buy"
		RunPresentationIntent.Kind.SELL_UNIT:
			return &"audio.shop_sell"
		RunPresentationIntent.Kind.FORGE_EQUIPMENT:
			return &"audio.forge"
		RunPresentationIntent.Kind.EQUIP_ITEM, \
		RunPresentationIntent.Kind.DISMANTLE_EQUIPMENT, \
		RunPresentationIntent.Kind.DISMANTLE_WITH_NODE_SERVICE:
			return &"audio.equip"
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD, \
		RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD, \
		RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD, \
		RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD, \
		RunPresentationIntent.Kind.ADVANCE_REWARD, \
		RunPresentationIntent.Kind.RESOLVE_UNIT_OVERFLOW, \
		RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW, \
		RunPresentationIntent.Kind.REPLACE_RELIC, \
		RunPresentationIntent.Kind.ABANDON_RELIC:
			return &"audio.reward_select"
		RunPresentationIntent.Kind.GENERATE_MAP, \
		RunPresentationIntent.Kind.ENTER_NODE, \
		RunPresentationIntent.Kind.RESOLVE_NON_COMBAT, \
		RunPresentationIntent.Kind.COMMIT_NODE_CHOICE, \
		RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT, \
		RunPresentationIntent.Kind.EXIT_NODE_SERVICE:
			return &"audio.event_select"
	return &"audio.ui_confirm"


static func cue_id_for_action(action_id: StringName, ok: bool) -> StringName:
	if not ok:
		return &"audio.ui_error"
	match action_id:
		&"prepare.refresh":
			return &"audio.shop_refresh"
		&"prepare.buy", &"prepare.xp":
			return &"audio.shop_buy"
		&"prepare.sell":
			return &"audio.shop_sell"
		&"prepare.forge.confirm":
			return &"audio.forge"
		&"prepare.equip", &"prepare.dismantle", &"service.dismantle":
			return &"audio.equip"
		&"reward.confirm":
			return &"audio.reward_select"
		&"map.confirm", &"choice.confirm", &"choice.ack", &"service.exit":
			return &"audio.event_select"
	if String(action_id).ends_with(".cancel"):
		return &"audio.ui_cancel"
	return &"audio.ui_confirm"


static func result_is_ok(result: Variant) -> bool:
	if result == null:
		return false
	if result is bool:
		return bool(result)
	if result is Object:
		for property: Dictionary in (result as Object).get_property_list():
			if StringName(property.get("name", &"")) == &"ok":
				return bool((result as Object).get(&"ok"))
	return true


static func combat_cue_sequence(events: Array) -> Array[Dictionary]:
	var mappings: Array[Dictionary] = []
	for event_index: int in events.size():
		var event := events[event_index] as BattleEvent
		var cue_id := cue_id_for_combat_event(event)
		if cue_id.is_empty():
			continue
		mappings.append({
			"event_index": event_index,
			"event_sequence": event.sequence,
			"event_tick": event.tick,
			"event_type": event.type,
			"cue_id": cue_id,
		})
	return mappings


static func cue_id_for_combat_event(event: BattleEvent) -> StringName:
	if event == null:
		return &""
	match event.type:
		&"attack":
			if not event.payload is AttackEventPayload:
				return &""
			var profile := String(
				(event.payload as AttackEventPayload).presentation_profile
			)
			if profile.ends_with("ranged"):
				return &"audio.combat_ranged_attack"
			if profile.ends_with("magic_projectile"):
				return &"audio.combat_cast"
		&"cast":
			return &"audio.combat_cast"
		&"damage":
			if (
				event.payload is DamageEventPayload
				and (event.payload as DamageEventPayload).damage_type == &"magical"
			):
				return &"audio.combat_magic_hit"
			return &"audio.combat_melee_hit"
		&"shield":
			return &"audio.combat_shield"
		&"heal":
			return &"audio.combat_heal"
		&"death":
			return &"audio.combat_death"
		&"boss_phase":
			return &"audio.combat_boss_warning"
		&"summon_failure":
			return &"audio.ui_error"
		&"battle_finished":
			if (
				event.payload is BattleFinishedEventPayload
				and (event.payload as BattleFinishedEventPayload).outcome
				== &"player_win"
			):
				return &"audio.combat_victory"
			return &"audio.combat_defeat"
	return &""


static func cue_definition(cue_id: StringName) -> AudioCueDef:
	var resource_path := String(CUE_RESOURCES.get(cue_id, ""))
	return load(resource_path) as AudioCueDef if not resource_path.is_empty() else null


static func cue_manifest_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for cue_id: StringName in MUSIC_CUE_IDS + SFX_CUE_IDS:
		var definition := cue_definition(cue_id)
		var resource_path := String(CUE_RESOURCES.get(cue_id, ""))
		report.append({
			"cue_id": cue_id,
			"resource_path": resource_path,
			"resource_sha256": FileAccess.get_sha256(resource_path),
			"stream_path": definition.stream_path if definition != null else "",
			"stream_sha256": (
				FileAccess.get_sha256(definition.stream_path)
				if definition != null else ""
			),
			"bus": definition.bus if definition != null else &"",
			"loop": definition.loop if definition != null else false,
		})
	return report


static func route_music_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for route_kind: StringName in ProductionSceneCatalog.REQUIRED_ROUTES:
		report.append({
			"route_kind": route_kind,
			"cue_id": music_cue_id_for_route(route_kind),
		})
	return report


static func sfx_mapping_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for cue_id: StringName in SFX_CUE_IDS:
		report.append({
			"cue_id": cue_id,
			"triggers": (SFX_SEMANTIC_BINDINGS.get(cue_id, []) as Array).duplicate(),
		})
	return report


func _build_players() -> void:
	if _music_player != null:
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)
	for voice_index: int in SFX_VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "SfxVoice%02d" % voice_index
		add_child(player)
		_sfx_players.append(player)


func _play_music(cue_id: StringName) -> bool:
	if _music_player == null:
		_build_players()
	var definition := cue_definition(cue_id)
	var stream := _stream_for_definition(definition)
	if definition == null or stream == null or _music_player == null:
		_record(&"music_load_failed", cue_id, {"route_kind": _route_kind})
		return false
	_music_player.stop()
	_music_player.bus = definition.bus
	_music_player.stream = stream
	_music_player.play()
	_music_cue_id = cue_id
	_music_bus = definition.bus
	_record(&"music", cue_id, {"route_kind": _route_kind})
	return true


func _stream_for_definition(definition: AudioCueDef) -> AudioStream:
	if definition == null or definition.stream_path.is_empty():
		return null
	var source := load(definition.stream_path) as AudioStream
	if source == null:
		return null
	var stream := source.duplicate() as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = definition.loop
	return stream


func _next_sfx_player() -> AudioStreamPlayer:
	if _sfx_players.is_empty():
		_build_players()
	for player: AudioStreamPlayer in _sfx_players:
		if not player.playing:
			return player
	if _sfx_players.is_empty():
		return null
	var player := _sfx_players[_sfx_cursor % _sfx_players.size()]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	return player


func _record(kind: StringName, cue_id: StringName, context: Dictionary) -> void:
	_playback_sequence += 1
	var entry := {
		"sequence": _playback_sequence,
		"kind": kind,
		"cue_id": cue_id,
	}
	for key: Variant in context.keys():
		entry[key] = context[key]
	_history.append(entry)
	while _history.size() > MAX_HISTORY:
		_history.pop_front()


func _on_gui_focus_changed(control: Control) -> void:
	if control == null or not is_ancestor_of(control):
		return
	var instance_id := control.get_instance_id()
	if instance_id == _last_focus_instance_id:
		return
	_last_focus_instance_id = instance_id
	play_cue(&"audio.ui_focus", {
		"source": &"focus",
		"control": control.name,
	})
