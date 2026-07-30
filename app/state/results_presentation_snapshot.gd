class_name ResultsPresentationSnapshot
extends RefCounted

var run_id: StringName
var receipt_id: StringName
var committed_file_digest: String
var can_exit_results: bool
var profile: ProfileState
var receipt: SettlementReceiptState


static func capture(
	p_profile: ProfileState,
	p_receipt: SettlementReceiptState,
	p_run_id: StringName,
	p_committed_file_digest: String,
	p_can_exit_results: bool
) -> ResultsPresentationSnapshot:
	var snapshot := ResultsPresentationSnapshot.new()
	snapshot.run_id = p_run_id
	snapshot.receipt_id = (
		StringName(p_receipt.key.digest)
		if p_receipt != null and p_receipt.key != null
		else &""
	)
	snapshot.committed_file_digest = p_committed_file_digest
	snapshot.can_exit_results = p_can_exit_results
	snapshot.profile = p_profile.deep_clone() if p_profile != null else null
	snapshot.receipt = p_receipt.deep_clone() if p_receipt != null else null
	return snapshot


func deep_clone() -> ResultsPresentationSnapshot:
	var clone := ResultsPresentationSnapshot.new()
	clone.run_id = run_id
	clone.receipt_id = receipt_id
	clone.committed_file_digest = committed_file_digest
	clone.can_exit_results = can_exit_results
	clone.profile = profile.deep_clone() if profile != null else null
	clone.receipt = receipt.deep_clone() if receipt != null else null
	return clone


func has_authoritative_pair() -> bool:
	if (
		run_id.is_empty()
		or receipt_id.is_empty()
		or committed_file_digest.is_empty()
		or profile == null
		or receipt == null
		or receipt.key == null
		or StringName(receipt.key.digest) != receipt_id
	):
		return false
	for candidate: SettlementReceiptState in profile.settlement_receipts:
		if (
			candidate.key != null
			and StringName(candidate.key.digest) == receipt_id
			and candidate.outcome == receipt.outcome
			and candidate.currency_delta == receipt.currency_delta
			and candidate.payload_digest == receipt.payload_digest
		):
			return true
	return false


func presentation_digest() -> String:
	if not has_authoritative_pair():
		return ""
	var receipts: Array[Dictionary] = []
	for candidate: SettlementReceiptState in profile.settlement_receipts:
		receipts.append(_receipt_projection(candidate))
	var records: Array[Dictionary] = []
	for record: CommanderChallengeRecordState in profile.commander_challenge_records:
		records.append({
			"commander_id": String(record.commander_id),
			"highest_cleared_level": record.highest_cleared_level,
		})
	var last_selection: Variant = null
	if profile.last_selection != null:
		last_selection = {
			"commander_id": String(profile.last_selection.commander_id),
			"challenge_level": profile.last_selection.challenge_level,
		}
	var payload := {
		"run_id": String(run_id),
		"receipt_id": String(receipt_id),
		"committed_file_digest": committed_file_digest,
		"can_exit_results": can_exit_results,
		"profile": {
			"profile_id": profile.profile_id,
			"next_run_serial": profile.next_run_serial.to_hex(),
			"meta_currency": profile.meta_currency,
			"unlocked_content_ids": _string_names(profile.unlocked_content_ids),
			"discovered_content_ids": _string_names(profile.discovered_content_ids),
			"highest_challenge_level": profile.highest_challenge_level,
			"settlement_receipts": receipts,
			"settings_ref": String(profile.settings_ref),
			"last_selection": last_selection,
			"commander_challenge_records": records,
		},
		"receipt": _receipt_projection(receipt),
	}
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(JSON.stringify(payload).to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _receipt_projection(value: SettlementReceiptState) -> Dictionary:
	if value == null or value.key == null:
		return {}
	return {
		"kind": String(value.key.kind),
		"run_id": String(value.key.run_id),
		"digest": String(value.key.digest),
		"outcome": value.outcome,
		"currency_delta": value.currency_delta,
		"payload_digest": value.payload_digest,
	}


func _string_names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result
