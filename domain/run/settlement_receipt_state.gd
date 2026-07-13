class_name SettlementReceiptState
extends RefCounted

enum Outcome { COMPLETED, FAILED, ABANDONED }

var key: SettlementReceiptKeyState
var outcome: Outcome
var currency_delta: int
var payload_digest: String

func _init(
	p_key: SettlementReceiptKeyState,
	p_outcome: Outcome,
	p_currency_delta: int,
	p_payload_digest: String
) -> void:
	key = p_key.deep_clone()
	outcome = p_outcome
	currency_delta = p_currency_delta
	payload_digest = p_payload_digest

func deep_clone() -> SettlementReceiptState:
	return SettlementReceiptState.new(key, outcome, currency_delta, payload_digest)
