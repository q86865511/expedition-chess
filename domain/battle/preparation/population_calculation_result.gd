class_name PopulationCalculationResult
extends RefCounted

var ok: bool
var derived_capacity: int
var ordered_sources: Array[PopulationSourceSnapshot] = []
var error: PopulationCalculationError

static func success(
	p_derived_capacity: int,
	p_ordered_sources: Array[PopulationSourceSnapshot]
) -> PopulationCalculationResult:
	return PopulationCalculationResult.new(true, p_derived_capacity, p_ordered_sources, null)

static func failure(p_error: PopulationCalculationError) -> PopulationCalculationResult:
	var no_sources: Array[PopulationSourceSnapshot] = []
	return PopulationCalculationResult.new(false, -1, no_sources, p_error)

func _init(
	p_ok: bool,
	p_derived_capacity: int,
	p_ordered_sources: Array[PopulationSourceSnapshot],
	p_error: PopulationCalculationError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_derived_capacity >= 0,
		p_derived_capacity == -1 and p_ordered_sources.is_empty()
	)
	ok = p_ok
	derived_capacity = p_derived_capacity
	for source: PopulationSourceSnapshot in p_ordered_sources:
		ordered_sources.append(source.deep_clone())
	error = p_error.deep_clone() if p_error != null else null
