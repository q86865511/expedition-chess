class_name BoardPreparationRequest
extends RefCounted

var board: BoardState
var bench_unit_instance_ids: Array[String] = []
var unit_instances: Array[UnitInstance] = []
var base_level: int
var population_sources: Array[PopulationSourceSnapshot] = []

func _init(
	p_board: BoardState,
	p_bench_unit_instance_ids: Array[String],
	p_unit_instances: Array[UnitInstance],
	p_base_level: int,
	p_population_sources: Array[PopulationSourceSnapshot]
) -> void:
	board = p_board.deep_clone() if p_board != null else null
	bench_unit_instance_ids.assign(p_bench_unit_instance_ids)
	for unit: UnitInstance in p_unit_instances:
		unit_instances.append(unit.deep_clone() if unit != null else null)
	base_level = p_base_level
	for source: PopulationSourceSnapshot in p_population_sources:
		population_sources.append(source.deep_clone() if source != null else null)

func deep_clone() -> BoardPreparationRequest:
	return BoardPreparationRequest.new(
		board,
		bench_unit_instance_ids,
		unit_instances,
		base_level,
		population_sources
	)
