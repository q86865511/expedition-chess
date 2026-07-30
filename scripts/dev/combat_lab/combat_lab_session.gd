class_name CombatLabSession
extends RefCounted

## Thin dev consumer. The production-composed BattleSimulationPort owns the
## battle engine and all lifecycle semantics.

const PORT_MISSING: StringName = &"COMBAT_LAB_BATTLE_PORT_MISSING"

var _battle_port: BattleSimulationPort
var _run_session: RunPresentationSession


func _init(
	p_battle_port: BattleSimulationPort = null,
	p_run_session: RunPresentationSession = null
) -> void:
	_battle_port = p_battle_port
	_run_session = p_run_session


func bind(p_battle_port: BattleSimulationPort) -> void:
	_battle_port = p_battle_port


func bind_run_presentation(p_run_session: RunPresentationSession) -> void:
	_run_session = p_run_session


func start(setup: BattleSetup) -> BattleInitializationResult:
	if _battle_port == null:
		return BattleInitializationResult.failure(BattleSimulationError.new(
			BattleSimulationError.LIFECYCLE_INVALID, PORT_MISSING
		))
	return _battle_port.start(setup)


func step() -> BattleStepResult:
	if _battle_port == null:
		return BattleStepResult.failure(BattleSimulationError.new(
			BattleSimulationError.LIFECYCLE_INVALID, PORT_MISSING
		))
	return _battle_port.step()


func result() -> BattleResultQuery:
	if _battle_port == null:
		return BattleResultQuery.failure(BattleSimulationError.new(
			BattleSimulationError.LIFECYCLE_INVALID, PORT_MISSING
		))
	return _battle_port.result()
