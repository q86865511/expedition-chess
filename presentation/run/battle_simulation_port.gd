class_name BattleSimulationPort
extends RefCounted

var _simulation: BattleSimulation


func start(setup: BattleSetup) -> BattleInitializationResult:
	var candidate := BattleSimulation.new()
	var initialized := candidate.initialize(setup)
	if initialized.ok:
		_simulation = candidate
	return initialized


func step() -> BattleStepResult:
	if _simulation == null:
		return BattleStepResult.failure(BattleSimulationError.new(
			BattleSimulationError.LIFECYCLE_INVALID, &"battle_simulation_port"
		))
	return _simulation.step()


func result() -> BattleResultQuery:
	if _simulation == null:
		return BattleResultQuery.failure(BattleSimulationError.new(
			BattleSimulationError.LIFECYCLE_INVALID, &"battle_simulation_port"
		))
	return _simulation.result()
