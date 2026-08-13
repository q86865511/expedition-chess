class_name CombatWorldEventProjection
extends RefCounted

## Presentation-only reducer for the already committed combat transcript.
##
## The setup snapshot and every event payload are authoritative clones. This
## class only copies explicit `*_after` values and move destinations; it never
## derives damage, healing, mana, pathing, or any other domain rule.

const INITIAL_SNAPSHOT_INVALID: StringName = \
	&"COMBAT_WORLD_INITIAL_SNAPSHOT_INVALID"
const EVENT_INVALID: StringName = &"COMBAT_WORLD_EVENT_INVALID"
const EVENT_TARGET_UNKNOWN: StringName = &"COMBAT_WORLD_EVENT_TARGET_UNKNOWN"

var _snapshot: WorldBoardSnapshot
var _setup_entity_ids: Dictionary = {}
var _unrenderable_spawned_ids: Dictionary = {}
var _dead_entity_ids: Dictionary = {}
var _codec := BattleEventCodecV1.new()
## Pinned visual/max-stat authority for entities that only the transcript
## introduces. Absent authority is the pre-existing contract: every spawn then
## stays unrenderable, which is why this dependency is optional.
var _summon_authority: WorldBoardSummonAuthority


func _init(p_summon_authority: WorldBoardSummonAuthority = null) -> void:
	_summon_authority = p_summon_authority


func compose(initial_snapshot: WorldBoardSnapshot) -> StringName:
	if initial_snapshot == null or not initial_snapshot.is_valid():
		_snapshot = null
		_setup_entity_ids.clear()
		_unrenderable_spawned_ids.clear()
		_dead_entity_ids.clear()
		return INITIAL_SNAPSHOT_INVALID
	_snapshot = initial_snapshot.deep_clone()
	_setup_entity_ids.clear()
	_unrenderable_spawned_ids.clear()
	_dead_entity_ids.clear()
	for unit: WorldBoardUnitSnapshot in _snapshot.units:
		_setup_entity_ids[unit.presentation_instance_id] = true
	return &""


## Applies one presented event window atomically. If any supported event is
## malformed or names an unknown entity, the entire window is rejected and the
## previously presented snapshot is kept. Spawned entities absent from setup are
## rendered from the injected pinned summon authority; without such authority
## (or for a unit id it does not cover) they still lack complete visual/max-stat
## data, so their stable ids are tracked clone-only and their follow-up events
## are ignored without rolling back unrelated, renderable entity updates in the
## same window.
func apply_window(events: Array) -> StringName:
	if _snapshot == null or not _snapshot.is_valid():
		return INITIAL_SNAPSHOT_INVALID
	var draft := _snapshot.deep_clone()
	var units_by_id: Dictionary = {}
	for unit: WorldBoardUnitSnapshot in draft.units:
		units_by_id[unit.presentation_instance_id] = unit
	var unrenderable_spawned_ids := _unrenderable_spawned_ids.duplicate()
	var dead_entity_ids := _dead_entity_ids.duplicate()
	for value: Variant in events:
		if not value is BattleEvent:
			return EVENT_INVALID
		var event := value as BattleEvent
		# BattleEventCodecV1 is the single source of truth for every codec-v1
		# identity and payload schema, including events this projection ignores.
		# Do not mirror those domain-owned validation rules here.
		if not _codec.encode(event).ok:
			return EVENT_INVALID
		var event_error := _apply_event(
			draft,
			units_by_id,
			unrenderable_spawned_ids,
			dead_entity_ids,
			event
		)
		if not event_error.is_empty():
			return event_error
	if not draft.is_valid():
		return EVENT_INVALID
	_snapshot = draft
	_unrenderable_spawned_ids = unrenderable_spawned_ids
	_dead_entity_ids = dead_entity_ids
	return &""


func snapshot_clone() -> WorldBoardSnapshot:
	return _snapshot.deep_clone() if _snapshot != null else null


func _apply_event(
	draft: WorldBoardSnapshot,
	units_by_id: Dictionary,
	unrenderable_spawned_ids: Dictionary,
	dead_entity_ids: Dictionary,
	event: BattleEvent
) -> StringName:
	match event.type:
		&"spawn":
			return _apply_spawn(
				draft,
				units_by_id,
				unrenderable_spawned_ids,
				dead_entity_ids,
				event
			)
		&"damage":
			if _targets_nonrenderable(
				unrenderable_spawned_ids,
				dead_entity_ids,
				event
			):
				return &""
			var damage_target := _single_target(units_by_id, event)
			if damage_target == null:
				return EVENT_TARGET_UNKNOWN
			var damage := event.payload as DamageEventPayload
			damage_target.health = damage.health_after
		&"heal":
			if _targets_nonrenderable(
				unrenderable_spawned_ids,
				dead_entity_ids,
				event
			):
				return &""
			var heal_target := _single_target(units_by_id, event)
			if heal_target == null:
				return EVENT_TARGET_UNKNOWN
			var heal := event.payload as HealEventPayload
			heal_target.health = heal.health_after
		&"mana":
			if _targets_nonrenderable(
				unrenderable_spawned_ids,
				dead_entity_ids,
				event
			):
				return &""
			var mana_target := _single_target(units_by_id, event)
			if mana_target == null:
				return EVENT_TARGET_UNKNOWN
			var mana := event.payload as ManaEventPayload
			mana_target.mana = mana.mana_after
		&"move":
			return _apply_move(
				units_by_id,
				unrenderable_spawned_ids,
				dead_entity_ids,
				event
			)
		&"death":
			return _apply_death(
				draft,
				units_by_id,
				unrenderable_spawned_ids,
				dead_entity_ids,
				event
			)
		_:
			# Other codec-v1 events remain authoritative transcript data, but
			# none of them carries one of the explicit world fields owned here.
			pass
	return &""


func _apply_spawn(
	draft: WorldBoardSnapshot,
	units_by_id: Dictionary,
	unrenderable_spawned_ids: Dictionary,
	dead_entity_ids: Dictionary,
	event: BattleEvent
) -> StringName:
	var spawned_id: StringName = event.target_instance_ids[0]
	# Setup owns the complete sprite and max-stat data of the entities it placed.
	# Repeated setup spawns are therefore explicit no-ops, including after that
	# setup entity died: the summon authority covers summoned templates only, so
	# presentation still cannot fabricate a resurrection snapshot.
	if _setup_entity_ids.has(spawned_id):
		return &""
	var spawned := _try_authoritative_unit(spawned_id, event)
	if spawned == null:
		# No pinned template or no authored sprite for this unit id. A repeated
		# non-setup id starts a new unrenderable lifecycle, matching the original
		# spawn strategy while retaining no domain-mutable state.
		dead_entity_ids.erase(spawned_id)
		unrenderable_spawned_ids[spawned_id] = true
		return &""
	# A respawned id re-enters entirely from pinned authority and the committed
	# destination cell, so the previous body is replaced rather than duplicated.
	var previous := units_by_id.get(spawned_id) as WorldBoardUnitSnapshot
	if previous != null:
		draft.units.erase(previous)
	unrenderable_spawned_ids.erase(spawned_id)
	dead_entity_ids.erase(spawned_id)
	draft.append_unit(spawned)
	units_by_id[spawned_id] = draft.units[draft.units.size() - 1]
	return &""


## The renderer body for a spawned entity, or null when nothing pinned covers it.
## Cell and unit id come from the committed payload; sprite and maximums come
## from the injected authority. Nothing is derived here.
func _try_authoritative_unit(
	spawned_id: StringName,
	event: BattleEvent
) -> WorldBoardUnitSnapshot:
	if _summon_authority == null:
		return null
	var payload := event.payload as SpawnEventPayload
	if payload == null:
		return null
	return _summon_authority.try_spawned_unit(
		payload.unit_id,
		spawned_id,
		Vector2i(payload.logical_x, payload.logical_y)
	)


func _apply_move(
	units_by_id: Dictionary,
	unrenderable_spawned_ids: Dictionary,
	dead_entity_ids: Dictionary,
	event: BattleEvent
) -> StringName:
	var source_id := event.source_instance_id.value
	if (
		unrenderable_spawned_ids.has(source_id)
		or dead_entity_ids.has(source_id)
	):
		return &""
	var source := units_by_id.get(source_id) as WorldBoardUnitSnapshot
	if source == null:
		return EVENT_TARGET_UNKNOWN
	var move := event.payload as MoveEventPayload
	var from_cell := Vector2i(move.from_x, move.from_y)
	var to_cell := Vector2i(move.to_x, move.to_y)
	# Codec validation owns the destination footprint. This remaining check is
	# presentation-state consistency: a window cannot move from a cell that the
	# previously presented authoritative windows did not establish.
	if source.logical_cell != from_cell:
		return EVENT_INVALID
	source.logical_cell = to_cell
	return &""


func _apply_death(
	draft: WorldBoardSnapshot,
	units_by_id: Dictionary,
	unrenderable_spawned_ids: Dictionary,
	dead_entity_ids: Dictionary,
	event: BattleEvent
) -> StringName:
	var source_id: StringName = event.source_instance_id.value
	if dead_entity_ids.has(source_id):
		return &""
	if unrenderable_spawned_ids.has(source_id):
		unrenderable_spawned_ids.erase(source_id)
		dead_entity_ids[source_id] = true
		return &""
	var source := units_by_id.get(source_id) as WorldBoardUnitSnapshot
	if source == null:
		return EVENT_TARGET_UNKNOWN
	draft.units.erase(source)
	units_by_id.erase(source_id)
	dead_entity_ids[source_id] = true
	return &""


func _single_target(
	units_by_id: Dictionary,
	event: BattleEvent
) -> WorldBoardUnitSnapshot:
	var target_id: StringName = event.target_instance_ids[0]
	return units_by_id.get(target_id) as WorldBoardUnitSnapshot


func _targets_nonrenderable(
	unrenderable_spawned_ids: Dictionary,
	dead_entity_ids: Dictionary,
	event: BattleEvent
) -> bool:
	var target_id: StringName = event.target_instance_ids[0]
	return (
		unrenderable_spawned_ids.has(target_id)
		or dead_entity_ids.has(target_id)
	)
