class_name UnitMergeResult
extends RefCounted

var ok: bool
var roster: RosterState
var merge_count: int
var copy_ledger: Array[UnitCopyLedgerEntry] = []
var error: UnitMergeError

static func success(
	p_roster: RosterState,
	p_merge_count: int,
	p_copy_ledger: Array[UnitCopyLedgerEntry]
) -> UnitMergeResult:
	return UnitMergeResult.new(true, p_roster, p_merge_count, p_copy_ledger, null)

static func failure(p_error: UnitMergeError) -> UnitMergeResult:
	var no_ledger: Array[UnitCopyLedgerEntry] = []
	return UnitMergeResult.new(false, null, 0, no_ledger, p_error)

func _init(
	p_ok: bool,
	p_roster: RosterState,
	p_merge_count: int,
	p_copy_ledger: Array[UnitCopyLedgerEntry],
	p_error: UnitMergeError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_roster != null and p_merge_count >= 0,
		p_roster == null and p_merge_count == 0 and p_copy_ledger.is_empty()
	)
	ok = p_ok
	roster = p_roster.deep_clone() if p_roster != null else null
	merge_count = p_merge_count
	for entry: UnitCopyLedgerEntry in p_copy_ledger:
		copy_ledger.append(entry.deep_clone())
	error = p_error.deep_clone() if p_error != null else null
