class_name RunRelicTable
extends RefCounted

var _manifest_digest: String
var _rules: Array[RunRelicRule] = []

func _init(manifest_digest: String, rules: Array[RunRelicRule]) -> void:
	_manifest_digest = manifest_digest
	for value: RunRelicRule in rules:
		_rules.append(value.deep_clone())

func manifest_digest_value() -> String:
	return _manifest_digest

func rules_for_category(category: StringName) -> Array[RunRelicRule]:
	var result: Array[RunRelicRule] = []
	for value: RunRelicRule in _rules:
		if value.category == category:
			result.append(value.deep_clone())
	return result

func try_relic_rule(relic_id: StringName) -> RunRelicRule:
	for value: RunRelicRule in _rules:
		if value.relic_id == relic_id:
			return value.deep_clone()
	return null

func deep_clone() -> RunRelicTable:
	return RunRelicTable.new(_manifest_digest, _rules)
