class_name AudioBusBatch
extends RefCounted

var assignments: Array[AudioBusAssignment] = []


func _init(p_assignments: Array[AudioBusAssignment]) -> void:
	for assignment: AudioBusAssignment in p_assignments:
		assignments.append(assignment.deep_clone())


func deep_clone() -> AudioBusBatch:
	return AudioBusBatch.new(assignments)
