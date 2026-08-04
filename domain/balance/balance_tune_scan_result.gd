class_name BalanceTuneScanResult
extends RefCounted

var ok: bool
var entries: Array[BalanceTuneEntry] = []
var error_path: String
var error_detail: String


static func success(values: Array[BalanceTuneEntry]) -> BalanceTuneScanResult:
	var result := BalanceTuneScanResult.new()
	result.ok = true
	for entry: BalanceTuneEntry in values:
		result.entries.append(entry.deep_clone() if entry != null else null)
	return result


static func failure(path: String, detail: String) -> BalanceTuneScanResult:
	var result := BalanceTuneScanResult.new()
	result.ok = false
	result.error_path = path
	result.error_detail = detail
	return result
