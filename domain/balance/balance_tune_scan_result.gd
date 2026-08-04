class_name BalanceTuneScanResult
extends RefCounted

var ok: bool
var entries: Array[BalanceTuneEntry] = []
var error_path: String
var error_detail: String
var error: BalanceTuneScanError


func _init(
	p_ok: bool,
	p_entries: Array[BalanceTuneEntry],
	p_error: BalanceTuneScanError
) -> void:
	ResultInvariant.require(
		p_ok, p_error, true, p_entries.is_empty()
	)
	ok = p_ok
	for entry: BalanceTuneEntry in p_entries:
		entries.append(entry.deep_clone() if entry != null else null)
	error = p_error.deep_clone() if p_error != null else null
	error_path = error.path if error != null else ""
	error_detail = error.detail if error != null else ""


static func success(values: Array[BalanceTuneEntry]) -> BalanceTuneScanResult:
	return BalanceTuneScanResult.new(true, values, null)


static func failure(path: String, detail: String) -> BalanceTuneScanResult:
	return BalanceTuneScanResult.new(
		false, [] as Array[BalanceTuneEntry],
		BalanceTuneScanError.new(path, detail)
	)
