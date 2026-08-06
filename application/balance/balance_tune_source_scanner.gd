class_name BalanceTuneSourceScanner
extends RefCounted

const ROOTS: Array[String] = [
	"res://content/packs/build_systems",
	"res://content/packs/vertical_slice",
]
const TUNE_FIELDS: Array[String] = [
	"health", "attack", "armor", "magic_resist", "attack_speed_milli",
	"attack_range_cells", "start_mana", "max_mana", "move_speed_milli",
	"health_bps", "attack_bps", "armor_bps", "magic_resist_bps",
	"attack_speed_bps", "attack_range_bps", "start_mana_bps", "max_mana_bps",
	"move_speed_bps", "amount", "amount_i32", "base", "cells", "count",
	"count_u32", "required_count", "weight_i32", "value_i32", "value_u32",
	"tier_basis_points", "periodic_interval_ticks", "max_stacks", "duration_ticks",
	"cast_ticks", "activation_limit", "population_bonus", "currency_cost",
	"draw_count", "interest_step_gold", "interest_per_step", "max_interest",
	"reroll_cost", "xp_buy_cost", "xp_buy_amount", "layer_income", "streak_rewards",
	"loss_subsidy", "shop_odds_by_level", "pool_copies_by_tier",
	"unit_costs_by_tier", "xp_thresholds", "completion_reward", "failure_reward",
	"challenge_multiplier_bps", "attack_mana_gain", "damage_mana_factor",
	"damage_mana_min", "damage_mana_max", "overtime_step_bps", "overtime_cap_bps",
	"act1_base_damage", "act2_base_damage", "act3_base_damage", "survivor_damage",
	"boss_damage", "effect_resolution_budget", "operation_budget", "event_budget",
	"entity_budget", "act1_enemy_stat_bps", "act2_enemy_stat_bps",
	"act3_enemy_stat_bps", "cost_tier", "hp_threshold_bps", "int_value", "stack_limit",
	"star", "node_scores",
]
const FIXED_FIELDS: Array[String] = BalanceTuneFieldPolicy.FIXED_FIELDS
## Serialization schema version; changing it is a codec migration, not balance.
const IGNORED_SCHEMA_VERSION: String = "schema_version"
## Canonical operation ordering identity; values must remain contiguous.
const IGNORED_OPERATION_INDEX: String = "operation_index"
## Boss phase ordering identity; phase power lives in threshold/effect values.
const IGNORED_PHASE_INDEX: String = "phase_index"
## Meta unlock identity; challenge tuning lives in referenced effects/multipliers.
const IGNORED_CHALLENGE_LEVEL: String = "challenge_level"
## Economy table lookup key; row values, not row identity, are TUNE.
const IGNORED_LEVEL: String = "level"
## Typed pair lookup key; paired value fields are scanned separately.
const IGNORED_KEY_U32: String = "key_u32"
## Encounter board geometry is authored topology, not numeric balance TUNE.
const IGNORED_LOGICAL_X: String = "logical_x"
const IGNORED_LOGICAL_Y: String = "logical_y"
## Presentation-only ordering.
const IGNORED_SORT_ORDER: String = "sort_order"
## Closed node-choice enum ordinal; payload amounts are scanned separately.
const IGNORED_OUTCOME_KIND: String = "outcome_kind"
const IGNORED_NUMERIC_FIELDS: Array[String] = [
	IGNORED_SCHEMA_VERSION, IGNORED_OPERATION_INDEX, IGNORED_PHASE_INDEX,
	IGNORED_CHALLENGE_LEVEL, IGNORED_LEVEL, IGNORED_KEY_U32,
	IGNORED_LOGICAL_X, IGNORED_LOGICAL_Y, IGNORED_SORT_ORDER,
	IGNORED_OUTCOME_KIND,
]


static func scan() -> BalanceTuneScanResult:
	var entries: Array[BalanceTuneEntry] = []
	for root: String in ROOTS:
		var failure := _scan_dir(root, entries)
		if failure != null:
			return failure
	entries.sort_custom(func(left: BalanceTuneEntry, right: BalanceTuneEntry) -> bool:
		return String(left.field_path) < String(right.field_path)
	)
	return BalanceTuneScanResult.success(entries)


static func collect() -> Array[BalanceTuneEntry]:
	var result := scan()
	if not result.ok:
		push_error("balance TUNE scan failed: %s: %s" % [
			result.error_path, result.error_detail,
		])
		return [] as Array[BalanceTuneEntry]
	return result.entries


static func scan_text(path: String, source: String) -> BalanceTuneScanResult:
	var entries: Array[BalanceTuneEntry] = []
	var section := 0
	for raw_line: String in source.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("["):
			section += 1
			continue
		var failure := _scan_assignment(path, section, line, entries)
		if failure != null:
			return failure
	return BalanceTuneScanResult.success(entries)


static func _scan_dir(
	path: String, output: Array[BalanceTuneEntry]
) -> BalanceTuneScanResult:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return BalanceTuneScanResult.failure(path, "root missing")
	var directories := DirAccess.get_directories_at(path)
	directories.sort()
	for name: String in directories:
		var failure := _scan_dir(path.path_join(name), output)
		if failure != null:
			return failure
	var files := DirAccess.get_files_at(path)
	files.sort()
	for name: String in files:
		if name.ends_with(".tres"):
			var failure := _scan_file(path.path_join(name), output)
			if failure != null:
				return failure
	return null


static func _scan_file(
	path: String, output: Array[BalanceTuneEntry]
) -> BalanceTuneScanResult:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return BalanceTuneScanResult.failure(path, "read failed")
	var section := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("["):
			section += 1
			continue
		var failure := _scan_assignment(path, section, line, output)
		if failure != null:
			file.close()
			return failure
	file.close()
	return null


static func _scan_assignment(
	path: String, section: int, line: String,
	output: Array[BalanceTuneEntry]
) -> BalanceTuneScanResult:
	var separator := line.find(" = ")
	if separator <= 0:
		return null
	var field := line.substr(0, separator).strip_edges()
	var value := line.substr(separator + 3).strip_edges()
	if BalanceTuneFieldPolicy.is_fixed_leaf(field):
		return null
	if TUNE_FIELDS.has(field):
		if not _value_is_balanced(value):
			# The value's brackets/parens do not close on this line, so it
			# continues on a following line that our line-by-line parser cannot
			# see. Silently accepting the truncated first-line text would let a
			# later change to the continuation lines drift tune_digest without
			# changing what was scanned (see F06); fail closed instead.
			return BalanceTuneScanResult.failure(
				"%s#%d.%s" % [path, section, field],
				"tracked field value is not closed on this line (continuation lines are unsupported)"
			)
		output.append(BalanceTuneEntry.new(
			StringName("%s#%d.%s" % [path, section, field]), value
		))
		return null
	if _is_numeric_value(value) and not IGNORED_NUMERIC_FIELDS.has(field):
		return BalanceTuneScanResult.failure(
			"%s#%d.%s" % [path, section, field],
			"numeric field is neither TUNE, fixed, nor explicitly ignored"
		)
	return null


static func _value_is_balanced(value: String) -> bool:
	var depth := 0
	for character: String in value:
		if character == "[" or character == "(":
			depth += 1
		elif character == "]" or character == ")":
			depth -= 1
	return depth == 0


static func _is_numeric_value(value: String) -> bool:
	if value.is_valid_int() or value.is_valid_float():
		return true
	return value.begins_with("Packed") and value.contains("Array([") \
		and _contains_ascii_digit(value)


static func _contains_ascii_digit(value: String) -> bool:
	for code: int in value.to_ascii_buffer():
		if code >= 48 and code <= 57:
			return true
	return false
