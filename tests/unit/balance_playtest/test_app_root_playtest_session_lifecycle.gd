extends GutTest

## balance-playtest Phase 0 收尾雙審修正：B-02（跨行程棄置無報告）、B-08（session id
## 未清導致誤標 abandoned）、F03（RC candidate invalid 靜默無報告）、B-09（破壞性 smoke
## 參數無確認即可執行）。四項都掛在 `app/app_root.gd` 既有的 playtest session／棄置流程上。

const Support = preload("res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd")
const PENDING_PATH: String = "user://playtest_session/.pending-session.json"
const MARKER_PATH: String = "user://playtest_reports/.candidate-invalid.err"


func before_each() -> void:
	# 這幾個檔案是本機真實 user:// 目錄（不是 FakeSaveStorage 能隔離的範圍），先清乾淨
	# 避免上一次失敗的測試殘留影響本次判定。
	_remove_absolute(PENDING_PATH)
	_remove_absolute(MARKER_PATH)


func after_each() -> void:
	# GUT 的 error_tracker 是 process 全域單例（GutUtils.get_error_tracker()），不會隨
	# 測試切換自動重置；test_report_playtest_candidate_invalid_writes_marker_and_logs_error
	# 會暫時放行預期中的 push_error，這裡確保不論該測試通過與否都還原，不外洩到後續測試。
	gut.error_tracker.treat_push_error_as = GutUtils.TREAT_AS.FAILURE
	_remove_absolute(PENDING_PATH)
	_remove_absolute(MARKER_PATH)


## B-02：session 開始後行程「重啟」（記憶體 session id 遺失，sidecar 留存），
## 之後在主選單明示棄置 retained run 必須補發一份 outcome=abandoned 報告，並清掉 sidecar。
func test_cross_process_abandon_recovers_report_from_pending_sidecar() -> void:
	var storage := FakeSaveStorage.new()
	var harness: Variant = Support.boot(self, storage)
	var root: ApplicationRoot = harness.root
	if not _compose_active_run(root):
		return

	var session_id: String = root._playtest_session_id
	assert_false(session_id.is_empty(), "playtest session must begin on successful compose")
	assert_true(FileAccess.file_exists(PENDING_PATH), "sidecar must be written at session start")

	# 模擬跨行程放棄：行程記憶體遺失（等同重啟後的全新行程），sidecar 仍留在本機磁碟。
	root._playtest_session_id = ""

	var returned: AppActionResult = root.return_to_menu()
	assert_true(returned.ok, String(returned.error.code) if not returned.ok else "ok")
	if not returned.ok:
		return
	var loaded: LoadResult = root._save_repository.load()
	assert_true(loaded.ok and loaded.run != null)
	if not (loaded.ok and loaded.run != null):
		return
	var token: RetainedRunRecoveryToken = root._retained_run_recovery_service.issue_token(
		loaded, StringName(loaded.run.run_id)
	)
	assert_not_null(token)
	if token == null:
		return

	var discarded: AppActionResult = root.discard_retained_run(token)
	assert_true(discarded.ok, String(discarded.error.code) if not discarded.ok else "ok")
	if not discarded.ok:
		return

	assert_false(
		FileAccess.file_exists(PENDING_PATH),
		"pending sidecar must be cleared once the abandoned report is recovered"
	)
	var report_path := "user://playtest_reports/session-%s.json" % session_id
	assert_true(
		FileAccess.file_exists(report_path),
		"B-02: cross-process abandon must recover a report from the sidecar"
	)
	var report := PlaytestSessionReportCodecV1.new().try_decode(
		FileAccess.get_file_as_string(report_path)
	)
	assert_not_null(report)
	if report != null:
		assert_eq(report.session_id, session_id)
		assert_eq(String(report.outcome), "abandoned")
	_remove_absolute(report_path)


## B-08：fail-closed terminal handoff（receipt 為 null）到達時必須立即清 session
## 狀態（含 sidecar），否則之後的棄置會沿用同一個 session id 誤標成 abandoned。
func test_null_receipt_terminal_handoff_clears_session_state_without_writing_a_report() -> void:
	var storage := FakeSaveStorage.new()
	var harness: Variant = Support.boot(self, storage)
	var root: ApplicationRoot = harness.root
	if not _compose_active_run(root):
		return

	var session_id: String = root._playtest_session_id
	assert_false(session_id.is_empty())
	assert_true(FileAccess.file_exists(PENDING_PATH))

	var snapshot := ResultsPresentationSnapshot.new()
	snapshot.run_id = &"run.b08-null-receipt-test"
	snapshot.receipt = null
	root._write_playtest_session_report(snapshot)

	assert_eq(
		root._playtest_session_id, "",
		"B-08: reaching terminal must clear the session id even without a receipt"
	)
	assert_false(
		FileAccess.file_exists(PENDING_PATH),
		"B-08: reaching terminal must clear the pending sidecar too"
	)
	var report_path := "user://playtest_reports/session-%s.json" % session_id
	assert_false(
		FileAccess.file_exists(report_path),
		"no outcome can be determined without a receipt; no report should be written"
	)


## F03：provisional_rc 匯出時 candidate invalid 必須留下可被發現的訊號（錯誤標記檔），
## 而不是整批 playtest 靜默不寫任何報告。OS.has_feature("provisional_rc") 在編輯器/測試
## 行程恆為 false，所以直接測「候選失效時的回報動作」本體，並用原始碼比對確認
## `_begin_playtest_session` 確實在該 feature 下呼叫它。
func test_report_playtest_candidate_invalid_writes_marker_and_logs_error() -> void:
	var storage := FakeSaveStorage.new()
	var harness: Variant = Support.boot(self, storage)
	var root: ApplicationRoot = harness.root

	assert_false(FileAccess.file_exists(MARKER_PATH))
	# _report_playtest_candidate_invalid() 故意 push_error（讓失效可被發現）；GUT 把
	# push_error 是否算失敗的判定延到本測試函式整個返回之後才讀取旗標，所以不能在函式內
	# 提前還原——這裡放行到 after_each() 才收回（見上方 after_each 的說明）。
	gut.error_tracker.treat_push_error_as = GutUtils.TREAT_AS.NOTHING
	root._report_playtest_candidate_invalid()
	assert_true(FileAccess.file_exists(MARKER_PATH))
	var text := FileAccess.get_file_as_string(MARKER_PATH)
	assert_true(text.contains("BALANCE_CANDIDATE_INVALID"))


func test_begin_playtest_session_wires_candidate_invalid_marker_to_provisional_rc_feature() -> void:
	var source := Support.source("res://app/app_root.gd")
	assert_true(source.contains("OS.has_feature(\"provisional_rc\")"))
	assert_true(
		source.contains("elif OS.has_feature(\"provisional_rc\"):")
		and source.contains("_report_playtest_candidate_invalid()"),
		"F03: invalid candidate under provisional_rc must be reported, not silently dropped"
	)


## B-09：唯一具破壞性的 phase（restart-abandon-verify，會不可逆棄置 retained run）
## 缺少 --rc-smoke-confirm 時必須拒絕；其餘 phase 或帶了確認旗標則不受影響。
func test_rc_smoke_confirm_required_only_for_destructive_phase_without_confirm_flag() -> void:
	assert_true(
		ApplicationRoot._rc_smoke_confirm_required(
			&"restart-abandon-verify",
			PackedStringArray(["--rc-smoke-phase=restart-abandon-verify"])
		)
	)
	assert_false(
		ApplicationRoot._rc_smoke_confirm_required(
			&"restart-abandon-verify",
			PackedStringArray([
				"--rc-smoke-phase=restart-abandon-verify", "--rc-smoke-confirm",
			])
		),
		"presence of --rc-smoke-confirm must lift the gate"
	)
	assert_false(
		ApplicationRoot._rc_smoke_confirm_required(
			&"start-save", PackedStringArray(["--rc-smoke-phase=start-save"])
		),
		"non-destructive phases are never gated"
	)
	assert_false(
		ApplicationRoot._rc_smoke_confirm_required(
			&"restart-terminal", PackedStringArray(["--rc-smoke-phase=restart-terminal"])
		)
	)


func _compose_active_run(root: ApplicationRoot) -> bool:
	var opened: AppActionResult = root.open_camp()
	assert_true(opened.ok, "run-free MENU must be able to enter CAMP")
	if not opened.ok:
		return false
	var commander_id: StringName = _first_commander(root)
	assert_ne(commander_id, &"")
	if commander_id.is_empty():
		return false
	var started: AppActionResult = root.start_expedition(
		StartExpeditionRequest.new(commander_id, 0)
	)
	assert_true(started.ok, String(started.error.code) if not started.ok else "ok")
	if not started.ok:
		return false
	assert_eq(root.app_state(), AppStateMachine.State.RUN)
	return root.app_state() == AppStateMachine.State.RUN


func _first_commander(root: ApplicationRoot) -> StringName:
	var view_model: CampViewModel = root.try_camp_view_model()
	if view_model == null:
		return &""
	var commanders: Array[StringName] = view_model.commander_hall_unlocked_commander_ids()
	return commanders[0] if not commanders.is_empty() else &""


func _remove_absolute(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
