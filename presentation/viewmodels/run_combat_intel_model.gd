class_name RunCombatIntelModel
extends RefCounted

const SNAPSHOT_INVALID: StringName = &"COMBAT_SNAPSHOT_INVALID"


class EnemyIntelRow:
	extends RefCounted

	var unit_id: StringName
	var logical_x: int
	var logical_y: int
	var ability_id: StringName
	var effect_ids: Array[StringName] = []
	var target_ids: Array[StringName] = []

	func deep_clone() -> EnemyIntelRow:
		var clone := EnemyIntelRow.new()
		clone.unit_id = unit_id
		clone.logical_x = logical_x
		clone.logical_y = logical_y
		clone.ability_id = ability_id
		clone.effect_ids.assign(effect_ids)
		clone.target_ids.assign(target_ids)
		return clone


class BossPhaseIntelRow:
	extends RefCounted

	var phase_index: int
	var hp_threshold_bps: int
	var effect_ids: Array[StringName] = []

	func deep_clone() -> BossPhaseIntelRow:
		var clone := BossPhaseIntelRow.new()
		clone.phase_index = phase_index
		clone.hp_threshold_bps = hp_threshold_bps
		clone.effect_ids.assign(effect_ids)
		return clone


class InspectionIntelRow:
	extends RefCounted

	var unit_serial: int
	var source_id: StringName
	var side_id: StringName
	var star: int
	var trait_ids: Array[StringName] = []

	func deep_clone() -> InspectionIntelRow:
		var clone := InspectionIntelRow.new()
		clone.unit_serial = unit_serial
		clone.source_id = source_id
		clone.side_id = side_id
		clone.star = star
		clone.trait_ids.assign(trait_ids)
		return clone


var _snapshot: RunPresentationSnapshot
var _enemy_rows: Array[EnemyIntelRow] = []
var _inspection_rows: Array[InspectionIntelRow] = []
var _active_trait_ids: Array[StringName] = []
var _boss_phase_rows: Array[BossPhaseIntelRow] = []


func compose(snapshot: RunPresentationSnapshot) -> StringName:
	_clear()
	if snapshot == null or snapshot.app_phase != &"COMBAT" or snapshot.map == null:
		return SNAPSHOT_INVALID
	_snapshot = snapshot.deep_clone()
	for inspection: CombatUnitInspectionSnapshot in _snapshot.combat_inspections:
		if inspection == null:
			continue
		var inspection_row := InspectionIntelRow.new()
		inspection_row.unit_serial = inspection.unit_serial
		inspection_row.source_id = inspection.source_id
		inspection_row.side_id = inspection.side_id
		inspection_row.star = int(inspection.stats.get("star", 0))
		inspection_row.trait_ids.assign(inspection.trait_ids)
		_inspection_rows.append(inspection_row)
	_inspection_rows.sort_custom(func(
		left: InspectionIntelRow,
		right: InspectionIntelRow
	) -> bool:
		var left_rank := 0 if left.side_id in [&"player", &"ally"] else 1
		var right_rank := 0 if right.side_id in [&"player", &"ally"] else 1
		return (
			left.unit_serial < right.unit_serial
			if left_rank == right_rank
			else left_rank < right_rank
		)
	)
	var preview := _current_encounter_preview(_snapshot)
	if preview == null:
		_clear()
		return SNAPSHOT_INVALID
	for enemy: UnitBattleSnapshot in preview.enemy_units:
		var row := EnemyIntelRow.new()
		row.unit_id = enemy.unit_id
		row.logical_x = enemy.logical_x
		row.logical_y = enemy.logical_y
		row.ability_id = (
			enemy.ability_id.value if enemy.ability_id != null else &""
		)
		row.effect_ids.assign(enemy.effect_ids)
		for assignment: BattleEffectSnapshot in enemy.effect_assignments:
			for target_id: StringName in assignment.target_ids:
				if not row.target_ids.has(target_id):
					row.target_ids.append(target_id)
		_enemy_rows.append(row)
	for trait_snapshot: TraitBattleSnapshot in preview.active_traits:
		_active_trait_ids.append(trait_snapshot.trait_id)
	for phase: BossPhaseSnapshot in preview.boss_phases:
		var row := BossPhaseIntelRow.new()
		row.phase_index = phase.phase_index
		row.hp_threshold_bps = phase.hp_threshold_bps
		row.effect_ids.assign(phase.effect_ids)
		_boss_phase_rows.append(row)
	return &""


func enemy_rows() -> Array[EnemyIntelRow]:
	var result: Array[EnemyIntelRow] = []
	for row: EnemyIntelRow in _enemy_rows:
		result.append(row.deep_clone())
	return result


func inspection_rows() -> Array[InspectionIntelRow]:
	var result: Array[InspectionIntelRow] = []
	for row: InspectionIntelRow in _inspection_rows:
		result.append(row.deep_clone())
	return result


func active_trait_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_active_trait_ids)
	return result


func boss_phase_rows() -> Array[BossPhaseIntelRow]:
	var result: Array[BossPhaseIntelRow] = []
	for row: BossPhaseIntelRow in _boss_phase_rows:
		result.append(row.deep_clone())
	return result


func _current_encounter_preview(
	snapshot: RunPresentationSnapshot
) -> EncounterPreviewSnapshot:
	if snapshot.map.current_node_id == null:
		return null
	var current_node_id: String = snapshot.map.current_node_id.value
	for node: MapNodeState in snapshot.map.nodes:
		if node.node_id == current_node_id:
			return (
				node.encounter_preview.deep_clone()
				if node.encounter_preview != null
				else null
			)
	return null


func _clear() -> void:
	_snapshot = null
	_enemy_rows.clear()
	_inspection_rows.clear()
	_active_trait_ids.clear()
	_boss_phase_rows.clear()
