class_name EncounterPreviewValidator
extends RefCounted

const INVALID: StringName = &"ENCOUNTER_PREVIEW_INVALID"
const ENTITY_ID_COLLISION: StringName = &"BATTLE_ENTITY_ID_COLLISION"
const MAX_U32: int = 0xffffffff

var _stable_ids := StableIdValidator.new()

func validate(
	preview: EncounterPreviewSnapshot,
	player_instance_ids: Array[StringName] = []
) -> EncounterPreviewValidationResult:
	if preview == null:
		return EncounterPreviewValidationResult.failure(INVALID, &"preview")
	if preview.preview_schema_version != 1:
		return EncounterPreviewValidationResult.failure(
			INVALID, &"preview.preview_schema_version"
		)
	if not _stable_ids.is_valid(preview.encounter_id):
		return EncounterPreviewValidationResult.failure(
			INVALID, &"preview.encounter_id", preview.encounter_id
		)
	if not _is_digest(String(preview.manifest_digest)):
		return EncounterPreviewValidationResult.failure(
			INVALID, &"preview.manifest_digest"
		)
	var seen_ids: Dictionary = {}
	for index: int in range(player_instance_ids.size()):
		var player_id := player_instance_ids[index]
		if not _is_strict_ascii(String(player_id)):
			return EncounterPreviewValidationResult.failure(
				INVALID,
				StringName("player_instance_ids.%d" % index),
				player_id
			)
		if seen_ids.has(player_id):
			return EncounterPreviewValidationResult.failure(
				ENTITY_ID_COLLISION,
				StringName("player_instance_ids.%d" % index),
				player_id
			)
		seen_ids[player_id] = true
	var occupied_cells: Dictionary = {}
	var enemy_ids: Dictionary = {}
	var previous_unit: UnitBattleSnapshot = null
	for index: int in range(preview.enemy_units.size()):
		var unit := preview.enemy_units[index]
		var item_path := StringName("preview.enemy_units.%d" % index)
		if unit == null or unit.side != &"enemy":
			return EncounterPreviewValidationResult.failure(INVALID, item_path)
		if not _is_enemy_id(String(unit.instance_id)):
			return EncounterPreviewValidationResult.failure(
				INVALID,
				StringName("%s.instance_id" % item_path),
				unit.instance_id
			)
		if seen_ids.has(unit.instance_id):
			return EncounterPreviewValidationResult.failure(
				ENTITY_ID_COLLISION,
				StringName("%s.instance_id" % item_path),
				unit.instance_id
			)
		if unit.logical_y < 0 or unit.logical_y > 7 \
			or unit.logical_x < 0 or unit.logical_x > 7:
			return EncounterPreviewValidationResult.failure(INVALID, item_path)
		var cell_key := unit.logical_y * 8 + unit.logical_x
		if occupied_cells.has(cell_key):
			return EncounterPreviewValidationResult.failure(
				INVALID, StringName("%s.cell" % item_path)
			)
		if previous_unit != null and not _unit_before(previous_unit, unit):
			return EncounterPreviewValidationResult.failure(
				INVALID, &"preview.enemy_units"
			)
		seen_ids[unit.instance_id] = true
		enemy_ids[unit.instance_id] = true
		occupied_cells[cell_key] = true
		previous_unit = unit
	var trait_result := _validate_traits(preview.active_traits, enemy_ids)
	if not trait_result.ok:
		return trait_result
	var previous_phase := -1
	for index: int in range(preview.boss_phases.size()):
		var phase := preview.boss_phases[index]
		var phase_path := StringName("preview.boss_phases.%d" % index)
		if phase == null or not _is_u32(phase.phase_index) \
			or phase.phase_index <= previous_phase \
			or phase.hp_threshold_bps < 0 \
			or phase.hp_threshold_bps > 10000:
			return EncounterPreviewValidationResult.failure(INVALID, phase_path)
		if not enemy_ids.has(phase.source_instance_id):
			return EncounterPreviewValidationResult.failure(
				INVALID,
				StringName("%s.source_instance_id" % phase_path),
				phase.source_instance_id
			)
		if not _sorted_unique_stable_ids(phase.effect_ids):
			return EncounterPreviewValidationResult.failure(
				INVALID, StringName("%s.effect_ids" % phase_path)
			)
		previous_phase = phase.phase_index
	return EncounterPreviewValidationResult.success()

func _validate_traits(
	traits: Array[TraitBattleSnapshot],
	all_instance_ids: Dictionary
) -> EncounterPreviewValidationResult:
	var previous_id := ""
	for index: int in range(traits.size()):
		var trait_snapshot := traits[index]
		var path := StringName("preview.active_traits.%d" % index)
		if trait_snapshot == null \
			or not _stable_ids.is_valid(trait_snapshot.trait_id) \
			or trait_snapshot.tier <= 0:
			return EncounterPreviewValidationResult.failure(INVALID, path)
		var trait_id_text := String(trait_snapshot.trait_id)
		if index > 0 and previous_id >= trait_id_text:
			return EncounterPreviewValidationResult.failure(
				INVALID, &"preview.active_traits"
			)
		var previous_member := ""
		for member_index: int in range(trait_snapshot.member_instance_ids.size()):
			var member_id := trait_snapshot.member_instance_ids[member_index]
			var member_text := String(member_id)
			if not all_instance_ids.has(member_id) \
				or (member_index > 0 and previous_member >= member_text):
				return EncounterPreviewValidationResult.failure(
					INVALID,
					StringName("%s.member_instance_ids" % path),
					member_id
				)
			previous_member = member_text
		previous_id = trait_id_text
	return EncounterPreviewValidationResult.success()

func _unit_before(left: UnitBattleSnapshot, right: UnitBattleSnapshot) -> bool:
	if left.logical_y != right.logical_y:
		return left.logical_y < right.logical_y
	if left.logical_x != right.logical_x:
		return left.logical_x < right.logical_x
	return String(left.instance_id) < String(right.instance_id)

func _sorted_unique_stable_ids(values: Array[StringName]) -> bool:
	var previous := ""
	for index: int in range(values.size()):
		var current := String(values[index])
		if not _stable_ids.is_valid(values[index]) \
			or (index > 0 and previous >= current):
			return false
		previous = current
	return true

func _is_enemy_id(value: String) -> bool:
	if value.length() != 18 or not value.begins_with("e_"):
		return false
	for index: int in range(2, value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) \
			and not (code >= 97 and code <= 102):
			return false
	return true

func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) \
			and not (code >= 97 and code <= 102):
			return false
	return true

func _is_strict_ascii(value: String) -> bool:
	if value.is_empty():
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 33 or byte > 126:
			return false
	return true

func _is_u32(value: int) -> bool:
	return value >= 0 and value <= MAX_U32
