extends GutTest

const BalanceProductionCaseDriverScript = preload(
	"res://application/balance/balance_production_case_driver.gd"
)


func test_production_case_driver_script_loads() -> void:
	assert_not_null(BalanceProductionCaseDriverScript)


func test_reward_proof_is_serial_free_and_flags_true_duplicate() -> void:
	# F09: the ledger-based reward proof was structurally incapable of ever
	# repeating (every reward transaction key embeds next_transaction_serial), so
	# BALANCE_DUPLICATE_REWARD could never fire. This exercises the replacement
	# node+stage+step proof built by _reward_intent directly: two CHOOSING
	# intents for the same node/stage — simulating "the same node's reward chain
	# ran twice" — must collide even though their generated offers carry
	# different serial-derived choice_ids, while a genuinely different node must
	# not collide.
	var driver: RefCounted = BalanceProductionCaseDriverScript.new(null, Callable())
	var result := BalanceBotCaseResult.new()
	result.final_phase = &"RESULTS"
	var replay_parts: Array[String] = []

	var first_key := TransactionKeyState.create(
		&"run-dup", &"node-1", &"reward_generate", U64Bits.one(), &"key-digest-a"
	)
	var first_offer := RewardOfferState.new(
		"choice_standard_1_0", RewardOfferState.RewardKind.GOLD, null, 10, null, "digest-a"
	)
	var first_snapshot := RunPresentationSnapshot.new()
	first_snapshot.pending_reward = PendingRewardState.new(
		"node-1", PendingRewardState.StageId.STANDARD, PendingRewardState.Phase.CHOOSING,
		[first_offer] as Array[RewardOfferState], [] as Array[ReservedCopyState],
		null, null, first_key
	)
	driver._reward_intent(first_snapshot, BalanceBotStrategy.TEMPO, result, replay_parts)

	var second_key := TransactionKeyState.create(
		&"run-dup", &"node-1", &"reward_generate",
		U64Bits.one().add(U64Bits.one()), &"key-digest-b"
	)
	var second_offer := RewardOfferState.new(
		"choice_standard_9_0", RewardOfferState.RewardKind.GOLD, null, 10, null, "digest-b"
	)
	var second_snapshot := RunPresentationSnapshot.new()
	second_snapshot.pending_reward = PendingRewardState.new(
		"node-1", PendingRewardState.StageId.STANDARD, PendingRewardState.Phase.CHOOSING,
		[second_offer] as Array[RewardOfferState], [] as Array[ReservedCopyState],
		null, null, second_key
	)
	driver._reward_intent(second_snapshot, BalanceBotStrategy.TEMPO, result, replay_parts)

	assert_eq(result.reward_receipt_digests.size(), 2)
	assert_eq(
		result.reward_receipt_digests[0], result.reward_receipt_digests[1],
		"同節點同 stage 的重複 choose 必須產生相同 proof"
	)
	driver._validate_case_proof(result)
	assert_true(
		result.failure_codes.has(&"BALANCE_DUPLICATE_REWARD"),
		"同節點同 stage 的重複 reward 鏈必須觸發 BALANCE_DUPLICATE_REWARD"
	)

	var other_result := BalanceBotCaseResult.new()
	other_result.final_phase = &"RESULTS"
	var other_replay_parts: Array[String] = []
	var other_key := TransactionKeyState.create(
		&"run-dup", &"node-2", &"reward_generate", U64Bits.one(), &"key-digest-c"
	)
	var other_offer := RewardOfferState.new(
		"choice_standard_1_0", RewardOfferState.RewardKind.GOLD, null, 10, null, "digest-c"
	)
	var other_snapshot := RunPresentationSnapshot.new()
	other_snapshot.pending_reward = PendingRewardState.new(
		"node-2", PendingRewardState.StageId.STANDARD, PendingRewardState.Phase.CHOOSING,
		[other_offer] as Array[RewardOfferState], [] as Array[ReservedCopyState],
		null, null, other_key
	)
	driver._reward_intent(first_snapshot, BalanceBotStrategy.TEMPO, other_result, other_replay_parts)
	driver._reward_intent(other_snapshot, BalanceBotStrategy.TEMPO, other_result, other_replay_parts)
	driver._validate_case_proof(other_result)
	assert_false(
		other_result.failure_codes.has(&"BALANCE_DUPLICATE_REWARD"),
		"不同節點的合法 reward 選擇不得被誤判為重複"
	)


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


func test_scanner_fails_closed_on_unclosed_tracked_field_continuation_line() -> void:
	# A tracked field (tier_basis_points) whose Array literal is not closed on the
	# same line simulates the Godot editor wrapping a long array across lines.
	# scan_text parses line-by-line, so the continuation line's real values would
	# otherwise be silently dropped and the truncated first line written into the
	# digest as if it were complete (F06). Assert fail-closed instead.
	var rejected := BalanceTuneSourceScanner.scan_text(
		"res://probe_multiline.tres",
		"[gd_resource]\n[resource]\ntier_basis_points = Array[int]([\n10000, 0, 0, 0, 0\n])\n"
	)
	assert_false(rejected.ok)
	assert_true(rejected.error_path.ends_with(".tier_basis_points"), rejected.error_path)
	# A same-line (closed) array on a tracked field must still scan normally.
	var accepted := BalanceTuneSourceScanner.scan_text(
		"res://probe_singleline.tres",
		"[gd_resource]\n[resource]\ntier_basis_points = Array[int]([10000, 0, 0, 0, 0])\n"
	)
	assert_true(accepted.ok, accepted.error_detail)
	assert_eq(accepted.entries.size(), 1)


func test_pinned_production_constants_match_scanner_computed_digest() -> void:
	# F02: the sealed RC constants must equal what the scanner computes fresh
	# from the current source tree, independent of production_balance_candidate.json
	# and independent of the two constants being merely self-consistent with each
	# other. This pins the export path to the actual TUNE source, not just to a
	# committed sealed payload that could silently drift from it.
	var scan := BalanceTuneSourceScanner.scan()
	assert_true(scan.ok, scan.error_detail)
	if not scan.ok:
		return
	var source_entries: Array[BalanceTuneEntry] = []
	source_entries.assign(scan.entries)
	var computed := BalanceCandidateDescriptor.new(
		&"", "probe", "a".repeat(64),
		BalanceCandidateDescriptor.RNG_VERSION, source_entries
	)
	assert_eq(
		BalanceTuneInventory.PINNED_PRODUCTION_TUNE_DIGEST, computed.tune_digest,
		"sealed PINNED_PRODUCTION_TUNE_DIGEST 必須等於 scanner 對本 source tree 實算的 tune_digest"
	)
	assert_eq(
		String(BalanceTuneInventory.PINNED_PRODUCTION_CANDIDATE_ID), String(computed.candidate_id),
		"sealed PINNED_PRODUCTION_CANDIDATE_ID 必須等於實算 tune_digest 衍生的 candidate_id"
	)


func test_pinned_production_candidate_matches_source_and_fails_closed() -> void:
	var scan := BalanceTuneSourceScanner.scan()
	assert_true(scan.ok, scan.error_detail)
	if not scan.ok:
		return
	var source_entries: Array[BalanceTuneEntry] = []
	source_entries.assign(scan.entries)
	var source_candidate := BalanceCandidateDescriptor.new(
		&"", "0.2.0-content-production",
		"f7bc9df62ba8f6306a54272fd599157ad3a5913f3f3fc659475b3379c777de64",
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


## G2 difficulty-curve 第二個評分退化修復：bench_pressure_score 是純函式，
## 只有「板面已滿（unit_count >= level）且板凳真的有溢出戰力（>=2 隻卡住待部署）」
## 才給 BUY_XP 加成；單一隻溢出（正常換血雜訊）與板面未滿都不算數。
func test_bench_pressure_score_requires_full_board_and_at_least_two_overflow_units() -> void:
	assert_eq(
		BalanceProductionCaseDriverScript.bench_pressure_score(0, 0, 1), 0,
		"空板開局不得有加成"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.bench_pressure_score(3, 1, 3), 0,
		"板面尚未鋪滿（unit_count < level）時不得有加成"
	)
	assert_eq(
		BalanceProductionCaseDriverScript.bench_pressure_score(1, 4, 3), 0,
		"只有 1 隻溢出時不算真正的板凳壓力"
	)
	assert_gt(
		BalanceProductionCaseDriverScript.bench_pressure_score(2, 5, 3), 0,
		"板滿且溢出 >=2 隻時必須加成"
	)
	assert_gt(
		BalanceProductionCaseDriverScript.bench_pressure_score(4, 7, 3),
		BalanceProductionCaseDriverScript.bench_pressure_score(2, 5, 3),
		"溢出戰力越多，加成必須越大"
	)


## 性質 (a)：存在可達狀態（板凳溢出 4 隻）使 tempo 的 BUY_XP 贏過即使是很強的
## BUY_UNIT（cost_tier 5、免費、3 特質）——修復「tempo 永遠不買 XP」的退化。
func test_tempo_buys_xp_when_bench_pressure_is_high() -> void:
	var pressure := BalanceProductionCaseDriverScript.bench_pressure_score(4, 7, 3)
	assert_gt(pressure, 0, "前提：本測試狀態必須真的觸發板凳壓力")
	var actions: Array[BalanceBotAction] = [
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_UNIT, &"action.strong_unit", 0,
			100 + 5 * 20, 20, 3 * 30
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.REROLL, &"action.refresh_shop", 2, 80, 40, 35
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_XP, &"action.buy_xp", 4,
			40 + pressure, 90 + pressure, 20 + pressure
		),
	]
	var chosen := BalanceBotStrategy.new(BalanceBotStrategy.TEMPO).try_choose_action(
		BalanceBotObservation.new(100, 3, 100, 1, actions)
	)
	assert_eq(
		chosen.stable_id, &"action.buy_xp",
		"板凳有明顯溢出戰力時 tempo 也必須被說服買經驗，不能永遠不買"
	)


## 性質 (b)：空板開局（沒有溢出戰力，加成為 0）時 BUY_XP 不得壓過 BUY_UNIT——
## 不能反向退化成「先升級不鋪場」。
func test_tempo_still_prioritizes_buy_unit_on_empty_board() -> void:
	var pressure := BalanceProductionCaseDriverScript.bench_pressure_score(0, 0, 1)
	assert_eq(pressure, 0, "前提：空板開局不得有加成")
	var actions: Array[BalanceBotAction] = [
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_UNIT, &"action.opening_unit", 2, 120, -80, 30
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_XP, &"action.buy_xp", 4,
			40 + pressure, 90 + pressure, 20 + pressure
		),
	]
	var chosen := BalanceBotStrategy.new(BalanceBotStrategy.TEMPO).try_choose_action(
		BalanceBotObservation.new(10, 1, 100, 1, actions)
	)
	assert_eq(
		chosen.stable_id, &"action.opening_unit",
		"空板開局不得反向退化成優先買經驗、不鋪場"
	)


## 性質 (c)：同一個板凳壓力狀態下，tempo／economy／synergy 三策略的完整偏好
## 排序仍然互異——本次修復只解退化，不得抹平策略身分差異。
func test_three_strategies_rank_actions_differently_under_shared_bench_pressure() -> void:
	var pressure := BalanceProductionCaseDriverScript.bench_pressure_score(2, 5, 3)
	assert_gt(pressure, 0, "前提：本測試狀態必須真的觸發板凳壓力")
	var base_actions: Array[BalanceBotAction] = [
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_UNIT, &"action.cheap_tempo_unit", 5, 120, -5, 0
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.BUY_UNIT, &"action.trait_unit", 20, 120, -80, 125
		),
		BalanceBotAction.new(
			BalanceBotAction.Kind.REROLL, &"action.refresh_shop", 2, 80, -40, 35
		),
	]
	var tempo_actions: Array[BalanceBotAction] = base_actions.duplicate()
	tempo_actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.BUY_XP, &"action.buy_xp", 4,
		40 + pressure, 90 + pressure, 20 + pressure
	))
	var synergy_actions: Array[BalanceBotAction] = base_actions.duplicate()
	synergy_actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.BUY_XP, &"action.buy_xp", 4,
		40 + pressure, 90 + pressure, 20 + pressure
	))
	var economy_actions: Array[BalanceBotAction] = base_actions.duplicate()
	economy_actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.BUY_XP, &"action.buy_xp", 4,
		40 + pressure, 150 + pressure, 20 + pressure
	))

	var tempo_order := _ranked_ids(BalanceBotStrategy.new(BalanceBotStrategy.TEMPO), tempo_actions)
	var economy_order := _ranked_ids(
		BalanceBotStrategy.new(BalanceBotStrategy.ECONOMY), economy_actions
	)
	var synergy_order := _ranked_ids(
		BalanceBotStrategy.new(BalanceBotStrategy.SYNERGY), synergy_actions
	)

	assert_ne(tempo_order, economy_order, "tempo 與 economy 的完整偏好排序必須不同")
	assert_ne(tempo_order, synergy_order, "tempo 與 synergy 的完整偏好排序必須不同")
	assert_ne(economy_order, synergy_order, "economy 與 synergy 的完整偏好排序必須不同")


## 依序移除最高分動作、重複呼叫 try_choose_action，還原策略對整批動作的完整排序。
func _ranked_ids(
	strategy: BalanceBotStrategy, source: Array[BalanceBotAction]
) -> Array[StringName]:
	var remaining: Array[BalanceBotAction] = []
	remaining.assign(source)
	var order: Array[StringName] = []
	while not remaining.is_empty():
		var chosen := strategy.try_choose_action(
			BalanceBotObservation.new(1000, 3, 100, 1, remaining)
		)
		if chosen == null:
			break
		order.append(chosen.stable_id)
		for index: int in range(remaining.size()):
			if remaining[index].stable_id == chosen.stable_id:
				remaining.remove_at(index)
				break
	return order


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
