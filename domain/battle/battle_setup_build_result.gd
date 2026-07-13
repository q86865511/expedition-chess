class_name BattleSetupBuildResult
extends RefCounted

var ok: bool = false
var battle_setup: BattleSetup = null
var error: BattleSetupBuildError = null

static func success(value: BattleSetup) -> BattleSetupBuildResult:
	return BattleSetupBuildResult.new(true, value, null)

static func failure(code: StringName, path: StringName = &"") -> BattleSetupBuildResult:
	return BattleSetupBuildResult.new(
		false, null, BattleSetupBuildError.create(code, path)
	)

func _init(
	p_ok: bool,
	p_battle_setup: BattleSetup,
	p_error: BattleSetupBuildError
) -> void:
	ResultInvariant.require(
		p_ok, p_error, p_battle_setup != null, p_battle_setup == null
	)
	ok = p_ok
	battle_setup = p_battle_setup.deep_clone() if p_battle_setup != null else null
	error = p_error
