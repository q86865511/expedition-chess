class_name BalanceTuneScanError
extends RefCounted

var path: String
var detail: String


func _init(p_path: String, p_detail: String) -> void:
	path = p_path
	detail = p_detail


func deep_clone() -> BalanceTuneScanError:
	return BalanceTuneScanError.new(path, detail)
