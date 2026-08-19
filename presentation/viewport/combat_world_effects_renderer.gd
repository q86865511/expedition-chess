class_name CombatWorldEffectsRenderer
extends Node2D

const COMBAT_VFX_ATLAS := preload(
	"res://assets/production/shared/combat_vfx.png"
)
const STATUS_DAMAGE_ATLAS := preload(
	"res://assets/production/shared/status_damage.png"
)

const EFFECT_TYPES: Array[StringName] = [
	&"attack",
	&"cast",
	&"damage",
	&"status",
]

var _projection := BoardProjection.new()
var _last_positions: Dictionary = {}
var _processed_sequences: Array[int] = []
var _spawned_by_kind: Dictionary = {}
var _motion_enabled: bool = true


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	z_index = ExpeditionLayoutMetrics.COMBAT_EFFECT_LAYER


## Clone-free read of an already presentation-owned snapshot. Missing units are
## deliberately retained so a death event can still finish at its last known
## foot position after the board projection removes the body.
func sync_snapshot(snapshot: WorldBoardSnapshot) -> void:
	if snapshot == null or not snapshot.is_valid():
		return
	for unit: WorldBoardUnitSnapshot in snapshot.units:
		_last_positions[unit.presentation_instance_id] = (
			_projection.project_cell(unit.logical_cell).round()
		)


func configure_accessibility(motion_enabled: bool) -> void:
	_motion_enabled = motion_enabled


## Every event is visited in canonical window order. damage_budget affects only
## how many floating labels are instantiated; it never filters or reorders the
## event stream consumed by the board projection.
func present_events(
	events: Array,
	snapshot: WorldBoardSnapshot,
	damage_budget: int
) -> Dictionary:
	sync_snapshot(snapshot)
	var remaining_damage_labels := maxi(
		0,
		damage_budget - _active_count(&"floating_damage")
	)
	var window_vfx := 0
	var window_damage_labels := 0
	for value: Variant in events:
		if not value is BattleEvent:
			continue
		var event := value as BattleEvent
		_processed_sequences.append(event.sequence)
		if event.type not in EFFECT_TYPES:
			continue
		var position_value: Variant = _event_position(event)
		if position_value == null:
			continue
		var position: Vector2 = position_value
		match event.type:
			&"cast":
				_spawn_combat_vfx(event, position, 1, &"skill")
				window_vfx += 1
			&"attack":
				_spawn_combat_vfx(event, position, 4, &"attack")
				window_vfx += 1
			&"damage":
				_spawn_status_vfx(event, position, 3, &"hit")
				window_vfx += 1
				if remaining_damage_labels > 0:
					var payload := event.payload as DamageEventPayload
					if payload != null:
						_spawn_damage_label(event, position, payload.health_damage)
						remaining_damage_labels -= 1
						window_damage_labels += 1
			&"status":
				_spawn_status_vfx(
					event,
					position,
					_status_row(event),
					&"status"
				)
				window_vfx += 1
	return {
		"processed": events.size(),
		"spawned_vfx": window_vfx,
		"spawned_damage_labels": window_damage_labels,
		"active_vfx": _active_count(&"vfx"),
		"active_damage_labels": _active_count(&"floating_damage"),
	}


func advance_playback(delta_ms: float) -> void:
	var safe_delta := maxf(0.0, delta_ms)
	if safe_delta <= 0.0:
		return
	for child: Node in get_children():
		if not child is CanvasItem or not child.has_meta(&"combat_effect_track"):
			continue
		var item := child as CanvasItem
		var age := float(item.get_meta(&"age_ms", 0.0)) + safe_delta
		var duration := maxf(1.0, float(item.get_meta(&"duration_ms", 1.0)))
		item.set_meta(&"age_ms", age)
		var progress := clampf(age / duration, 0.0, 1.0)
		item.modulate.a = 1.0 - progress
		if item is Sprite2D:
			var sprite := item as Sprite2D
			var base_scale := float(item.get_meta(&"base_scale", 1.0))
			var pulse := 1.0 + sin(progress * PI) * 0.18
			sprite.scale = Vector2.ONE * base_scale * pulse
		elif item is Label and _motion_enabled:
			var label := item as Label
			var start := item.get_meta(&"start_position", label.position) as Vector2
			label.position = start + Vector2(
				0.0,
				-ExpeditionLayoutMetrics.COMBAT_DAMAGE_FLOAT_RISE * progress
			)
		if age >= duration:
			item.queue_free()


func clear_effects() -> void:
	for child: Node in get_children():
		child.queue_free()
	_last_positions.clear()
	_processed_sequences.clear()
	_spawned_by_kind.clear()


func processed_sequences() -> Array[int]:
	return _processed_sequences.duplicate()


func visual_report() -> Dictionary:
	return {
		"active_vfx": _active_count(&"vfx"),
		"active_damage_labels": _active_count(&"floating_damage"),
		"processed_sequences": _processed_sequences.duplicate(),
		"spawned_by_kind": _spawned_by_kind.duplicate(true),
		"combat_vfx_path": COMBAT_VFX_ATLAS.resource_path,
		"status_damage_path": STATUS_DAMAGE_ATLAS.resource_path,
	}


func _spawn_combat_vfx(
	event: BattleEvent,
	position: Vector2,
	row: int,
	kind: StringName
) -> void:
	var color_column := _combat_color_column(event)
	_spawn_atlas_sprite(
		COMBAT_VFX_ATLAS,
		&"combat_vfx",
		Vector2i(color_column, row),
		position,
		event,
		kind
	)


func _spawn_status_vfx(
	event: BattleEvent,
	position: Vector2,
	row: int,
	kind: StringName
) -> void:
	_spawn_atlas_sprite(
		STATUS_DAMAGE_ATLAS,
		&"status_damage",
		Vector2i(_status_color_column(event), row),
		position,
		event,
		kind
	)


func _spawn_atlas_sprite(
	texture: Texture2D,
	atlas_id: StringName,
	cell: Vector2i,
	position: Vector2,
	event: BattleEvent,
	kind: StringName
) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Effect_%s_%d" % [String(kind), event.sequence]
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		Vector2(cell * ExpeditionLayoutMetrics.COMBAT_ATLAS_CELL_SIZE),
		Vector2(ExpeditionLayoutMetrics.COMBAT_ATLAS_CELL_SIZE)
	)
	sprite.centered = true
	sprite.position = position + _effect_offset(kind)
	var visual_scale := _effect_scale(kind)
	sprite.scale = Vector2.ONE * visual_scale
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.set_meta(&"combat_effect_track", &"vfx")
	sprite.set_meta(&"effect_kind", kind)
	sprite.set_meta(&"atlas_id", atlas_id)
	sprite.set_meta(&"atlas_cell", cell)
	sprite.set_meta(&"event_sequence", event.sequence)
	sprite.set_meta(&"age_ms", 0.0)
	sprite.set_meta(
		&"duration_ms",
		ExpeditionLayoutMetrics.COMBAT_VFX_DURATION_MS
	)
	sprite.set_meta(&"base_scale", visual_scale)
	add_child(sprite)
	_increment_spawned(kind)


func _spawn_damage_label(
	event: BattleEvent,
	position: Vector2,
	amount: int
) -> void:
	var label := Label.new()
	label.name = "Damage_%d" % event.sequence
	label.text = "-%d" % maxi(0, amount)
	label.position = position + ExpeditionLayoutMetrics.COMBAT_DAMAGE_FLOAT_OFFSET
	label.size = ExpeditionLayoutMetrics.COMBAT_DAMAGE_FLOAT_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_as_relative = false
	label.z_index = ExpeditionLayoutMetrics.COMBAT_DAMAGE_LABEL_LAYER
	var settings := LabelSettings.new()
	settings.font_size = ExpeditionLayoutMetrics.COMBAT_DAMAGE_FONT_SIZE
	settings.font_color = _damage_color(event)
	settings.outline_color = Color(0.025, 0.035, 0.055, 0.98)
	settings.outline_size = ExpeditionLayoutMetrics.COMBAT_DAMAGE_OUTLINE_SIZE
	label.label_settings = settings
	label.set_meta(&"combat_effect_track", &"floating_damage")
	label.set_meta(&"event_sequence", event.sequence)
	label.set_meta(&"damage_amount", amount)
	label.set_meta(&"age_ms", 0.0)
	label.set_meta(
		&"duration_ms",
		ExpeditionLayoutMetrics.COMBAT_DAMAGE_FLOAT_DURATION_MS
	)
	label.set_meta(&"start_position", label.position)
	add_child(label)
	_increment_spawned(&"floating_damage")


func _event_position(event: BattleEvent) -> Variant:
	for target_id: StringName in event.target_instance_ids:
		if _last_positions.has(target_id):
			return _last_positions[target_id] as Vector2
	if event.source_instance_id != null:
		var source_id: StringName = event.source_instance_id.value
		if _last_positions.has(source_id):
			return _last_positions[source_id] as Vector2
	return null


func _effect_offset(kind: StringName) -> Vector2:
	return {
		&"skill": ExpeditionLayoutMetrics.COMBAT_VFX_SKILL_OFFSET,
		&"attack": ExpeditionLayoutMetrics.COMBAT_VFX_ATTACK_OFFSET,
		&"hit": ExpeditionLayoutMetrics.COMBAT_VFX_HIT_OFFSET,
		&"status": ExpeditionLayoutMetrics.COMBAT_VFX_STATUS_OFFSET,
	}.get(kind, ExpeditionLayoutMetrics.COMBAT_VFX_HIT_OFFSET)


func _effect_scale(kind: StringName) -> float:
	return ExpeditionLayoutMetrics.COMBAT_VFX_SCALE * (
		0.82 if kind in [&"hit", &"status"] else 1.0
	)


func _combat_color_column(event: BattleEvent) -> int:
	if event.payload is DamageEventPayload:
		match (event.payload as DamageEventPayload).damage_type:
			&"magic":
				return 1
			&"true":
				return 2
			_:
				return 0
	return posmod(event.sequence, 4)


func _status_color_column(event: BattleEvent) -> int:
	if event.payload is DamageEventPayload:
		match (event.payload as DamageEventPayload).damage_type:
			&"magic":
				return 3
			&"true":
				return 2
			_:
				return 0
	return posmod(event.sequence, 4)


func _status_row(event: BattleEvent) -> int:
	var payload := event.payload as StatusEventPayload
	if payload == null:
		return 0
	var stable_sum := 0
	var status_text := String(payload.status_id)
	for index: int in status_text.length():
		stable_sum += status_text.unicode_at(index)
	return posmod(stable_sum, 8)


func _damage_color(event: BattleEvent) -> Color:
	var payload := event.payload as DamageEventPayload
	if payload == null:
		return Color("fff1d0")
	return {
		&"physical": Color("ffd760"),
		&"magic": Color("d592ff"),
		&"true": Color("66f2de"),
	}.get(payload.damage_type, Color("fff1d0"))


func _active_count(track_kind: StringName) -> int:
	var result := 0
	for child: Node in get_children():
		if StringName(child.get_meta(&"combat_effect_track", &"")) == track_kind:
			result += 1
	return result


func _increment_spawned(kind: StringName) -> void:
	_spawned_by_kind[kind] = int(_spawned_by_kind.get(kind, 0)) + 1
