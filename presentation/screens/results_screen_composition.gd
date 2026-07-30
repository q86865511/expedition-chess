class_name ResultsScreenComposition
extends Control

const COMPOSE_INVALID: StringName = &"RESULTS_COMPOSE_INVALID"
const AUTHORITATIVE_PAIR_INVALID: StringName = \
	&"RESULTS_AUTHORITATIVE_PAIR_INVALID"

var _snapshot: ResultsPresentationSnapshot
var _localized_text: Dictionary[StringName, String] = {}


func compose(
	snapshot: ResultsPresentationSnapshot,
	localized_text: Dictionary = {}
) -> StringName:
	if snapshot == null:
		return COMPOSE_INVALID
	var owned_snapshot := snapshot.deep_clone()
	if not owned_snapshot.has_authoritative_pair():
		return AUTHORITATIVE_PAIR_INVALID
	_snapshot = owned_snapshot
	_set_localized_text(localized_text)
	_set_value(^"ReceiptValue", String(_snapshot.receipt_id), &"receipt")
	_set_value(
		^"OutcomeValue",
		_outcome_text(_snapshot.receipt.outcome),
		&"outcome"
	)
	_set_value(
		^"RewardValue",
		str(_snapshot.receipt.currency_delta),
		&"reward"
	)
	_set_value(
		^"ProfileValue",
		str(_snapshot.profile.meta_currency),
		&"profile_currency"
	)
	_set_value(
		^"DigestValue",
		_snapshot.committed_file_digest,
		&"committed_digest"
	)
	return &""


func snapshot_clone() -> ResultsPresentationSnapshot:
	return _snapshot.deep_clone() if _snapshot != null else null


func _set_value(path: NodePath, value: String, kind: StringName) -> void:
	var label := get_node_or_null(path) as Label
	if label == null:
		return
	label.text = value
	label.set_meta(&"typed_data_kind", kind)
	label.set_meta(&"accessible_text", value)


func _outcome_text(outcome: SettlementReceiptState.Outcome) -> String:
	var token: StringName
	match outcome:
		SettlementReceiptState.Outcome.COMPLETED:
			token = &"completed"
		SettlementReceiptState.Outcome.FAILED:
			token = &"failed"
		SettlementReceiptState.Outcome.ABANDONED:
			token = &"abandoned"
		_:
			token = &"unknown"
	return _text(StringName("results.outcome.%s" % String(token)))


func _set_localized_text(values: Dictionary) -> void:
	_localized_text.clear()
	for key: Variant in values.keys():
		_localized_text[StringName(key)] = String(values[key])


func _text(key: StringName) -> String:
	return _localized_text.get(key, String(key))
