extends GutTest

## 第二意見審查 Blocker 1／2 回歸：node-choice receipt 與 transaction／node service
## 之間的綁定不能只靠「digest 存在」。
##
## B1：receipt.transaction_digest 只證明「有這麼一筆 transaction」。竄改者可以把它
##     指向任何一筆既有 transaction 再重算 NCR1；validator 若收下，
##     CommitNodeChoiceService._has_committed_receipt 會對合法 commit 誤回
##     ALREADY_COMMITTED（commit_node_choice_service.gd:99），run 直接卡死。
## B2：NodeServicePendingResolutionState 只有 dismantle 一種合法 service_kind，而且
##     它引用的 receipt 必須就是「開出這個服務的那一筆」——節點與 outcome 都要對得上，
##     current_node_id 也要是同一個節點，否則 ExitNodeServiceCommand 會完成錯的節點。

const COMMIT_COMMAND_KIND: StringName = &"commit_node_choice"
const FOREIGN_NODE_ID: StringName = &"node_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const FOREIGN_RUN_ID: StringName = &"run_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const UNKNOWN_TRANSACTION_DIGEST: String = "transaction_cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
const UNKNOWN_RECEIPT_DIGEST: String = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
const FOREIGN_PAYLOAD_DIGEST: String = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"


func test_committed_dismantle_service_run_is_the_valid_baseline() -> void:
	var run := _committed_run()
	assert_eq(_failure_path(run), "")


# --- B1：receipt ↔ transaction 的逐欄綁定 -------------------------------------

func test_receipt_pointing_at_a_foreign_transaction_is_rejected() -> void:
	var run := _committed_run()
	# 攻擊：另外偽造（或重用）一筆非 commit_node_choice 的 transaction，把 receipt
	# 指過去並重算 NCR1——digest 存在性檢查會通過，逐欄綁定不會。
	_repoint_receipt_at_built_transaction(
		run,
		StringName(run.run_id),
		NodeChoiceServiceFixture.current_node_id(run),
		&"buy_offer",
		run.next_transaction_serial
	)
	assert_true(
		_receipt(run).is_valid(),
		"攻擊 payload 本身必須是合法 NCR1，否則測不到綁定"
	)
	assert_eq(_failure_path(run), "run.node_choice_receipts.transaction_binding")


## 以下四案的竄改都必須「只」違反 receipt↔key 的逐欄綁定：就地改 key 欄位會先被
## _receipts_sorted 的 _runtime_key→reencode_state（digest 自洽檢查，失敗路徑
## run.ledgers）擋掉，測不到新分支。所以一律真的用 RuntimeKeySchemaRegistry 編出
## 一把合法的 transaction key（digest 自洽、排序正確、payload_digest 也補成合法值），
## 只讓其中一個 token 與 receipt 對不上——上游只驗 key 自身，這裡才是第二道防線。
func test_transaction_command_kind_mismatch_is_rejected() -> void:
	var run := _committed_run()
	_repoint_receipt_at_built_transaction(
		run,
		StringName(run.run_id),
		_receipt(run).node_id,
		&"buy_offer",
		_committed_serial(run)
	)
	assert_eq(_failure_path(run), "run.node_choice_receipts.transaction_binding")


func test_transaction_serial_mismatch_is_rejected() -> void:
	var run := _committed_run()
	_repoint_receipt_at_built_transaction(
		run,
		StringName(run.run_id),
		_receipt(run).node_id,
		COMMIT_COMMAND_KIND,
		_committed_serial(run).add(U64Bits.one())
	)
	assert_eq(_failure_path(run), "run.node_choice_receipts.transaction_binding")


func test_transaction_node_mismatch_is_rejected() -> void:
	var run := _committed_run()
	_repoint_receipt_at_built_transaction(
		run,
		StringName(run.run_id),
		FOREIGN_NODE_ID,
		COMMIT_COMMAND_KIND,
		_committed_serial(run)
	)
	assert_eq(_failure_path(run), "run.node_choice_receipts.transaction_binding")


func test_transaction_run_mismatch_is_rejected() -> void:
	var run := _committed_run()
	# key 自身仍然合法（reencode_state 不會拿 run.run_id 交叉比對），只有
	# key.run_id ≠ receipt.run_id。
	_repoint_receipt_at_built_transaction(
		run,
		FOREIGN_RUN_ID,
		_receipt(run).node_id,
		COMMIT_COMMAND_KIND,
		_committed_serial(run)
	)
	assert_eq(_failure_path(run), "run.node_choice_receipts.transaction_binding")


func test_transaction_payload_digest_mismatch_is_rejected() -> void:
	var run := _committed_run()
	_matching_transaction(run).payload_digest = FOREIGN_PAYLOAD_DIGEST
	assert_eq(_failure_path(run), "run.node_choice_receipts.transaction_binding")


## 「找不到那筆 transaction」與「找到但綁不上」是兩種竄改，具名路徑不得合流。
func test_unknown_transaction_digest_keeps_its_own_failure_path() -> void:
	var run := _committed_run()
	_receipt(run).transaction_digest = UNKNOWN_TRANSACTION_DIGEST
	_reseal(run)
	assert_eq(_failure_path(run), "run.node_choice_receipts.transaction_digest")


# --- B2：node service resolution 的綁定 ---------------------------------------

func test_reward_service_kind_is_rejected() -> void:
	var run := _committed_run()
	# reward 沒有任何命令能處理（dismantle/exit 都要求 service_kind==dismantle），
	# 收下它等於接受一個可載入的永久 softlock。
	_service_pending(run).service_kind = &"reward"
	assert_eq(_failure_path(run), "run.resolution_state.node_service_pending")


func test_service_node_must_be_the_current_node() -> void:
	var run := _committed_run()
	_service_pending(run).node_id = FOREIGN_NODE_ID
	assert_eq(_failure_path(run), "run.resolution_state.node_service_pending")


func test_service_receipt_from_another_node_is_rejected() -> void:
	var run := _committed_run()
	# receipt 與它的 transaction 整組是「另一個節點的合法紀錄」：key 真的編得出來、
	# 逐欄綁定也全對，所以 ledger 完全過得去；service resolution 卻仍停在目前節點。
	# 只有 resolution 層的節點綁定能擋——否則 ExitNodeServiceCommand 會完成錯的節點。
	var serial := _committed_serial(run)
	_receipt(run).node_id = FOREIGN_NODE_ID
	_repoint_receipt_at_built_transaction(
		run,
		StringName(run.run_id),
		FOREIGN_NODE_ID,
		COMMIT_COMMAND_KIND,
		serial
	)
	assert_eq(
		_failure_path(run),
		"run.resolution_state.node_service_pending.choice_receipt"
	)


func test_service_receipt_with_non_dismantle_outcome_is_rejected() -> void:
	var run := _committed_run()
	_receipt(run).outcome_kind = NodeChoiceRule.OUTCOME_APPLY_AND_COMPLETE
	_reseal(run)
	assert_eq(
		_failure_path(run),
		"run.resolution_state.node_service_pending.choice_receipt"
	)


func test_service_receipt_digest_must_exist_in_the_ledger() -> void:
	var run := _committed_run()
	_service_pending(run).choice_receipt_digest = UNKNOWN_RECEIPT_DIGEST
	assert_eq(
		_failure_path(run),
		"run.resolution_state.node_service_pending.choice_receipt"
	)


# --- helpers ------------------------------------------------------------------

## OPEN_DISMANTLE_SERVICE 的正式產生路徑：begin → commit 一個 dismantle 選項。
func _committed_run() -> RunState:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set(
		NodeChoiceRule.OUTCOME_OPEN_DISMANTLE_SERVICE
	)
	var begun := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var committed := CommitNodeChoiceService.new().commit(
		begun,
		NodeChoiceServiceFixture.payload_for(begun, &"choice.fixture.dismantle"),
		rule,
		catalog
	)
	assert_true(committed.ok, NodeChoiceServiceFixture.error_code(committed))
	return committed.run_state


func _failure_path(run: RunState) -> String:
	var result := RunStateValidator.new().validate_run(run)
	if result.ok:
		return ""
	return String(result.error.field_path)


func _receipt(run: RunState) -> NodeChoiceCommitReceiptState:
	return run.node_choice_receipts[0].receipt


func _service_pending(run: RunState) -> NodeServicePendingResolutionState:
	return run.resolution_state as NodeServicePendingResolutionState


func _matching_transaction(run: RunState) -> TransactionReceiptState:
	return _transaction_of(run, _receipt(run).transaction_digest)


func _committed_serial(run: RunState) -> U64Bits:
	var parsed := U64Bits.from_hex(_receipt(run).transaction_serial)
	assert_true(parsed.ok, "receipt.transaction_serial must be 16 lower-hex")
	return parsed.value


func _transaction_of(
	run: RunState, transaction_digest: String
) -> TransactionReceiptState:
	for transaction: TransactionReceiptState in run.transaction_receipts:
		if String(transaction.key.digest) == transaction_digest:
			return transaction
	return null


## 改過 receipt 的任一欄之後，把 NCR1 digest 與所有指向它的地方一起補回一致狀態，
## 這樣測試斷言到的失敗一定來自被測的那一條綁定，而不是順帶壞掉的 digest。
func _reseal(run: RunState) -> void:
	var receipt := _receipt(run)
	receipt.refresh_digest()
	var transaction := _transaction_of(run, receipt.transaction_digest)
	if transaction != null:
		transaction.payload_digest = receipt.receipt_digest
	_service_pending(run).choice_receipt_digest = receipt.receipt_digest


## 攻擊構造的通用手法：真的用 registry 編一把 transaction key（因此 digest 自洽，
## 過得了 _runtime_key→reencode_state），排序插入 transaction_receipts，再把
## node-choice receipt 指過去並重算 NCR1／補齊 payload_digest。這樣 run.ledgers 一定
## 過，失敗只可能來自 receipt↔key 的逐欄綁定或 resolution 綁定。
func _repoint_receipt_at_built_transaction(
	run: RunState,
	run_id: StringName,
	node_id_or_camp: StringName,
	command_kind: StringName,
	serial: U64Bits
) -> void:
	var attack := _append_built_transaction(
		run, run_id, node_id_or_camp, command_kind, serial
	)
	_receipt(run).transaction_digest = String(attack.key.digest)
	_reseal(run)


func _append_built_transaction(
	run: RunState,
	run_id: StringName,
	node_id_or_camp: StringName,
	command_kind: StringName,
	serial: U64Bits
) -> TransactionReceiptState:
	var built := RuntimeKeySchemaRegistry.new().build_transaction(
		run_id, node_id_or_camp, command_kind, serial
	)
	assert_true(built.ok, "attack transaction key must build")
	EconomyCommandSupport.append_transaction_receipt(run, TransactionReceiptState.new(
		built.key_state as TransactionKeyState, FOREIGN_PAYLOAD_DIGEST
	))
	return _transaction_of(run, String(built.key_state.digest))
