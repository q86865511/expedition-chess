class_name RunRelicTableBuilder
extends RefCounted

func build(
	registry: ContentRegistryService,
	manifest_digest: String,
	relic_ids: Array[StringName]
) -> RunRelicTableBuildResult:
	if registry == null or manifest_digest.length() != 64:
		return RunRelicTableBuildResult.failure(RunRelicTableError.INPUT_INVALID, &"manifest_digest")
	var rules: Array[RunRelicRule] = []
	var sorted_ids: Array[StringName] = relic_ids.duplicate()
	sorted_ids.sort()
	for relic_id: StringName in sorted_ids:
		if not StableIdValidator.new().is_valid(relic_id):
			return RunRelicTableBuildResult.failure(RunRelicTableError.INPUT_INVALID, &"relic_ids", relic_id)
		var resolved := registry.resolve(ContentRef.new(manifest_digest, relic_id))
		if not resolved.ok:
			return RunRelicTableBuildResult.failure(RunRelicTableError.RESOLVE_FAILED, resolved.error.field_path, relic_id)
		var view: ContentDefinitionView = resolved.value
		if view.category != &"relic":
			return RunRelicTableBuildResult.failure(RunRelicTableError.CATEGORY_MISMATCH, &"category", relic_id)
		if view.payload == null or view.payload.record_type != ContentCategory.RELIC or view.payload.children.size() != 7:
			return RunRelicTableBuildResult.failure(RunRelicTableError.PAYLOAD_INVALID, &"relic.payload", relic_id)
		var category := StringName(view.payload.children[3].string_value)
		if category == &"battle":
			return RunRelicTableBuildResult.failure(RunRelicTableError.CATEGORY_MISMATCH, &"relic.category", relic_id)
		var rule := RunRelicRule.new()
		rule.relic_id = view.content_id
		rule.category = category
		rule.effect_ids = _names(view.payload.children[4])
		rules.append(rule)
	rules.sort_custom(_rule_less)
	return RunRelicTableBuildResult.success(RunRelicTable.new(manifest_digest, rules))

func _names(value: ContentValue) -> Array[StringName]:
	var result: Array[StringName] = []
	if value == null:
		return result
	for child: ContentValue in value.children:
		result.append(StringName(child.string_value))
	return result

func _rule_less(left: RunRelicRule, right: RunRelicRule) -> bool:
	return String(left.relic_id) < String(right.relic_id)
