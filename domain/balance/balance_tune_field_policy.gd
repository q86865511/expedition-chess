class_name BalanceTuneFieldPolicy
extends RefCounted

## combat-core design §2.2 fixed rules. These fields are versioned simulation
## contracts, never candidate TUNE values.
const FIXED_FIELDS: Array[String] = [
	"simulation_version",
	"tick_rate",
	"board_width",
	"board_height",
	"soft_limit_ticks",
	"hard_limit_ticks",
	"progress_scale",
	"resistance_base",
	"basis_points",
	"overtime_interval_ticks",
	"main_actions_per_tick",
]

const QUALIFIED_FIXED_RULE_FIELDS: Array[String] = [
	"combat.simulation_version",
	"combat.tick_rate",
	"combat.board_width",
	"combat.board_height",
	"combat.soft_limit_ticks",
	"combat.hard_limit_ticks",
	"combat.progress_scale",
	"combat.resistance_base",
	"combat.basis_points",
	"combat.overtime_interval_ticks",
	"combat.main_actions_per_tick",
]


static func is_fixed_leaf(field: String) -> bool:
	return FIXED_FIELDS.has(field)


static func is_fixed_path(path: String) -> bool:
	for field: String in FIXED_FIELDS:
		if path == "combat.%s" % field:
			return true
		if path.contains("/combat_configs/") and path.ends_with(".%s" % field):
			return true
	return false
