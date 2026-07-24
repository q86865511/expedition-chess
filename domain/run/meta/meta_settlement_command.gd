class_name MetaSettlementCommand
extends RefCounted

## design.md §5.1 point5／§5.2 — FINISH_RUN 的單一原子 meta 結算交易（S5-AC-007／
## REQ-META-004／REQ-DATA-007／REQ-TECH-004）。自包含交易單元：直接經 SaveRepository
## load → settle → save，不依賴 CampController／RunController（正式接線屬 T11）。
##
## dispatch()：
##   1. repository.load() 取得目前 profile/run。load 失敗（存檔各前置故障點）→ SAVE_FAILED：
##      交易尚未提交、run 維持 active，重載重試即可（§5.2）。
##   2. 無 active run（run==null）→ NO_ACTIVE_RUN：無可結算標的、零變動。
##   3. MetaSettlementService.settle(profile, run, table) → profile'（回 null
##      時→KEY_FAILED：不可達防禦路徑，尚未組 SaveRoot、run 未清）；否則組
##      SaveRoot(profile', run=null) 經 repository.save 單一原子提交（清除 active run 與
##      發放貨幣/receipt/挑戰紀錄同一 SaveRoot）。save 失敗 → SAVE_FAILED：
##      SaveRepository 的 tmp→readback→promote→final-readback 全有或全無，故障後 run
##      仍 active、profile 未變。
##
## exactly-once（§5.2）：(a) settle 為純函式恆得同值；(b) 單一原子 SaveRoot 提交；
## (c) run_id receipt 冪等守衛；(d) 成功後 run=null→無 active run 可再結算→零重發。
## content_version 取自 load 到的 run.content_snapshot（清 run 前）——load 不回傳原
## SaveRoot 的 schema/app_version metadata，故 Command 比照 RunSaveRootFactory 自行決定。
var _repository: SaveRepository
var _meta_reward_table: MetaRewardTableDef
var _app_version: String
var _clock: RunCommitClock

func _init(
	p_repository: SaveRepository,
	p_meta_reward_table: MetaRewardTableDef,
	p_app_version: String = "0.2.0",
	p_clock: RunCommitClock = null
) -> void:
	_repository = p_repository
	_meta_reward_table = p_meta_reward_table
	_app_version = p_app_version
	_clock = p_clock if p_clock != null else RunCommitClock.new()

func dispatch() -> MetaSettlementCommandResult:
	var loaded := _repository.load()
	if not loaded.ok:
		return MetaSettlementCommandResult.failure(
			MetaSettlementCommandError.SAVE_FAILED,
			loaded.error.field_path if loaded.error != null else &"load"
		)
	if loaded.run_status != LoadResult.RunStatus.LOADED or loaded.run == null:
		return MetaSettlementCommandResult.failure(
			MetaSettlementCommandError.NO_ACTIVE_RUN, &"run"
		)
	var content_version := loaded.run.content_snapshot.content_version_value()
	var settled := MetaSettlementService.settle(
		loaded.profile, loaded.run, _meta_reward_table
	)
	if settled == null:
		return MetaSettlementCommandResult.failure(
			MetaSettlementCommandError.KEY_FAILED, &"terminal_run.run_id"
		)
	var root := SaveRoot.new(
		SaveSchemaContract.CURRENT,
		content_version,
		_app_version,
		1,
		1,
		_clock.now_utc(),
		settled,
		null
	)
	var save_result := _repository.save(root)
	if not save_result.ok:
		return MetaSettlementCommandResult.failure(
			MetaSettlementCommandError.SAVE_FAILED,
			save_result.error.field_path if save_result.error != null else &"save"
		)
	return MetaSettlementCommandResult.success()
