class_name IncomeTransaction
extends RefCounted

var economy_state: EconomyState
var next_transaction_serial: U64Bits
var receipt: TransactionReceiptState
var base_income: int
var interest_income: int
var streak_income: int

func _init(
	p_economy: EconomyState, p_next_serial: U64Bits,
	p_receipt: TransactionReceiptState, p_base: int, p_interest: int, p_streak: int
) -> void:
	economy_state = p_economy.deep_clone()
	next_transaction_serial = p_next_serial.deep_clone()
	receipt = p_receipt.deep_clone()
	base_income = p_base
	interest_income = p_interest
	streak_income = p_streak

func deep_clone() -> IncomeTransaction:
	return IncomeTransaction.new(economy_state, next_transaction_serial, receipt, base_income, interest_income, streak_income)
