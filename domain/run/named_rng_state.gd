class_name NamedRngState
extends RefCounted

enum StreamName { MAP, SHOP, REWARD, COMBAT }

var stream_name: StreamName
var snapshot: RngSnapshot

func _init(p_stream_name: StreamName, p_snapshot: RngSnapshot) -> void:
	stream_name = p_stream_name
	snapshot = p_snapshot.deep_clone()

func deep_clone() -> NamedRngState:
	return NamedRngState.new(stream_name, snapshot)
