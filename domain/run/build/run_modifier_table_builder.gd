class_name RunModifierTableBuilder
extends RefCounted

## design §6.1（S5-AC-003）：在既有 slot-gated 遺物規則之上，疊加指揮官被動與挑戰詞綴兩層
## always-active 規則，產出擴充後的 RunRelicTable。
## - relic 規則（source=relic，slot-gated）：沿用既有 RunRelicTableBuilder 解析，不改其行為。
## - commander 規則（source=commander，always-active）：解 CommanderDef.passive_effect_refs 的
##   run_operations。
## - challenge 規則（source=challenge，always-active）：解 challenge unlock 鏈 1..N 的
##   modifier_refs 的 run_operations（本波僅建通道與參數，wave4 才有實際內容）。
## 回傳型別重用 RunRelicTableBuildResult（同一個 RunRelicTable 產物，不另造同構型別）。

## always-active 規則的消費端支援集合：IncomeService(add_gold)／ShopService(shop_discount)／
## BattleSettlementService(heal_expedition_hp)。不在此集合的 kind（如 add_xp）沒有任何
## always-active 消費端，build 時具名拒絕，杜絕「建表成功但效果靜默歸零」。
const _ALWAYS_ACTIVE_SUPPORTED_KINDS: Array[StringName] = [
	&"add_gold", &"shop_discount", &"heal_expedition_hp",
]

var _relic_builder := RunRelicTableBuilder.new()

func build(
	registry: ContentRegistryService,
	manifest_digest: String,
	relic_ids: Array[StringName],
	commander_id: StringName,
	challenge_level: int
) -> RunRelicTableBuildResult:
	if registry == null or manifest_digest.length() != 64:
		return RunRelicTableBuildResult.failure(RunRelicTableError.INPUT_INVALID, &"manifest_digest")
	# 1. relic 規則（slot-gated，source=relic）——沿用既有 builder；失敗直接傳遞其具名結果。
	var relic_result := _relic_builder.build(registry, manifest_digest, relic_ids)
	if not relic_result.ok:
		return relic_result
	var rules: Array[RunRelicRule] = relic_result.table.all_rules()
	# 2. commander 被動（always-active，source=commander）。
	var commander_failure := _append_commander_rules(registry, manifest_digest, commander_id, rules)
	if commander_failure != null:
		return commander_failure
	# 3. challenge 詞綴鏈 1..N（always-active，source=challenge；本波僅建通道）。
	var challenge_failure := _append_challenge_rules(registry, manifest_digest, challenge_level, rules)
	if challenge_failure != null:
		return challenge_failure
	return RunRelicTableBuildResult.success(RunRelicTable.new(manifest_digest, rules))

## 解 commander_id 的 passive_effect_refs 為 always-active 規則，append 進 rules。
## 回 null=成功、非 null=具名失敗（RunRelicTableBuildResult）。
func _append_commander_rules(
	registry: ContentRegistryService, manifest_digest: String,
	commander_id: StringName, rules: Array[RunRelicRule]
) -> RunRelicTableBuildResult:
	var resolved := registry.resolve(ContentRef.new(manifest_digest, commander_id))
	if not resolved.ok:
		return RunRelicTableBuildResult.failure(
			RunRelicTableError.RESOLVE_FAILED, resolved.error.field_path, commander_id
		)
	var view: ContentDefinitionView = resolved.value
	if view.category != &"commander":
		return RunRelicTableBuildResult.failure(
			RunRelicTableError.CATEGORY_MISMATCH, &"category", commander_id
		)
	# CommanderDef payload：3 common ＋ 4 specifics ＝ 7 children；children[4]＝
	# passive_effect_refs（stable_id 清單，見 content_definition_compiler.gd:117）。
	if view.payload == null or view.payload.record_type != ContentCategory.COMMANDER \
		or view.payload.children.size() != 7:
		return RunRelicTableBuildResult.failure(
			RunRelicTableError.PAYLOAD_INVALID, &"commander.payload", commander_id
		)
	var effect_refs := _stable_id_names(view.payload.children[4])
	return _append_source_rules(
		registry, manifest_digest, commander_id, &"commander",
		effect_refs, &"commander.run_operations", rules
	)

## 解 challenge unlock 鏈 1..challenge_level 的 modifier_refs 為 always-active 規則。
## challenge_level 0 無詞綴（不解析任何 unlock）；1..N 逐階累積（design §6.3「詞綴 1..N 累積」）。
## unlock id 慣例：unlock.slice_challenge_%d（見 content/packs/vertical_slice/unlocks/）。
func _append_challenge_rules(
	registry: ContentRegistryService, manifest_digest: String,
	challenge_level: int, rules: Array[RunRelicRule]
) -> RunRelicTableBuildResult:
	for level: int in range(1, challenge_level + 1):
		var unlock_id := StringName("unlock.slice_challenge_%d" % level)
		var resolved := registry.resolve(ContentRef.new(manifest_digest, unlock_id))
		if not resolved.ok:
			return RunRelicTableBuildResult.failure(
				RunRelicTableError.RESOLVE_FAILED, resolved.error.field_path, unlock_id
			)
		var view: ContentDefinitionView = resolved.value
		if view.category != &"unlock":
			return RunRelicTableBuildResult.failure(
				RunRelicTableError.CATEGORY_MISMATCH, &"category", unlock_id
			)
		# UnlockDef payload：3 common ＋ 6 specifics ＝ 9 children；children[8]＝
		# modifier_refs（stable_id 集合，見 content_definition_compiler.gd:121）。
		if view.payload == null or view.payload.record_type != ContentCategory.UNLOCK \
			or view.payload.children.size() != 9:
			return RunRelicTableBuildResult.failure(
				RunRelicTableError.PAYLOAD_INVALID, &"unlock.payload", unlock_id
			)
		var effect_refs := _stable_id_names(view.payload.children[8])
		var failure := _append_source_rules(
			registry, manifest_digest, unlock_id, &"challenge",
			effect_refs, &"challenge.run_operations", rules
		)
		if failure != null:
			return failure
	return null

## 把一個 always-active 來源（commander 或單一 challenge unlock）的 effect_refs 解為 run
## operations，依 kind 對應的 run-layer category 分組，每個非空 category 產出一條 RunRelicRule
## （同一來源同一 category 的所有 operation 合成一條——always_active_count 上等同「一個來源貢獻
## 一份額度」，對齊 MapService 每來源佔一個 anchor 的語意）。
## effect 解碼沿用 RunRelicTableBuilder._append_effect_run_operations（含 claim_scope==always
## 約束與 record-type→kind 對應），避免與既有 relic 解碼分歧（消除 builder 間分歧風險）。
## 回 null=成功、非 null=具名失敗。
func _append_source_rules(
	registry: ContentRegistryService, manifest_digest: String,
	source_id: StringName, source: StringName, effect_refs: Array[StringName],
	failure_path: StringName, rules: Array[RunRelicRule]
) -> RunRelicTableBuildResult:
	var operations: Array[RunRelicOperationRule] = []
	for effect_id: StringName in effect_refs:
		# category 傳 source（commander/challenge）：always-active 路徑無 claim-aware 消費端，
		# _scope_supported 對非 rule category 只放行 always——非 always 的被動/詞綴 intent 在此被拒。
		var error := _relic_builder._append_effect_run_operations(
			registry, manifest_digest, source, effect_id, operations
		)
		if error != &"":
			return RunRelicTableBuildResult.failure(error, failure_path, source_id)
	for operation: RunRelicOperationRule in operations:
		if not _ALWAYS_ACTIVE_SUPPORTED_KINDS.has(operation.kind):
			return RunRelicTableBuildResult.failure(
				RunRelicTableError.UNSUPPORTED_ALWAYS_ACTIVE_KIND, failure_path, source_id
			)
	# 依 kind 對應 category 分組。目前 run 層 always-active 消費端只有 economy（IncomeService
	# add_gold／ShopService shop_discount）與 rule（BattleSettlementService heal_expedition_hp）
	# 兩類；route 佔用由 MapService 對規則計數、無對應 scalar run kind，故 builder 不由 operation
	# 產出 route always-active 規則（route 被動屬未來波次的獨立機制）。決定性順序 economy→rule。
	var economy_operations: Array[RunRelicOperationRule] = []
	var rule_operations: Array[RunRelicOperationRule] = []
	for operation: RunRelicOperationRule in operations:
		if _category_for_kind(operation.kind) == &"rule":
			rule_operations.append(operation)
		else:
			economy_operations.append(operation)
	_append_category_rule(rules, source_id, source, &"economy", effect_refs, economy_operations)
	_append_category_rule(rules, source_id, source, &"rule", effect_refs, rule_operations)
	return null

func _append_category_rule(
	rules: Array[RunRelicRule], source_id: StringName, source: StringName,
	category: StringName, effect_refs: Array[StringName],
	operations: Array[RunRelicOperationRule]
) -> void:
	if operations.is_empty():
		return
	var rule := RunRelicRule.new()
	rule.relic_id = source_id
	rule.category = category
	rule.source = source
	rule.effect_ids = effect_refs.duplicate()
	rule.run_operations = operations
	rules.append(rule)

## run operation kind → run-layer category（消費端讀取的 category 反推）：
## heal_expedition_hp→rule（BattleSettlementService）；add_gold/shop_discount→economy
## （IncomeService／ShopService）。不在 _ALWAYS_ACTIVE_SUPPORTED_KINDS 的 kind（如 add_xp）
## 已於 _append_source_rules 具名拒絕，到不了本函式。
func _category_for_kind(kind: StringName) -> StringName:
	if kind == &"heal_expedition_hp":
		return &"rule"
	return &"economy"

func _stable_id_names(value: ContentValue) -> Array[StringName]:
	var result: Array[StringName] = []
	if value == null:
		return result
	for child: ContentValue in value.children:
		result.append(StringName(child.string_value))
	return result
