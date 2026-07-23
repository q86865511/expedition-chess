extends GutTest

## W3-F3 / T05 / specs/build-systems/design.md §5.4: the item-overflow tray hard
## gate's 繞不過 final defence lives in RunStateValidator (inside
## _validate_phase_resolution_pair), not only in the StartCombatEvent /
## NonCombatNodeService early-exit checks. Any draft whose run_phase has already
## left PREPARE -- into COMBAT, a committed MAP transition, or terminal RESULTS --
## while pending_item_overflow is non-empty is rejected at commit-validate time.
## So a future PREPARE exit that forgets its own early check still cannot bypass
## the tray into a softlock. PREPARE and REWARD keep the tray legal: PREPARE is
## the disposition window, REWARD is where the item-resolution flow populates it.
##
## These bypass the two services entirely and hand a hand-built draft straight to
## validate_run(), which is the layer every RunController commit passes through.

func test_validator_accepts_non_empty_tray_during_prepare() -> void:
	# Positive control: the very same tray-bearing draft is valid in PREPARE,
	# proving the rejections below are caused only by the phase, not the tray item.
	var run := _run_with_overflow_tray(RunState.RunPhase.PREPARE)
	var result := RunStateValidator.new().validate_run(run, 1, 1)
	assert_true(result.ok, String(result.error.field_path) if result.error != null else "none")

func test_validator_rejects_non_empty_tray_after_committed_map_transition() -> void:
	var run := _run_with_overflow_tray(RunState.RunPhase.MAP)
	var result := RunStateValidator.new().validate_run(run, 1, 1)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.roster_state.pending_item_overflow")

func test_validator_rejects_non_empty_tray_in_terminal_results() -> void:
	var run := _run_with_overflow_tray(RunState.RunPhase.RESULTS)
	run.expedition_hp = 0
	var result := RunStateValidator.new().validate_run(run, 1, 1)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.roster_state.pending_item_overflow")

## Builds an otherwise-valid RunState in `phase` with a single unbound instance
## sitting in the one-shot overflow tray -- mirroring the tray-population shape
## used by tests/integration/build_items/test_overflow_phase_gate.gd.
func _run_with_overflow_tray(phase: RunState.RunPhase) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = phase
	run.resolution_state = IdleResolutionState.new()
	var overflow_id := "it_0000000000000099"
	run.roster_state.item_instances.append(ItemInstanceState.new(
		overflow_id, &"unit.hero", null, U64Bits.from_u32(0, 99).value
	))
	run.roster_state.pending_item_overflow = [overflow_id]
	return run
