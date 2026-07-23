extends GutTest

## T10 / S4-AC-013 (specs/build-systems/design.md §8, HANDOFF.md §2) --
## RelicSlotViewModel (presentation/viewmodels/relic_slot_view_model.gd,
## currently does not exist).
##
## Expected contract (test-author decision -- see
## tests/fixtures/build_systems/view_model_test_fixture.gd header for the two
## new RunController read accessors this suite requires,
## `roster_snapshot()`/`pending_reward_snapshot()`, and for
## RELIC_RESOLUTION fixture rationale):
##   class_name RelicSlotViewModel extends RefCounted
##   func _init(controller: RunController) -> void
##   func active_slots() -> Array[RelicSlotState]
##   func pending_replacement_candidate() -> OptionalStringNameValue
##   func choose_slot(slot_index: int, catalog: EconomyExpeditionCatalog) -> CommandResult
## `pending_replacement_candidate()` surfaces the currently-offered RELIC-kind
## reward's content_id (design §8's "第六件替換候選") by reading
## `RunController.pending_reward_snapshot()` -- null when the run is not
## currently in `PendingRewardState.Phase.RELIC_RESOLUTION` with a selected
## RELIC offer, so the UI knows there is nothing to preview a replacement for.
## `choose_slot()` must dispatch the real `ResolveRelicRewardCommand` through
## `RunController.dispatch()` (design §8: "寫端一律經 command").

func test_active_slots_reflects_roster_snapshot_and_is_isolated_from_domain() -> void:
	var run := ViewModelTestFixture.relic_resolution_run()
	var controller := _controller_for(run)
	var view_model := RelicSlotViewModel.new(controller)

	var slots := view_model.active_slots()
	assert_eq(slots.size(), 5)
	for slot: RelicSlotState in slots:
		assert_eq(slot.relic_id.value, ViewModelTestFixture.RELIC_OLD)

	# 契約測試（design §8）：改動回傳陣列中的物件不得影響 domain 或之後的讀取。
	slots[0].relic_id = OptionalStringNameValue.of(&"relic.injected")
	var again := view_model.active_slots()
	assert_eq(again[0].relic_id.value, ViewModelTestFixture.RELIC_OLD)
	var roster_after := controller.roster_snapshot()
	assert_eq(roster_after.active_relic_slots[0].relic_id.value, ViewModelTestFixture.RELIC_OLD)

func test_pending_replacement_candidate_returns_offered_relic_during_relic_resolution() -> void:
	var run := ViewModelTestFixture.relic_resolution_run()
	var controller := _controller_for(run)
	var view_model := RelicSlotViewModel.new(controller)

	var candidate := view_model.pending_replacement_candidate()
	assert_not_null(candidate, "RELIC_RESOLUTION 階段有已選定的 RELIC offer 時應回傳其 content_id")
	if candidate == null:
		return
	assert_eq(candidate.value, ViewModelTestFixture.RELIC_NEW)

func test_pending_replacement_candidate_is_null_outside_relic_resolution() -> void:
	var run := ViewModelTestFixture.trait_preview_run()
	var catalog := ViewModelTestFixture.trait_battle_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := ViewModelTestFixture.controller_for(run, catalog, repository)
	var view_model := RelicSlotViewModel.new(controller)

	assert_null(
		view_model.pending_replacement_candidate(),
		"非 REWARD/RELIC_RESOLUTION 階段不應回傳任何替換候選"
	)

func test_choose_slot_success_replaces_relic_in_chosen_slot() -> void:
	var run := ViewModelTestFixture.relic_resolution_run()
	var catalog := ViewModelTestFixture.relic_economy_catalog()
	var controller := _controller_for(run)
	var view_model := RelicSlotViewModel.new(controller)

	var result := view_model.choose_slot(2, catalog)
	assert_true(result.ok, ViewModelTestFixture.command_error_source_code(result))
	if not result.ok:
		return
	var slots_after := result.view_state.roster.active_relic_slots
	assert_eq(slots_after[2].relic_id.value, ViewModelTestFixture.RELIC_NEW)
	for index: int in [0, 1, 3, 4]:
		assert_eq(slots_after[index].relic_id.value, ViewModelTestFixture.RELIC_OLD)

func test_choose_slot_rejects_wrong_run_phase_with_named_error() -> void:
	var run := ViewModelTestFixture.relic_resolution_run()
	# 離開 REWARD 階段（模擬「目前根本沒有待處理的遺物獎勵」情境）：
	# ResolveRelicRewardCommand 必須拒絕,且不得更動任何槽位。
	run.run_phase = RunState.RunPhase.MAP
	run.resolution_state = IdleResolutionState.new()
	var catalog := ViewModelTestFixture.relic_economy_catalog()
	var controller := _controller_for(run)
	var view_model := RelicSlotViewModel.new(controller)

	var result := view_model.choose_slot(2, catalog)
	assert_false(result.ok)
	assert_eq(ViewModelTestFixture.command_error_source_code(result), "EXPEDITION_PHASE_INVALID")
	var slots_after := view_model.active_slots()
	for slot: RelicSlotState in slots_after:
		assert_eq(slot.relic_id.value, ViewModelTestFixture.RELIC_OLD)

func _controller_for(run: RunState) -> RunController:
	var storage := FakeSaveStorage.new()
	var repository := ViewModelTestFixture.relic_repository_for(storage)
	add_child_autofree(repository)
	var battle_catalog := ViewModelTestFixture.relic_battle_catalog()
	return ViewModelTestFixture.controller_for(run, battle_catalog, repository)
