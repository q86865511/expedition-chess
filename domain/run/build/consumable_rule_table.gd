class_name ConsumableRuleTable
extends RefCounted

## Typed, pinned-manifest lookup of ConsumableRule by consumable_id, mirroring
## RunRelicTable. DismantleEquipmentCommand consults this before consuming a
## consumable so that only a genuine dismantle ConsumableDef (not an arbitrary
## inventory item) can be spent to unbind equipment. Built only from a pinned
## manifest (carries manifest_digest), never from the latest catalog.

var _manifest_digest: String
var _rules: Array[ConsumableRule] = []

func _init(manifest_digest: String, rules: Array[ConsumableRule]) -> void:
	_manifest_digest = manifest_digest
	for value: ConsumableRule in rules:
		_rules.append(value.deep_clone())

func manifest_digest_value() -> String:
	return _manifest_digest

func try_rule(consumable_id: StringName) -> ConsumableRule:
	for value: ConsumableRule in _rules:
		if value.consumable_id == consumable_id:
			return value.deep_clone()
	return null

func is_dismantle_consumable(consumable_id: StringName) -> bool:
	var rule := try_rule(consumable_id)
	return rule != null and rule.is_dismantle()

func deep_clone() -> ConsumableRuleTable:
	return ConsumableRuleTable.new(_manifest_digest, _rules)
