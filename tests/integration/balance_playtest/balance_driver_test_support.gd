extends RefCounted

## balance-playtest driver 整合測試的共用工具（rewrite-plan.md §5.1～§5.5）。
## 檔名沒有 `test_` 前綴，GUT 不會把本檔當成測試腳本蒐集（.gutconfig.json prefix）。

## 錨點 seed 取自 3k screening #2 的逐 case 證據
## （artifacts/test/balance-screening-shard-*.json 的 case_proofs）：
## seed 0 的 tempo／economy／synergy 三策略皆走完 21 節點且存活。
##
## 敗局／abandon 情境**不用 seed 當錨點**：實測邊緣 case 的勝負會隨同 process 內
## 先跑過哪些測試而改變，改由 prepare_probe_driver 的 force_empty_board_at_boss
## 確定性構造（見該檔說明）。
const SEED_VICTORY: int = 0

const SETTLEMENT_RECEIPT_PREFIX: String = "battle_settle_"
const REWARD_RECEIPT_PREFIX: String = "reward_"
const ABANDON_RECEIPT_KIND: String = "expedition_abandon"


## driver 的 storage factory：每個 case 一個隔離的 in-memory storage，並保留參考，
## 讓測試在 run_case 收工（driver 已 free 自己的 repository）後仍能讀回權威存檔。
class StorageRecorder:
	extends RefCounted

	var storages: Array[FakeSaveStorage] = []

	func factory() -> Callable:
		return func() -> SaveStoragePort:
			var storage := FakeSaveStorage.new()
			storages.append(storage)
			return storage

	func latest() -> FakeSaveStorage:
		return storages[-1] if not storages.is_empty() else null


## 以獨立 repository 讀回 storage 中的權威 RunState；讀不到回 null。
static func load_run(
	storage: FakeSaveStorage, registry: ContentRegistryService
) -> RunState:
	if storage == null or registry == null:
		return null
	var repository := SaveRepository.new(
		storage,
		ContentRegistryReceiptAdapter.new(registry),
		ContentRegistryMigrationAdapter.new(registry),
		RunStateValidator.new()
	)
	var loaded := repository.load()
	repository.free()
	return loaded.run if loaded.ok else null


## 取出 command_kind 以 `prefix` 開頭的 transaction receipt 證據
## （key digest + payload digest），供 exactly-once 對帳。
static func receipt_proofs(run: RunState, prefix: String) -> Array[String]:
	var proofs: Array[String] = []
	if run == null:
		return proofs
	for receipt: TransactionReceiptState in run.transaction_receipts:
		if receipt == null or receipt.key == null:
			continue
		if String(receipt.key.command_kind).begins_with(prefix):
			proofs.append("%s:%s" % [String(receipt.key.digest), receipt.payload_digest])
	return proofs


## 回傳第一個重複值；沒有重複回空字串（比 bool 好讀，失敗訊息能指出是哪一筆）。
static func duplicate_of(values: Array[String]) -> String:
	var seen: Dictionary = {}
	for value: String in values:
		if seen.has(value):
			return value
		seen[value] = true
	return ""


static func dispatch_error(result: RunPresentationResult) -> String:
	if result == null or result.ok or result.error == null:
		return ""
	return "%s/%s" % [
		String(result.error.source_code), String(result.error.message_key),
	]
