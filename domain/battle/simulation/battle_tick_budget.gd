class_name BattleTickBudget
extends RefCounted

var effect_limit: int
var operation_limit: int
var event_limit: int
var entity_limit: int
var effect_count: int = 0
var operation_count: int = 0
var event_count: int = 0

func _init(
	p_effect_limit: int,
	p_operation_limit: int,
	p_event_limit: int,
	p_entity_limit: int
) -> void:
	effect_limit = p_effect_limit
	operation_limit = p_operation_limit
	event_limit = p_event_limit
	entity_limit = p_entity_limit

func take_effect() -> bool:
	if effect_count + 1 > effect_limit:
		return false
	effect_count += 1
	return true

func take_operations(count: int) -> bool:
	if count < 0 or operation_count + count > operation_limit:
		return false
	operation_count += count
	return true

func take_event() -> bool:
	if event_count + 1 > event_limit:
		return false
	event_count += 1
	return true

func deep_clone() -> BattleTickBudget:
	var copied := BattleTickBudget.new(effect_limit, operation_limit, event_limit, entity_limit)
	copied.effect_count = effect_count
	copied.operation_count = operation_count
	copied.event_count = event_count
	return copied
