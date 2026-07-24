extends GutTest

## T09 (specs/meta-progression/design.md §8; tasks.md T09 驗收:
## "RunDiscoveryLog.mark 於四類事件... command apply 內 append"):
## RunDiscoveryLog 是四類發現事件(上場/購得棋子、商店出現、遭遇敵人、
## 取得裝備/遺物)共用的 helper -- 純函式式地把一個 content_id 併入
## draft.discovered_content_ids(union、單調、保持 sorted+unique,呼應
## run_state_validator.gd 對此欄位的 sorted+unique 強制要求,見
## tests/unit/meta_progression/test_run_state_validator_meta_progression_fields.gd
## 的 test_run_rejects_duplicate_discovered_content_ids／
## test_run_rejects_discovered_content_ids_out_of_canonical_order)。
##
## 這裡只測 helper 本身的純函式行為;個別 command 的掛點
## (BuyOfferCommand/RefreshShopCommand/EnterNodeEvent/CommitBoardLayoutCommand/
## ForgeEquipmentCommand/ChooseRewardCommand)由
## tests/integration/run_controller/test_discovery_log_marking.gd 覆蓋。
##
## Wire 契約(design.md 只給了呼叫形狀 "RunDiscoveryLog.mark(draft, content_id)",
## 未進一步釘選回傳型別 -- 依 commit_board_layout_command.gd 等既有 command
## 直接原地改 draft 欄位再 return draft 的既有慣例,本測試假設 mark() 為
## `static func mark(draft: RunState, content_id: StringName) -> void`,
## 直接原地 mutate draft.discovered_content_ids,不回傳新物件)。
##
## RunDiscoveryLog 這個 class_name 目前不存在。若直接在頂層寫
## `RunDiscoveryLog.mark(...)`,GDScript 靜態解析會在「載入這個測試腳本」
## 當下就丟出 Parse Error,而 GUT 對載入失敗的腳本是整檔靜默排除、不計入
## 失敗數(exit code 仍為 0,tests 總數也不含這個檔案的任何一條)-- 這樣
## 反而看不出紅燈。改用 load() 動態載入:檔案不存在時 load() 在執行期回傳
## null(不是 Parse Error),讓 assert_not_null() 成為一個會被 GUT 正確計入
## 失敗數的斷言;RunDiscoveryLog 一旦存在,同一份測試會改走 script.call(...)
## 動態呼叫其 mark() 靜態方法,驗證實際行為。

const SCRIPT_PATH := "res://domain/run/run_discovery_log.gd"


func test_mark_appends_new_content_id_in_sorted_order() -> void:
	var script := _load_script()
	if script == null: return
	var run := SaveRootFixture.create_valid_root().run
	run.discovered_content_ids = [&"relic.alpha"]
	script.call("mark", run, &"unit.fixture")
	assert_eq(run.discovered_content_ids, [&"relic.alpha", &"unit.fixture"])


func test_mark_inserts_before_a_lexically_later_existing_id() -> void:
	var script := _load_script()
	if script == null: return
	var run := SaveRootFixture.create_valid_root().run
	run.discovered_content_ids = [&"unit.fixture"]
	script.call("mark", run, &"relic.alpha")
	assert_eq(run.discovered_content_ids, [&"relic.alpha", &"unit.fixture"])


func test_mark_is_idempotent_when_content_id_already_present() -> void:
	var script := _load_script()
	if script == null: return
	var run := SaveRootFixture.create_valid_root().run
	run.discovered_content_ids = [&"unit.fixture"]
	script.call("mark", run, &"unit.fixture")
	assert_eq(run.discovered_content_ids, [&"unit.fixture"])
	assert_eq(run.discovered_content_ids.size(), 1)


func test_mark_on_empty_ledger_produces_single_entry() -> void:
	var script := _load_script()
	if script == null: return
	var run := SaveRootFixture.create_valid_root().run
	var empty: Array[StringName] = []
	run.discovered_content_ids = empty
	script.call("mark", run, &"commander.fixture")
	assert_eq(run.discovered_content_ids, [&"commander.fixture"])


func test_mark_does_not_mutate_rng_stream_states() -> void:
	# S5-AC-012 / design.md §8: "純 append 不消耗 RNG、不改 draw 序" -- at the
	# level of this pure helper, marking discovery must never touch any RNG
	# stream snapshot. The full "不改 draw 序" guarantee across real shop/
	# reward RNG draws is verified separately by re-running the existing
	# -Suite Expedition determinism regression after implementation (not
	# expressible as a single new GUT assertion) -- see this task's
	# untestable list.
	var script := _load_script()
	if script == null: return
	var run := SaveRootFixture.create_valid_root().run
	var before: Array[String] = []
	for state: NamedRngState in run.rng_stream_states:
		before.append(state.snapshot.counter.to_hex())
	script.call("mark", run, &"unit.fixture")
	var after: Array[String] = []
	for state: NamedRngState in run.rng_stream_states:
		after.append(state.snapshot.counter.to_hex())
	assert_eq(after, before)


func test_mark_result_still_satisfies_run_state_validator() -> void:
	# Guards against a helper that appends without keeping the canonical
	# sorted+unique invariant the validator enforces (run_state_validator.gd
	# rejects out-of-order or duplicate discovered_content_ids).
	var script := _load_script()
	if script == null: return
	var run := SaveRootFixture.create_valid_root().run
	run.discovered_content_ids = [&"commander.fixture"]
	script.call("mark", run, &"unit.fixture")
	script.call("mark", run, &"relic.alpha")
	var result := RunStateValidator.new().validate_run(run)
	assert_true(result.ok, String(result.error.field_path) if not result.ok else "")


## Loads domain/run/run_discovery_log.gd dynamically so a not-yet-existing
## class produces a normal, GUT-countable failing assertion (load() -> null
## at runtime) instead of a script-load Parse Error that silently excludes
## the whole file from the run (see header comment).
func _load_script() -> GDScript:
	var script := load(SCRIPT_PATH) as GDScript
	assert_not_null(
		script,
		"RunDiscoveryLog (%s) must exist and expose a static `mark(draft, content_id)`" % SCRIPT_PATH
	)
	return script
