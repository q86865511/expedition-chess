class_name BenchCompactor
extends RefCounted

func compact(
	bench_unit_instance_ids: Array[String],
	valid_unit_instance_ids: Array[String],
	on_board_unit_instance_ids: Array[String]
) -> Array[String]:
	var compacted: Array[String] = []
	for instance_id: String in bench_unit_instance_ids:
		if instance_id.is_empty() or not valid_unit_instance_ids.has(instance_id) \
			or on_board_unit_instance_ids.has(instance_id):
			continue
		compacted.append(instance_id)
	return compacted
