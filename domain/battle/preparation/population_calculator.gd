class_name PopulationCalculator
extends RefCounted

const _MAX_I32: int = 2147483647

var _stable_ids := StableIdValidator.new()

func calculate(
	base_level: int,
	sources: Array[PopulationSourceSnapshot]
) -> PopulationCalculationResult:
	if base_level < 0 or base_level > _MAX_I32:
		return PopulationCalculationResult.failure(
			PopulationCalculationError.new(
				PopulationCalculationError.INVALID_BASE_LEVEL,
				&"base_level"
			)
		)
	var ordered: Array[PopulationSourceSnapshot] = []
	for index: int in range(sources.size()):
		var source := sources[index]
		if not _source_is_valid(source):
			return PopulationCalculationResult.failure(
				PopulationCalculationError.new(
					PopulationCalculationError.INVALID_SOURCE,
					StringName("sources.%d" % index)
				)
			)
		ordered.append(source.deep_clone())
	ordered.sort_custom(_source_precedes)
	var previous_identity := ""
	var total := base_level
	for source: PopulationSourceSnapshot in ordered:
		var identity := _identity(source)
		if identity == previous_identity:
			return PopulationCalculationResult.failure(
				PopulationCalculationError.new(
					PopulationCalculationError.DUPLICATE_SOURCE,
					&"sources"
				)
			)
		if total > _MAX_I32 - source.amount:
			return PopulationCalculationResult.failure(
				PopulationCalculationError.new(
					PopulationCalculationError.OVERFLOW,
					&"derived_capacity"
				)
			)
		total += source.amount
		previous_identity = identity
	return PopulationCalculationResult.success(total, ordered)

func _source_is_valid(source: PopulationSourceSnapshot) -> bool:
	if source == null or source.source_kind < PopulationSourceSnapshot.SourceKind.EVENT \
		or source.source_kind > PopulationSourceSnapshot.SourceKind.TRAIT:
		return false
	if not _stable_ids.is_valid(source.source_id):
		return false
	if source.source_instance_or_slot.is_empty() \
		or not _strict_ascii(source.source_instance_or_slot):
		return false
	return source.amount > 0 and source.amount <= _MAX_I32

func _identity(source: PopulationSourceSnapshot) -> String:
	return "%02d/%s/%s" % [
		source.source_kind,
		String(source.source_id),
		source.source_instance_or_slot,
	]

func _source_precedes(left: PopulationSourceSnapshot, right: PopulationSourceSnapshot) -> bool:
	return _identity(left) < _identity(right)

func _strict_ascii(value: String) -> bool:
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if code < 0x21 or code > 0x7e:
			return false
	return true
