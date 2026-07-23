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
		for effect_id: StringName in rule.effect_ids:
			var append_error := _append_effect_run_operations(registry, manifest_digest, effect_id, rule.run_operations)
			if append_error != &"":
				return RunRelicTableBuildResult.failure(
					append_error, &"relic.run_operations", relic_id
				)
		if not _has_supported_run_intent(rule):
			return RunRelicTableBuildResult.failure(
				RunRelicTableError.UNSUPPORTED_INTENT, &"relic.run_operations", relic_id
			)
		rules.append(rule)
	rules.sort_custom(_rule_less)
	return RunRelicTableBuildResult.success(RunRelicTable.new(manifest_digest, rules))

## 解析非 battle 遺物 effect_ref 所指的 EffectDef payload，取其 run_operations（children[8]，
## 形狀同 battle_rule_catalog_builder._decode_run_operation），append 進 target。
## 回傳 &"" 表成功；解不到、非 &"effect" 分類、或 payload/紀錄形狀不符 → PAYLOAD_INVALID。
## W3-F5（S4 語意，2026-07-23 使用者裁決）＋W4-F2（2026-07-24 使用者裁決，移除混合效果豁免）：
## 非 battle 遺物解出的每一筆 run intent，其 claim_scope 必須是 &"always" 哨兵，否則回
## UNSUPPORTED_INTENT——S4 只支援 always（其餘 scope 語意如 on_first_clear 延後 S5）。
## run-layer 消費端（IncomeService/ShopService…／RunRelicTable.sum_operation_amount）逐節點
## 無條件加總、不看 claim_scope，任何非 always 的宣告都無法被正確履行。此約束不分效果是否
## 同時帶 battle_operations（混合效果）：混合效果的戰鬥部分屬 battle 類遺物作用域、不被 run
## layer 消費，但被非 battle 遺物引用時其 run 部分同樣受 always 約束（與 content_validator 的
## _validate_relic_effect_scope 對齊，消除 validator↔builder 分歧）。
func _append_effect_run_operations(
	registry: ContentRegistryService, manifest_digest: String,
	effect_id: StringName, target: Array[RunRelicOperationRule]
) -> StringName:
	var resolved := registry.resolve(ContentRef.new(manifest_digest, effect_id))
	if not resolved.ok:
		return RunRelicTableError.PAYLOAD_INVALID
	var view: ContentDefinitionView = resolved.value
	if view.category != &"effect":
		return RunRelicTableError.PAYLOAD_INVALID
	if view.payload == null or view.payload.record_type != ContentCategory.EFFECT \
		or view.payload.children.size() != 12:
		return RunRelicTableError.PAYLOAD_INVALID
	for value: ContentValue in view.payload.children[8].children:
		if value == null or value.children.size() != 3:
			return RunRelicTableError.PAYLOAD_INVALID
		var operation := RunRelicOperationRule.new()
		operation.operation_index = value.children[0].int_value
		operation.amount = value.children[1].int_value
		operation.claim_scope = StringName(value.children[2].string_value)
		match value.record_type:
			0x3101: operation.kind = &"add_gold"
			0x3102: operation.kind = &"add_xp"
			0x3103: operation.kind = &"heal_expedition_hp"
			0x3108: operation.kind = &"shop_discount"
			_: return RunRelicTableError.PAYLOAD_INVALID
		if operation.claim_scope != &"always":
			return RunRelicTableError.UNSUPPORTED_INTENT
		target.append(operation)
	return &""

## design §6/§10：非 battle 遺物的 run intent 必須落在對應 run-layer service 實際消費的
## (category, kind) 支援集合，否則其效果永遠不會被讀取（死內容）→ build 失敗。
## 一件遺物只要至少有一筆 run_operation 落在支援集合即算 alive（其餘 kind 視為同載的無效果
## intent，不阻擋 build——見 test_run_relic_table_operations 的 economy 遺物同時帶三種 kind）。
func _has_supported_run_intent(rule: RunRelicRule) -> bool:
	for operation: RunRelicOperationRule in rule.run_operations:
		if _is_supported_run_intent(rule.category, operation.kind):
			return true
	return false

## 支援集合以「修正後實際消費端」為準：
## - economy：IncomeService 讀 add_gold、ShopService 讀 shop_discount。
## - rule：BattleSettlementService 讀 heal_expedition_hp。
## - route：MapService 只計數 active route 遺物、不讀 kind，故任一可解碼的 run kind 皆有效。
func _is_supported_run_intent(category: StringName, kind: StringName) -> bool:
	match category:
		&"economy":
			return kind == &"add_gold" or kind == &"shop_discount"
		&"rule":
			return kind == &"heal_expedition_hp"
		&"route":
			return kind == &"add_gold" or kind == &"add_xp" \
				or kind == &"heal_expedition_hp" or kind == &"shop_discount"
	return false

func _names(value: ContentValue) -> Array[StringName]:
	var result: Array[StringName] = []
	if value == null:
		return result
	for child: ContentValue in value.children:
		result.append(StringName(child.string_value))
	return result

func _rule_less(left: RunRelicRule, right: RunRelicRule) -> bool:
	return String(left.relic_id) < String(right.relic_id)
