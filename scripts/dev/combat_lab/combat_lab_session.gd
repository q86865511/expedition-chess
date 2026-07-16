class_name CombatLabSession
extends RefCounted

var _simulation: BattleSimulation

func start(setup: BattleSetup) -> BattleInitializationResult:
	var simulation := BattleSimulation.new()
	var initialized := simulation.initialize(setup)
	if initialized.ok:
		_simulation = simulation
	return initialized

func step() -> BattleStepResult:
	if _simulation == null:
		return BattleStepResult.failure(BattleSimulationError.new(
			BattleSimulationError.LIFECYCLE_INVALID, &"combat_lab_session"
		))
	return _simulation.step()

func result() -> BattleResultQuery:
	if _simulation == null:
		return BattleResultQuery.failure(BattleSimulationError.new(
			BattleSimulationError.LIFECYCLE_INVALID, &"combat_lab_session"
		))
	return _simulation.result()
