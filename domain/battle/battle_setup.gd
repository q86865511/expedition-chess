class_name BattleSetup
extends RefCounted

var inputs: BattleSetupInputs = null
var hash_version: int = 1
var battle_setup_hash: StringName = &""
var rng_version: int = 1
var combat_rng_snapshot: RngSnapshot = null

func deep_clone() -> BattleSetup:
	var copied := BattleSetup.new()
	copied.inputs = inputs.deep_clone() if inputs != null else null
	copied.hash_version = hash_version
	copied.battle_setup_hash = battle_setup_hash
	copied.rng_version = rng_version
	copied.combat_rng_snapshot = combat_rng_snapshot.deep_clone() if combat_rng_snapshot != null else null
	return copied
