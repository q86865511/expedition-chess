class_name FakeCombatRunController
extends RunController

var _run: RunState
var record_succeeds: bool
var record_attempts: int = 0

func _init(run: RunState, p_record_succeeds: bool = true) -> void:
	super(null, null)
	_run = run.deep_clone()
	record_succeeds = p_record_succeeds

func committed_combat_snapshot() -> CombatCommittedSnapshot:
	return CombatCommittedSnapshot.new(
		U64Bits.zero(), _run.run_phase, _run.run_seed, _run.resolution_state
	)

func dispatch(command: RunCommand) -> CommandResult:
	record_attempts += 1
	if not record_succeeds:
		return CommandResult.failure(CommandError.new(
			CommandError.SAVE_FAILED, _run.run_phase, &"save"
		))
	var applied := command.apply_to(_run.deep_clone())
	if not applied.ok:
		return CommandResult.failure(CommandError.new(
			CommandError.APPLY_FAILED,
			_run.run_phase,
			applied.error.field_path if applied.error != null else &"command"
		))
	_run = applied.draft.deep_clone()
	return CommandResult.success(RunViewState.from_run(_run, U64Bits.one()))

func run_snapshot_for_test() -> RunState:
	return _run.deep_clone()
