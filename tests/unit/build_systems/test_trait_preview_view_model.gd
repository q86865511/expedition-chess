extends GutTest

## T10 / S4-AC-013 (specs/build-systems/design.md §8, HANDOFF.md §2) --
## TraitPreviewViewModel (presentation/viewmodels/trait_preview_view_model.gd,
## currently does not exist).
##
## Expected contract (test-author decision, wire contract not pinned by
## design.md beyond the read/write shape in §8's table -- see
## tests/fixtures/build_systems/view_model_test_fixture.gd header for the
## full rationale, including the two new RunController read accessors this
## suite requires: `roster_snapshot()` and `pending_reward_snapshot()`):
##   class_name TraitPreviewViewModel extends RefCounted
##   func _init(controller: RunController, catalog: BattleRuleCatalog,
##     compiler: BattleSetupSourceCompiler = null) -> void
##   func trait_snapshots() -> Array[TraitBattleSnapshot]
## No write API (design §8's ViewModel table lists "無（純預覽）" for this
## ViewModel's writes).
##
## `trait_snapshots()` must be produced by calling the same
## `BattleSetupSourceCompiler.compile(roster, catalog)` producer PREPARE-period
## combat entry uses (design §4/§8's "與實戰同源" requirement) -- so this suite
## asserts parity against a direct `BattleSetupSourceCompiler.new().compile()`
## call over the same roster/catalog, not just "returns something".

func test_trait_snapshots_matches_direct_compile_and_reports_active_tier() -> void:
	var run := ViewModelTestFixture.trait_preview_run()
	var catalog := ViewModelTestFixture.trait_battle_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	var controller := _controller_for(run, catalog)
	var view_model := TraitPreviewViewModel.new(controller, catalog)

	var snapshots := view_model.trait_snapshots()
	assert_eq(snapshots.size(), 1, "trait.pack 的兩個不同 def_id 上場棋應達門檻(2)產出一個 trait snapshot")
	if snapshots.size() != 1:
		return
	assert_eq(snapshots[0].trait_id, ViewModelTestFixture.TRAIT_ID)
	assert_eq(snapshots[0].tier, 1)
	assert_eq(snapshots[0].effect_assignments.size(), 1)
	assert_eq(snapshots[0].effect_assignments[0].effect_id, ViewModelTestFixture.TRAIT_EFFECT_ID)

	# 與實戰同源：直接呼叫 BattleSetupSourceCompiler.compile() 對照同一 roster/catalog
	# 的結果必須逐欄位相等 -- ViewModel 不得另生一套預覽邏輯。
	var direct := BattleSetupSourceCompiler.new().compile(run.roster_state, catalog)
	assert_eq(direct.player_active_traits.size(), snapshots.size())
	assert_eq(direct.player_active_traits[0].trait_id, snapshots[0].trait_id)
	assert_eq(direct.player_active_traits[0].tier, snapshots[0].tier)

func test_mutating_returned_trait_snapshots_does_not_affect_domain_or_later_reads() -> void:
	# 契約測試（design §8："ViewModel 不得直接改 draft、不得跨操作快取可變 domain
	# 物件"）：拿到的 trait_snapshots() 是獨立拷貝，改動它不得影響 domain 狀態，也不
	# 得影響下一次讀取的結果。
	var run := ViewModelTestFixture.trait_preview_run()
	var catalog := ViewModelTestFixture.trait_battle_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	var controller := _controller_for(run, catalog)
	var view_model := TraitPreviewViewModel.new(controller, catalog)

	var first := view_model.trait_snapshots()
	assert_eq(first.size(), 1)
	if first.size() != 1:
		return
	first[0].tier = 999
	first[0].member_instance_ids.append(&"u_injected")

	var second := view_model.trait_snapshots()
	assert_eq(second.size(), 1)
	if second.size() != 1:
		return
	assert_eq(second[0].tier, 1, "改動先前回傳的 snapshot 不應影響之後的讀取結果")
	assert_false(
		second[0].member_instance_ids.has(&"u_injected"),
		"改動先前回傳的 snapshot 不應污染之後的讀取結果"
	)
	# domain roster 本身(經由 controller 重新讀取)也不應被污染。
	var roster_after := controller.roster_snapshot()
	assert_eq(roster_after.unit_instances.size(), 2)

func test_trait_not_active_when_distinct_def_id_count_below_threshold() -> void:
	# S4-AC-001 讀端回歸：只有一個上場棋(unit.trait_a 重複)時,不同 def_id set size=1,
	# 未達門檻(2),trait 不應出現在 ViewModel 的預覽中。
	var run := ViewModelTestFixture.trait_preview_run()
	run.roster_state.unit_instances[1].def_id = ViewModelTestFixture.TRAIT_UNIT_A
	var catalog := ViewModelTestFixture.trait_battle_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	var controller := _controller_for(run, catalog)
	var view_model := TraitPreviewViewModel.new(controller, catalog)

	var snapshots := view_model.trait_snapshots()
	assert_eq(snapshots.size(), 0, "同 def_id 重複不應貢獻計數,未達門檻時不應產出 trait")

func _controller_for(run: RunState, catalog: BattleRuleCatalog) -> RunController:
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	return ViewModelTestFixture.controller_for(run, catalog, repository)
