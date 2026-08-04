extends GutTest

const BalanceProductionCaseDriverScript = preload(
	"res://application/balance/balance_production_case_driver.gd"
)


func test_production_case_driver_script_loads() -> void:
	assert_not_null(BalanceProductionCaseDriverScript)


func test_candidate_digest_is_order_independent_and_codec_round_trips() -> void:
	var entries: Array[BalanceTuneEntry] = [
		BalanceTuneEntry.new(&"economy.reroll_cost", "2"),
		BalanceTuneEntry.new(&"unit.alpha.health", "500"),
	]
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1, entries
	)
	var reversed: Array[BalanceTuneEntry] = [entries[1], entries[0]]
	var other := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1, reversed
	)
	assert_true(candidate.is_valid())
	assert_eq(candidate.tune_digest, other.tune_digest)
	assert_eq(candidate.candidate_id, other.candidate_id)
	assert_eq(
		String(candidate.candidate_id),
		"balance.g2.%s" % candidate.tune_digest.left(12)
	)
	var codec := BalanceCandidateCodecV1.new()
	var decoded := codec.try_decode(codec.encode(candidate))
	assert_not_null(decoded)
	assert_eq(decoded.tune_digest, candidate.tune_digest)
	var changed_entries: Array[BalanceTuneEntry] = [
		BalanceTuneEntry.new(&"economy.reroll_cost", "3"),
		BalanceTuneEntry.new(&"unit.alpha.health", "500"),
	]
	var changed := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1, changed_entries
	)
	assert_ne(changed.tune_digest, candidate.tune_digest)
	assert_ne(changed.candidate_id, candidate.candidate_id)


func test_candidate_rejects_duplicate_and_fixed_rule_fields() -> void:
	var duplicate: Array[BalanceTuneEntry] = [
		BalanceTuneEntry.new(&"economy.reroll_cost", "2"),
		BalanceTuneEntry.new(&"economy.reroll_cost", "3"),
	]
	assert_false(BalanceCandidateDescriptor.new(
		&"", "test", "b".repeat(64), 1, duplicate
	).is_valid())
	var fixed: Array[BalanceTuneEntry] = [
		BalanceTuneEntry.new(&"combat.tick_rate", "20"),
	]
	assert_false(BalanceCandidateDescriptor.new(
		&"", "test", "b".repeat(64), 1, fixed
	).is_valid())


func test_scanner_policy_is_shared_and_unknown_numeric_fields_fail_closed() -> void:
	assert_eq(
		BalanceTuneSourceScanner.FIXED_FIELDS,
		BalanceTuneFieldPolicy.FIXED_FIELDS
	)
	for field: String in ["soft_limit_ticks", "hard_limit_ticks", "basis_points", "overtime_interval_ticks"]:
		assert_true(BalanceTuneSourceScanner.FIXED_FIELDS.has(field), field)
	var accepted := BalanceTuneSourceScanner.scan_text(
		"res://probe.tres",
		"[gd_resource]\n[resource]\nschema_version = 2\ncells = 3\n"
	)
	assert_true(accepted.ok, accepted.error_detail)
	assert_eq(accepted.entries.size(), 1)
	assert_true(String(accepted.entries[0].field_path).ends_with(".cells"))
	var rejected := BalanceTuneSourceScanner.scan_text(
		"res://probe.tres", "[gd_resource]\n[resource]\nnew_power = 7\n"
	)
	assert_false(rejected.ok)
	assert_true(rejected.error_path.ends_with(".new_power"))
	var production := BalanceTuneSourceScanner.scan()
	assert_true(
		production.ok,
		"production TUNE scan: %s:%s" % [production.error_path, production.error_detail]
	)
	assert_gt(production.entries.size(), 0)


func test_pinned_production_candidate_matches_source_and_fails_closed() -> void:
	var scan := BalanceTuneSourceScanner.scan()
	assert_true(scan.ok, scan.error_detail)
	if not scan.ok:
		return
	var source_entries: Array[BalanceTuneEntry] = []
	source_entries.assign(scan.entries)
	var source_candidate := BalanceCandidateDescriptor.new(
		&"", "0.2.0-content-production",
		"923c6c11fddc0d1684f1f1f0da92a0990a922aef7ef1a2a30c93a92f90a00a60",
		BalanceCandidateDescriptor.RNG_VERSION,
		source_entries
	)
	var pinned := BalanceTuneInventory._load_pinned_candidate(
		source_candidate.manifest_digest, source_candidate.content_version
	)
	assert_true(pinned.is_valid())
	assert_eq(pinned.candidate_id, source_candidate.candidate_id)
	assert_eq(pinned.tune_digest, source_candidate.tune_digest)
	assert_eq(pinned.tune_entries.size(), source_candidate.tune_entries.size())
	assert_false(BalanceTuneInventory._load_pinned_candidate(
		"f".repeat(64), source_candidate.content_version
	).is_valid())
	assert_false(BalanceTuneInventory._load_pinned_candidate(
		source_candidate.manifest_digest, "wrong-content-version"
	).is_valid())


func test_candidate_archive_is_append_only_and_conflict_fails() -> void:
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "c".repeat(64), 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	var root := "user://balance-candidate-archive-test"
	var path := root.path_join("%s.json" % String(candidate.candidate_id))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(BalanceTuneInventory.archive_candidate(candidate, root), &"")
	assert_eq(BalanceTuneInventory.archive_candidate(candidate, root), &"")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string("conflict")
		file.close()
	assert_eq(
		BalanceTuneInventory.archive_candidate(candidate, root),
		&"BALANCE_CANDIDATE_ARCHIVE_CONFLICT"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_candidate_archive_preserves_same_tune_across_manifest_revisions() -> void:
	var entries: Array[BalanceTuneEntry] = [
		BalanceTuneEntry.new(&"economy.reroll_cost", "2"),
	]
	var first := BalanceCandidateDescriptor.new(
		&"", "test", "c".repeat(64), 1, entries
	)
	var revised := BalanceCandidateDescriptor.new(
		&"", "test", "d".repeat(64), 1, entries
	)
	assert_eq(first.candidate_id, revised.candidate_id)
	var root := "user://balance-candidate-manifest-revision-test"
	var flat_path := root.path_join("%s.json" % String(first.candidate_id))
	var revision_path := root.path_join("revisions").path_join(
		String(first.candidate_id)
	).path_join("%s.json" % revised.manifest_digest)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(flat_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(revision_path))
	assert_eq(BalanceTuneInventory.archive_candidate(first, root), &"")
	var revision_error := BalanceTuneInventory.archive_candidate(revised, root)
	assert_eq(revision_error, &"")
	if not revision_error.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(flat_path))
		return
	assert_true(FileAccess.file_exists(flat_path))
	assert_true(FileAccess.file_exists(revision_path))
	var codec := BalanceCandidateCodecV1.new()
	assert_eq(
		codec.try_decode(FileAccess.get_file_as_string(flat_path)).manifest_digest,
		first.manifest_digest
	)
	assert_eq(
		codec.try_decode(FileAccess.get_file_as_string(revision_path)).manifest_digest,
		revised.manifest_digest
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(flat_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(revision_path))


func test_strategies_choose_different_scores_and_stable_ties() -> void:
	var actions: Array[BalanceBotAction] = [
		BalanceBotAction.new(BalanceBotAction.Kind.BUY_UNIT, &"action.tempo", 1, 10, 0, 0),
		BalanceBotAction.new(BalanceBotAction.Kind.BUY_XP, &"action.economy", 1, 0, 10, 0),
		BalanceBotAction.new(BalanceBotAction.Kind.EQUIP, &"action.synergy", 1, 0, 0, 10),
	]
	var observation := BalanceBotObservation.new(10, 3, 100, 1, actions)
	assert_eq(BalanceBotStrategy.new(&"tempo").try_choose_action(observation).stable_id, &"action.tempo")
	assert_eq(BalanceBotStrategy.new(&"economy").try_choose_action(observation).stable_id, &"action.economy")
	assert_eq(BalanceBotStrategy.new(&"synergy").try_choose_action(observation).stable_id, &"action.synergy")
	var ties: Array[BalanceBotAction] = [
		BalanceBotAction.new(BalanceBotAction.Kind.HOLD, &"b", 0, 1, 1, 1),
		BalanceBotAction.new(BalanceBotAction.Kind.HOLD, &"a", 0, 1, 1, 1),
	]
	assert_eq(BalanceBotStrategy.new(&"tempo").try_choose_action(
		BalanceBotObservation.new(0, 1, 100, 1, ties)
	).stable_id, &"a")


func test_observation_and_selected_action_are_clone_only() -> void:
	var source := BalanceBotAction.new(
		BalanceBotAction.Kind.HOLD, &"hold", 0, 1, 1, 1
	)
	var source_actions: Array[BalanceBotAction] = [source]
	var observation := BalanceBotObservation.new(0, 1, 100, 1, source_actions)
	source.stable_id = &"mutated"
	var selected := BalanceBotStrategy.new(&"tempo").try_choose_action(observation)
	assert_eq(selected.stable_id, &"hold")
	selected.stable_id = &"caller_mutated"
	assert_eq(
		BalanceBotStrategy.new(&"tempo").try_choose_action(observation).stable_id,
		&"hold"
	)


func test_illegal_and_unaffordable_actions_are_rejected() -> void:
	var actions: Array[BalanceBotAction] = [
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_UNIT, &"illegal", 0, 999, 999, 999, false
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_UNIT, &"unaffordable", 11, 999, 999, 999
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.HOLD, &"legal", 0, 1, 1, 1
		),
	]
	var chosen := BalanceBotStrategy.new(&"tempo").try_choose_action(
		BalanceBotObservation.new(10, 1, 100, 1, actions)
	)
	assert_not_null(chosen)
	assert_eq(chosen.stable_id, &"legal")


func test_economy_policy_fills_board_then_spends_only_above_max_interest() -> void:
	assert_eq(BalanceProductionCaseDriverScript.economy_hold_score(2, 3), 0)
	assert_eq(BalanceProductionCaseDriverScript.economy_hold_score(3, 3), 120)
	assert_false(BalanceProductionCaseDriverScript.economy_xp_allowed(
		53, 4, 10, 1, 5, 3, 3
	))
	assert_true(BalanceProductionCaseDriverScript.economy_xp_allowed(
		54, 4, 10, 1, 5, 3, 3
	))
	assert_false(BalanceProductionCaseDriverScript.economy_xp_allowed(
		99, 4, 10, 1, 5, 2, 3
	), "未鋪滿目前人口時必須先買單位，不得繼續買 XP")
	assert_eq(
		BalanceProductionCaseDriverScript.economy_reroll_score(2, 3, true), -40,
		"已有可負擔單位時不得用 refresh 蓋過 BUY_UNIT"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.economy_reroll_score(2, 3, false), 40,
		"人口不足且沒有可負擔單位時才允許尋找商店"
	)


func test_build_attribution_requires_active_faction_and_tie_is_run_bound() -> void:
	assert_eq(BalanceProductionCaseDriverScript.build_id_from_trait_counts({
		&"trait.faction_arcane": 1,
		&"trait.role_vanguard": 3,
	}, &"run-a"), &"build.none")
	var tied := {
		&"trait.faction_arcane": 2,
		&"trait.faction_verdant": 2,
		&"trait.role_vanguard": 9,
	}
	var first: StringName = BalanceProductionCaseDriverScript.build_id_from_trait_counts(
		tied, &"run-a"
	)
	assert_true(first in [
		&"build.trait.trait.faction_arcane",
		&"build.trait.trait.faction_verdant",
	])
	assert_eq(
		BalanceProductionCaseDriverScript.build_id_from_trait_counts(tied, &"run-a"),
		first,
		"同 run_id 平手歸因必須決定性"
	)


func test_appendix_c_tune_values_are_exact() -> void:
	var verdant_text := FileAccess.get_file_as_string(
		"res://content/packs/build_systems/effects/trait_faction_verdant.tres"
	).replace("\r\n", "\n")
	assert_true(verdant_text.contains("amount = 20"))
	var economy_text := FileAccess.get_file_as_string(
		"res://content/packs/vertical_slice/economy_configs/slice_default.tres"
	).replace("\r\n", "\n")
	var expected: Array[String] = [
		"10000, 0, 0, 0, 0", "10000, 0, 0, 0, 0",
		"7500, 2500, 0, 0, 0", "7500, 2500, 0, 0, 0",
		"5500, 3000, 1500, 0, 0", "5500, 3000, 1500, 0, 0",
		"3500, 3500, 2000, 1000, 0", "3500, 3500, 2000, 1000, 0",
		"2500, 3000, 2500, 1500, 500",
	]
	for index: int in range(expected.size()):
		assert_true(economy_text.contains(
			"level = %d\ntier_basis_points = Array[int]([%s])" % [
				index + 1, expected[index],
			]
		), "level %d 商店機率必須符合附錄 C" % (index + 1))
	var verdant := load(
		"res://content/packs/build_systems/effects/trait_faction_verdant.tres"
	) as EffectDef
	var economy := load(
		"res://content/packs/vertical_slice/economy_configs/slice_default.tres"
	) as EconomyConfigDef
	assert_not_null(verdant)
	assert_not_null(economy)
	assert_eq((verdant.battle_operations[0] as ShieldOperationDef).amount, 20)
	assert_eq(economy.shop_odds_by_level[0].level, 1)
