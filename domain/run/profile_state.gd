class_name ProfileState
extends RefCounted

var profile_id: String
var next_run_serial: U64Bits
var meta_currency: int
var unlocked_content_ids: Array[StringName] = []
var discovered_content_ids: Array[StringName] = []
var highest_challenge_level: int
var settlement_receipts: Array[SettlementReceiptState] = []
var settings_ref: StringName
var last_selection: ProfileLastSelectionState
var commander_challenge_records: Array[CommanderChallengeRecordState] = []

func _init(
	p_profile_id: String,
	p_next_run_serial: U64Bits,
	p_meta_currency: int,
	p_unlocked_content_ids: Array[StringName],
	p_discovered_content_ids: Array[StringName],
	p_highest_challenge_level: int,
	p_settlement_receipts: Array[SettlementReceiptState],
	p_settings_ref: StringName,
	p_last_selection: ProfileLastSelectionState,
	p_commander_challenge_records: Array[CommanderChallengeRecordState]
) -> void:
	profile_id = p_profile_id
	next_run_serial = p_next_run_serial.deep_clone()
	meta_currency = p_meta_currency
	unlocked_content_ids.assign(p_unlocked_content_ids)
	discovered_content_ids.assign(p_discovered_content_ids)
	highest_challenge_level = p_highest_challenge_level
	for receipt: SettlementReceiptState in p_settlement_receipts:
		settlement_receipts.append(receipt.deep_clone())
	settings_ref = p_settings_ref
	last_selection = p_last_selection.deep_clone() if p_last_selection != null else null
	for record: CommanderChallengeRecordState in p_commander_challenge_records:
		commander_challenge_records.append(record.deep_clone())

func deep_clone() -> ProfileState:
	return ProfileState.new(
		profile_id,
		next_run_serial,
		meta_currency,
		unlocked_content_ids,
		discovered_content_ids,
		highest_challenge_level,
		settlement_receipts,
		settings_ref,
		last_selection,
		commander_challenge_records
	)
