class_name ContentValidator
extends RefCounted

const PLAYER_COST_DISTRIBUTION := [10, 8, 6, 5, 3]
const NODE_TYPES: Array[StringName] = [&"normal", &"elite", &"merchant", &"event", &"rest", &"treasure", &"boss"]
const EFFECT_TRIGGERS: Array[StringName] = [&"battle_start", &"attack", &"hit", &"damaged", &"cast", &"kill", &"death", &"periodic", &"battle_end"]
const EFFECT_CONDITIONS: Array[StringName] = [&"source_tag", &"target_tag", &"health_below_bps", &"health_above_bps", &"distance_at_most", &"distance_at_least", &"has_status", &"lacks_status", &"has_equipment", &"max_uses_per_battle"]
const STACKING_RULES: Array[StringName] = [&"replace", &"refresh_duration", &"add_stacks", &"independent"]
const BASIC_ATTACK_PROFILES: Array[StringName] = [&"melee", &"ranged", &"magic_projectile"]
const SHOP_CONDITIONS: Array[StringName] = [&"always", &"unlocked", &"event_only", &"never"]
const RELIC_CATEGORIES: Array[StringName] = [&"battle", &"economy", &"route", &"rule"]
const OPERATION_TARGETS: Array[StringName] = [
	&"self", &"target", &"all_allies", &"all_enemies",
]
const MODIFY_STAT_NAMES: Array[StringName] = [
	&"attack", &"armor", &"magic_resist", &"attack_speed_milli", &"move_speed_milli",
]
const GLOBAL_MODIFY_STAT_NAMES: Array[StringName] = [
	&"attack", &"armor", &"magic_resist", &"attack_speed_milli", &"move_speed_milli",
]
const DAMAGE_TYPES: Array[StringName] = [&"physical", &"magical", &"true"]
const GLOBAL_SOURCE_TRIGGERS: Array[StringName] = [
	&"battle_start", &"periodic", &"battle_end",
]
## challenge 詞綴專用的 content_role。
const CHALLENGE_AFFIX_ROLE: StringName = &"challenge_affix"
## S5-AC-005（design §7.2）：MetaRewardTableDef.challenge_multiplier_bps 每筆的乘數下限
## （100%，無折扣乘數的合理理由）。
const CHALLENGE_MULTIPLIER_MINIMUM_BPS: int = 10000

var _issues: Array[ContentValidationIssue] = []
var _by_id: Dictionary = {}
var _compiler := ContentDefinitionCompilerV3.new()
var _stable_id_validator := StableIdValidator.new()

func validate(input: ContentValidationInput) -> ContentValidationReport:
	_issues.clear()
	_by_id.clear()
	var report := ContentValidationReport.new()
	if input == null:
		return ContentValidationReport.failure(&"CONTENT_VALIDATION_FAILED", &"input")
	_index_and_validate_ids(input)
	_validate_dependencies(input)
	_validate_v3_definitions(input)
	_validate_units_and_traits(input.definitions)
	_validate_recipes(input.definitions)
	_validate_minimum_counts_and_nodes(input.definitions)
	_validate_relics(input.definitions)
	_validate_challenge_chain(input.definitions)
	_validate_always_only_claim_scope(input.definitions)
	_validate_commander_passive_diversity(input.definitions)
	_validate_economy(input.definitions)
	_validate_rewards(input.definitions)
	_validate_challenge_multiplier_coverage(input.definitions)
	_validate_unlock_graph(input.definitions)
	_validate_meta_forbidden_growth(input.definitions)
	_validate_operations(input.definitions)
	_validate_global_effect_source_lifecycle(input.definitions)
	_validate_encounter_sources(input.definitions)
	_calculate_population_and_entities(input, report)
	_validate_combat_config(input.definitions, report.entity_stress_minimum)
	_issues.sort_custom(_issue_less)
	report.valid = _issues.is_empty()
	for issue in _issues: report.issues.append(issue.deep_clone())
	return report

func _index_and_validate_ids(input: ContentValidationInput) -> void:
	var names: Dictionary = {}
	for definition in input.definitions:
		if definition == null:
			_issue(&"CONTENT_STABLE_ID", &"", &"definition", "null")
			continue
		if not _stable_id_validator.is_valid(definition.id):
			_issue(&"CONTENT_STABLE_ID", definition.id, &"id")
		if names.has(definition.id):
			_issue(&"CONTENT_STABLE_ID", definition.id, &"id", "duplicate")
		else:
			names[definition.id] = &"active"
			_by_id[definition.id] = definition
	for alias in input.aliases:
		if not _stable_id_validator.is_valid(alias.source_id) or not _stable_id_validator.is_valid(alias.target_id) or names.has(alias.source_id):
			_issue(&"CONTENT_STABLE_ID", alias.source_id, &"alias")
		else:
			names[alias.source_id] = &"alias"
	for tombstone in input.tombstones:
		if not _stable_id_validator.is_valid(tombstone.original_id) or names.has(tombstone.original_id):
			_issue(&"CONTENT_STABLE_ID", tombstone.original_id, &"tombstone")
		else:
			names[tombstone.original_id] = &"tombstone"
	var alias_targets: Dictionary = {}
	for alias in input.aliases: alias_targets[alias.source_id] = alias.target_id
	for alias in input.aliases:
		var visited: Dictionary = {}
		var cursor: StringName = alias.source_id
		while alias_targets.has(cursor):
			if visited.has(cursor):
				_issue(&"CONTENT_STABLE_ID", alias.source_id, &"alias", "cycle")
				break
			visited[cursor] = true
			cursor = alias_targets[cursor] as StringName
		if not names.has(cursor): _issue(&"CONTENT_STABLE_ID", alias.source_id, &"alias.target", "missing")

func _validate_dependencies(input: ContentValidationInput) -> void:
	for definition in input.definitions:
		if definition == null: continue
		for reference in _compiler.collect_references(definition):
			if not _by_id.has(reference): _issue(&"CONTENT_REFERENCE_MISSING", definition.id, &"references", String(reference))
		if definition.display_name_key.is_empty() or input.dependency_port == null or not input.dependency_port.localization_key_exists(definition.display_name_key):
			_issue(&"CONTENT_LOCALIZATION_MISSING", definition.id, &"display_name_key", String(definition.display_name_key))
		for asset_path in definition.asset_refs:
			if input.dependency_port == null or not input.dependency_port.asset_exists(asset_path):
				_issue(&"CONTENT_ASSET_MISSING", definition.id, &"asset_refs", asset_path)
		if definition is TraitDef:
			_validate_localization(input, definition.id, definition.description_key, &"description_key")
		elif definition is AbilityDef:
			_validate_localization(input, definition.id, definition.description_key, &"description_key")
		elif definition is EffectDef:
			_validate_localization(
				input, definition.id, definition.description_key, &"description_key"
			)


func _validate_v3_definitions(input: ContentValidationInput) -> void:
	for definition: ContentDefinition in input.definitions:
		if definition is UnitPresentationDef:
			var presentation := definition as UnitPresentationDef
			if (
				presentation.portrait_path.is_empty()
				or not presentation.portrait_path.ends_with(".png")
				or presentation.sprite_frames_path.is_empty()
				or not presentation.sprite_frames_path.ends_with(".tres")
				or presentation.board_icon_path.is_empty()
				or not presentation.board_icon_path.ends_with(".png")
				or presentation.ability_icon_path.is_empty()
				or not presentation.ability_icon_path.ends_with(".png")
			):
				_issue(
					&"CONTENT_PRESENTATION_PATH_INVALID",
					definition.id,
					&"presentation_paths"
				)
		elif definition is AudioCueDef:
			var audio := definition as AudioCueDef
			if audio.bus not in [&"Master", &"Music", &"SFX", &"UI"] \
				or not audio.stream_path.ends_with(".ogg"):
				_issue(
					&"CONTENT_AUDIO_CUE_INVALID",
					definition.id,
					&"audio_cue"
				)
		elif definition is NodeChoiceSetDef:
			_validate_node_choice_set(
				input, definition as NodeChoiceSetDef
			)


func _validate_node_choice_set(
	input: ContentValidationInput,
	choice_set: NodeChoiceSetDef
) -> void:
	if choice_set.node_kind not in [&"event", &"rest", &"treasure"]:
		_issue(
			&"CONTENT_NODE_CHOICE_INVALID",
			choice_set.id,
			&"node_kind"
		)
		return
	var minimum := 3 if choice_set.node_kind == &"treasure" else 2
	if choice_set.choices.size() < minimum:
		_issue(
			&"CONTENT_NODE_CHOICE_INVALID", choice_set.id, &"choices"
		)
	var ids: Dictionary = {}
	var previous_order := -1
	for choice: NodeChoiceDef in choice_set.choices:
		if (
			choice == null
			or not _stable_id_validator.is_valid(choice.choice_id)
			or ids.has(choice.choice_id)
			or choice.sort_order <= previous_order
			or choice.outcome_kind not in [
				NodeChoiceDef.OutcomeKind.APPLY_AND_COMPLETE,
				NodeChoiceDef.OutcomeKind.OPEN_DISMANTLE_SERVICE,
				NodeChoiceDef.OutcomeKind.OPEN_REWARD_STAGE,
			]
		):
			_issue(
				&"CONTENT_NODE_CHOICE_INVALID",
				choice_set.id,
				&"choices"
			)
			continue
		ids[choice.choice_id] = true
		previous_order = choice.sort_order
		for pair: Array in [
			[choice.title_key, &"title_key"],
			[choice.description_key, &"description_key"],
			[choice.preview_key, &"preview_key"],
			[choice.result_key, &"result_key"],
		]:
			_validate_localization(
				input, choice_set.id, pair[0], pair[1]
			)
		_validate_run_operations(
			choice_set.id,
			choice.operations,
			&"choices.operations",
			&"node_choice",
			false,
			true
		)

func _validate_localization(input: ContentValidationInput, source_id: StringName, key: StringName, path: StringName) -> void:
	if key.is_empty() or input.dependency_port == null or not input.dependency_port.localization_key_exists(key):
		_issue(&"CONTENT_LOCALIZATION_MISSING", source_id, path, String(key))

func _validate_units_and_traits(definitions: Array[ContentDefinition]) -> void:
	var players: Array[UnitDef] = []
	var faction_count := 0
	var role_count := 0
	var three_tag_count := 0
	var cost_counts := PackedInt32Array([0, 0, 0, 0, 0])
	var trait_members: Dictionary = {}
	for definition in definitions:
		if definition is TraitDef:
			var trait_definition := definition as TraitDef
			if trait_definition.trait_kind == &"faction": faction_count += 1
			elif trait_definition.trait_kind == &"role": role_count += 1
		if definition is UnitDef:
			var unit := definition as UnitDef
			_validate_unit_schema(unit)
			if unit.availability not in [&"player", &"shared"]: continue
			players.append(unit)
			if unit.cost_tier >= 1 and unit.cost_tier <= 5: cost_counts[unit.cost_tier - 1] += 1
			if unit.trait_refs.size() == 3: three_tag_count += 1
			for trait_id in unit.trait_refs:
				trait_members[trait_id] = int(trait_members.get(trait_id, 0)) + 1
	if players.size() != 32: _issue(&"CONTENT_UNIT_COUNT", &"catalog.units", &"players", str(players.size()))
	var distribution_matches := cost_counts.size() == PLAYER_COST_DISTRIBUTION.size()
	for index in cost_counts.size():
		if cost_counts[index] != PLAYER_COST_DISTRIBUTION[index]: distribution_matches = false
	if not distribution_matches: _issue(&"CONTENT_COST_DISTRIBUTION", &"catalog.units", &"cost_tier", str(cost_counts))
	if faction_count != 6 or role_count != 6: _issue(&"CONTENT_TRAIT_KIND_COUNT", &"catalog.traits", &"trait_kind", "%d/%d" % [faction_count, role_count])
	if three_tag_count != 4: _issue(&"CONTENT_THREE_TAG_COUNT", &"catalog.units", &"trait_refs", str(three_tag_count))
	for definition in definitions:
		if definition is TraitDef:
			var available := int(trait_members.get(definition.id, 0))
			var previous := 0
			for threshold in definition.thresholds:
				if threshold == null or threshold.required_count <= previous or threshold.required_count > available:
					_issue(&"CONTENT_TRAIT_THRESHOLD_UNREACHABLE", definition.id, &"thresholds", str(available))
					break
				previous = threshold.required_count

func _validate_unit_schema(unit: UnitDef) -> void:
	if unit.base_stats == null:
		_issue(&"CONTENT_OPERATION_INVALID", unit.id, &"base_stats", "missing")
	else:
		var stats := unit.base_stats
		if stats.health <= 0 or stats.attack <= 0 or stats.attack_speed_milli <= 0 or stats.attack_range_cells <= 0 or stats.max_mana <= 0 or stats.move_speed_milli <= 0:
			_issue(&"CONTENT_OPERATION_INVALID", unit.id, &"base_stats", "range")
	if not BASIC_ATTACK_PROFILES.has(unit.basic_attack_profile): _issue(&"CONTENT_OPERATION_INVALID", unit.id, &"basic_attack_profile")
	if not SHOP_CONDITIONS.has(unit.shop_condition): _issue(&"CONTENT_OPERATION_INVALID", unit.id, &"shop_condition")
	var stars := PackedInt32Array()
	for scaling in unit.star_scalings:
		if scaling == null: continue
		stars.append(scaling.star)
		var values := PackedInt32Array([scaling.health_bps, scaling.attack_bps, scaling.armor_bps, scaling.magic_resist_bps,
			scaling.attack_speed_bps, scaling.attack_range_bps, scaling.start_mana_bps, scaling.max_mana_bps, scaling.move_speed_bps])
		for value in values:
			if value < 1 or value > 100000: _issue(&"CONTENT_OPERATION_INVALID", unit.id, &"star_scalings", "range")
	stars.sort()
	if stars != PackedInt32Array([1, 2, 3]): _issue(&"CONTENT_OPERATION_INVALID", unit.id, &"star_scalings", "stars")

func _validate_recipes(definitions: Array[ContentDefinition]) -> void:
	var components: Array[StringName] = []
	var recipes: Dictionary = {}
	for definition in definitions:
		if definition is ItemComponentDef: components.append(definition.id)
	if components.size() != 6: _issue(&"CONTENT_COMPONENT_COUNT", &"catalog.components", &"count", str(components.size()))
	components.sort_custom(_string_name_less)
	for definition in definitions:
		if not definition is EquipmentDef: continue
		if definition.component_pair.size() < 1 or definition.component_pair.size() > 2:
			_issue(&"CONTENT_RECIPE_COVERAGE", definition.id, &"component_pair", "count")
			continue
		var pair: Array[StringName] = definition.component_pair.duplicate()
		pair.sort_custom(_string_name_less)
		var key := String(pair[0]) + "+" + String(pair[0] if pair.size() == 1 else pair[1])
		if not components.has(pair[0]) or (pair.size() == 2 and not components.has(pair[1])) or recipes.has(key):
			_issue(&"CONTENT_RECIPE_COVERAGE", definition.id, &"component_pair", key)
		else: recipes[key] = definition.id
	var expected := 0
	for left in components.size():
		for right in range(left, components.size()):
			expected += 1
			var key := String(components[left]) + "+" + String(components[right])
			if not recipes.has(key): _issue(&"CONTENT_RECIPE_COVERAGE", &"catalog.equipment", &"component_pair", key)
	if expected != 21 or recipes.size() != 21: _issue(&"CONTENT_RECIPE_COVERAGE", &"catalog.equipment", &"count", str(recipes.size()))

func _validate_minimum_counts_and_nodes(definitions: Array[ContentDefinition]) -> void:
	var relics := 0
	var commanders := 0
	var monsters := 0
	var affixes := 0
	var bosses := 0
	var event_generators: Dictionary = {}
	var node_types: Array[StringName] = []
	var node_type_counts: Dictionary = {}
	for definition in definitions:
		if definition is RelicDef: relics += 1
		elif definition is CommanderDef: commanders += 1
		elif definition is UnitDef and definition.availability == &"monster": monsters += 1
		elif definition is EffectDef and definition.content_role == &"elite_affix": affixes += 1
		elif definition is EncounterDef and definition.encounter_kind == &"boss": bosses += 1
		elif definition is MapNodeDef:
			if not node_types.has(definition.node_type): node_types.append(definition.node_type)
			node_type_counts[definition.node_type] = int(node_type_counts.get(definition.node_type, 0)) + 1
			if definition.node_type == &"event": event_generators[definition.generator_ref] = true
			if definition.node_type in [&"normal", &"elite", &"boss"]:
				var generator: ContentDefinition = _by_id.get(
					definition.generator_ref, null
				)
				if not generator is EncounterDef \
					or generator.encounter_kind != definition.node_type:
					_issue(
						&"CONTENT_NODE_GENERATOR", definition.id,
						&"generator_ref", String(definition.generator_ref)
					)
	if relics < 15 or commanders != 3 or monsters < 12 or affixes < 6 or bosses != 3 or event_generators.size() < 12:
		_issue(&"CONTENT_MINIMUM_COUNTS", &"catalog.minimums", &"counts", "%d/%d/%d/%d/%d/%d" % [relics, commanders, monsters, affixes, bosses, event_generators.size()])
	node_types.sort_custom(_string_name_less)
	var expected := NODE_TYPES.duplicate()
	expected.sort_custom(_string_name_less)
	if node_types != expected: _issue(&"CONTENT_NODE_KIND_COVERAGE", &"catalog.nodes", &"node_type", str(node_types))
	# MapService 在 layer 1/3 的 branch anchor 上把 route 遺物觸發的 kind 覆寫
	# NORMAL -> ELITE，且不消耗額外的 stream draw；覆寫後 rule_draw 的 bound 取自
	# EconomyExpeditionCatalog.map_nodes_for(kind).size()，所以 NORMAL 與 ELITE 兩種
	# node kind 的規則筆數必須相等，否則覆寫前後的 RNG 消耗量會分歧、破壞決定性。
	var normal_count := int(node_type_counts.get(&"normal", 0))
	var elite_count := int(node_type_counts.get(&"elite", 0))
	if normal_count != elite_count:
		_issue(
			&"CONTENT_MAP_NODE_RULE_COUNT_PARITY", &"catalog.nodes", &"node_type",
			"normal=%d/elite=%d" % [normal_count, elite_count]
		)

func _validate_relics(definitions: Array[ContentDefinition]) -> void:
	var seen_categories: Dictionary = {}
	for definition in definitions:
		if not definition is RelicDef: continue
		var relic := definition as RelicDef
		if not RELIC_CATEGORIES.has(relic.category):
			_issue(&"CONTENT_RELIC_CATEGORY", relic.id, &"category", String(relic.category))
		else:
			seen_categories[relic.category] = true
			_validate_relic_effect_scope(relic, relic.category == &"battle")
		if relic.activation_limit < 1 or relic.activation_limit > 99:
			_issue(&"CONTENT_RELIC_ACTIVATION_LIMIT", relic.id, &"activation_limit", str(relic.activation_limit))
	for category in RELIC_CATEGORIES:
		if not seen_categories.has(category):
			_issue(&"CONTENT_RELIC_CATEGORY_COVERAGE", &"catalog.relics", &"category", String(category))

func _validate_relic_effect_scope(relic: RelicDef, require_battle_operations: bool) -> void:
	if relic.effect_refs.is_empty():
		_issue(&"CONTENT_RELIC_EFFECT_EMPTY", relic.id, &"effect_refs")
		return
	for effect_id in relic.effect_refs:
		var effect: ContentDefinition = _by_id.get(effect_id)
		if not effect is EffectDef:
			_issue(&"CONTENT_RELIC_EFFECT_SCOPE", relic.id, &"effect_refs", String(effect_id))
			continue
		var effect_definition := effect as EffectDef
		if require_battle_operations:
			if effect_definition.battle_operations.is_empty():
				_issue(&"CONTENT_RELIC_EFFECT_SCOPE", relic.id, &"effect_refs", String(effect_id))
			continue
		if effect_definition.run_operations.is_empty():
			_issue(&"CONTENT_RELIC_EFFECT_SCOPE", relic.id, &"effect_refs", String(effect_id))
			continue
		# W4-F1（2026-07-24 使用者裁決）：非 battle 類遺物（economy/route/rule）引用的效果，其
		# run intent 由 run-layer service（IncomeService/ShopService…）逐節點無條件消費——
		# RunRelicTable.sum_operation_amount 不看 claim_scope，語意等同 always。故要求這些
		# run_operations 的 claim_scope 一律為 &"always"，讓宣告的 scope 與實際消費行為一致，並與
		# RunRelicTableBuilder 的 UNSUPPORTED_INTENT 守衛對齊（消除 validator↔builder 分歧）。
		# 允許效果同時帶 battle_operations（混合效果）——其戰鬥部分不被 run layer 消費、屬 battle
		# 類遺物作用域；此規則只約束會被 run layer 消費的 scalar run 部分。
		for operation: RunOperationDef in effect_definition.run_operations:
			if _is_scalar_run_operation(operation) \
				and _scalar_run_claim_scope(operation) != &"always" \
					and not _relic_claim_scope_consumed(relic.category, operation):
				_issue(&"CONTENT_RELIC_EFFECT_SCOPE", relic.id, &"effect_refs", "%s:claim_scope" % String(effect_id))
				break

## claim_scope 消費判準（S5-AC-013／design §6.4）：非 battle 遺物的 scalar run intent 只有在其
## (category, operation) 消費端具 claim-aware 去重時，才可宣告 once_per_node/on_first_clear。目前唯一
## 具此消費的作用點是 BattleSettlementService 對 (rule, heal_expedition_hp) 的規則遺物遠征 HP 修正；
## economy/route 消費端仍逐節點無條件加總，故其 scalar intent 續守 always。與 RunRelicTableBuilder.
## _scope_supported 同判準（消除 validator↔builder 分歧）。
func _relic_claim_scope_consumed(category: StringName, operation: RunOperationDef) -> bool:
	return category == &"rule" and operation is HealExpeditionHpOperationDef

## W4-F（Sonnet#4）修正（2026-07-25）：commander/challenge 來源的 run_operations 走完全不同
## 的 always-active 消費路徑（RunModifierTableBuilder._append_source_rules→_scope_supported，
## category 傳入固定是 &"commander"/&"challenge"，永遠不等於 &"rule"）——沒有 claim-aware
## 消費端例外，只認 &"always"（_relic_claim_scope_consumed 的 rule×heal 例外只服務 RelicDef
## 路徑，commander/challenge 沒有對應消費端）。這條規則之前只掛在 _validate_relic_effect_scope
## （僅涵蓋 RelicDef.effect_refs），UnlockDef(challenge).modifier_refs 與
## CommanderDef.passive_effect_refs 引用的效果完全沒被驗證器檢查過，形成「install_validated
## 通過、RunModifierTableBuilder.build() 才具名失敗」的時間差（內容作者誤設
## once_per_node/on_first_clear 時）。判準與 RunRelicTableBuilder._scope_supported 對齊。
func _validate_always_only_claim_scope(definitions: Array[ContentDefinition]) -> void:
	for definition in definitions:
		if definition is UnlockDef and (definition as UnlockDef).unlock_kind == &"challenge":
			_validate_effect_refs_always_only(
				definition.id, (definition as UnlockDef).modifier_refs, &"modifier_refs"
			)
		elif definition is CommanderDef:
			_validate_effect_refs_always_only(
				definition.id, (definition as CommanderDef).passive_effect_refs, &"passive_effect_refs"
			)
			for effect_id: StringName in (
				definition as CommanderDef
			).passive_effect_refs:
				var passive: ContentDefinition = _by_id.get(effect_id)
				if passive is EffectDef \
					and not (passive as EffectDef).battle_operations.is_empty() \
					and not (passive as EffectDef).run_operations.is_empty():
					_issue(
						&"CONTENT_COMMANDER_PASSIVE_MIXED_SCOPE",
						definition.id,
						&"passive_effect_refs",
						String(effect_id)
					)

func _validate_effect_refs_always_only(
	source_id: StringName, effect_refs: Array[StringName], field_path: StringName
) -> void:
	for effect_id in effect_refs:
		var effect: ContentDefinition = _by_id.get(effect_id)
		if not effect is EffectDef:
			continue
		for operation: RunOperationDef in (effect as EffectDef).run_operations:
			if _is_scalar_run_operation(operation) and _scalar_run_claim_scope(operation) != &"always":
				_issue(&"CONTENT_RELIC_EFFECT_SCOPE", source_id, field_path, "%s:claim_scope" % String(effect_id))
				break

## T10（架構規格 docs/game-architecture/04-content-and-meta-progression.md:81／design.md
## §7.2）：「三名指揮官的優勢不得只是相同被動的數值階級」。判準（W5 雙審 A6 裁定修正，見
## .pipeline/reviews/2026-07-25-reviewer-w5.md）：只在內容集合中恰有 3 個 CommanderDef 時檢查
## （對齊 CONTENT_MINIMUM_COUNTS 對 commanders 數量的既有硬性要求，恆為 3）；把每位指揮官
## passive_effect_refs 解析出的 EffectDef 的 battle_operations∪run_operations 各自的
## operation_type() 收斂成一個機制簽章（忽略 amount/duration 等數值欄位——「只有數值不同」正是
## 本規則要放行的差異）；**兩兩比對**，任兩名的非空機制簽章相等即回一筆聚合 issue（「兩名共用
## 同一被動機制、只有數值不同」就是 §7.2 字面的「相同被動的數值階級」，不須三者全同才觸發）；
## 簽章為空（未著作任何 battle/run operation）的指揮官不參與比對——尚未著作被動屬另一層內容
## 完整性問題，本規則不越權去管，避免「三者皆無被動」被誤判為同質。
func _validate_commander_passive_diversity(definitions: Array[ContentDefinition]) -> void:
	var commanders: Array[CommanderDef] = []
	for definition in definitions:
		if definition is CommanderDef: commanders.append(definition as CommanderDef)
	if commanders.size() != 3: return
	var signatures: Array[Array] = []
	for commander in commanders: signatures.append(_commander_passive_signature(commander))
	for i in range(signatures.size()):
		if signatures[i].is_empty(): continue
		for j in range(i + 1, signatures.size()):
			if signatures[j].is_empty(): continue
			if signatures[i] == signatures[j]:
				_issue(&"CONTENT_COMMANDER_PASSIVE_HOMOGENEOUS", &"catalog.commanders", &"passive_effect_refs")
				return

## 指揮官被動的「機制簽章」：passive_effect_refs 解析出的所有效果的 battle/run operation
## operation_type() 聯集，去重排序後回傳，供 _validate_commander_passive_diversity 兩兩比較。
func _commander_passive_signature(commander: CommanderDef) -> Array[int]:
	var types: Dictionary = {}
	for effect_id in commander.passive_effect_refs:
		var effect: ContentDefinition = _by_id.get(effect_id)
		if not effect is EffectDef: continue
		for operation: BattleOperationDef in (effect as EffectDef).battle_operations:
			types[operation.operation_type()] = true
		for operation: RunOperationDef in (effect as EffectDef).run_operations:
			types[operation.operation_type()] = true
	var result: Array[int] = []
	for key in types.keys(): result.append(int(key))
	result.sort()
	return result

func _validate_challenge_chain(definitions: Array[ContentDefinition]) -> void:
	var levels: Dictionary = {}
	for definition in definitions:
		if definition is UnlockDef and definition.unlock_kind == &"challenge":
			if levels.has(definition.challenge_level): _issue(&"CONTENT_CHALLENGE_CHAIN", definition.id, &"challenge_level", "duplicate")
			levels[definition.challenge_level] = definition
	for level in range(0, 6):
		if not levels.has(level):
			_issue(&"CONTENT_CHALLENGE_CHAIN", &"catalog.challenge", &"challenge_level", str(level))
			continue
		var unlock: UnlockDef = levels[level]
		if level == 0 and not unlock.prerequisite_refs.is_empty(): _issue(&"CONTENT_CHALLENGE_CHAIN", unlock.id, &"prerequisite_refs", "level0")
		if level > 0:
			if not levels.has(level - 1): continue
			var previous: UnlockDef = levels[level - 1]
			if unlock.prerequisite_refs.size() != 1 or unlock.prerequisite_refs[0] != previous.id:
				_issue(&"CONTENT_CHALLENGE_CHAIN", unlock.id, &"prerequisite_refs", "gap")
			# BP-SI-001（已解除，見 res://specs/balance-playtest/spec-issues.md）：鏈結構本身
			# （level 序列／prerequisite）不要求每個 unlock 都有非空 modifier_refs——是否覆蓋
			# 三桶由 _validate_challenge_affix_roles 聚合判定；slice_challenge_affix_02
			# （BP-SI-002，續 OPEN）仍刻意不連線，level 3 因此維持空 modifier_refs，非鏈結構缺失。
	_validate_challenge_affix_roles(levels)

## design §7.2（S5-AC-010）：challenge 鏈 1..5 的 modifier_refs 必須指向 challenge 詞綴自己的
## 效果，且五條合起來要覆蓋雙軌的三個可機械判別的桶。
## - **角色**：modifier_refs 引用的效果 content_role 必須恰為 &"challenge_affix"（T10 收緊，
##   design §7.2 字面要求）——引用到別的內容槽位所著作的效果（典型即菁英詞綴 elite_affix）或
##   未分類的預設角色 &"general" 皆視為內容編排錯誤，逐效果具名拒絕，不再放行預設角色。
## - **覆蓋**：軌 A（battle_operations 非空）／經濟壓力（ShopSurcharge）／遠征傷害
##   （DrainExpeditionHp）三桶缺一即回一筆聚合 issue。只在鏈上真的著作了詞綴時才檢查，
##   避免對「尚未著作 modifier_refs」的內容重複回報（那是 CONTENT_CHALLENGE_CHAIN 的職責）。
##   design §7.1/requirements.md 的「四類」（敵人編成/遭遇規則/經濟壓力/遠征傷害）中，前兩類
##   （敵人編成、遭遇規則）皆機械對應軌 A 這同一個桶——schema 無法再細分，本規則只驗證三桶
##   聯集覆蓋，不強加軌 A 內部二次分類；「軌 A 內容須同時體現敵人編成與遭遇規則兩種語意」是
##   內容著作面的責任（W4-F6，2026-07-25：見 content/packs/vertical_slice/effects/
##   slice_challenge_affix_02.tres 以 MoveOperationDef 表達遭遇規則，區別於其餘軌 A 詞綴的
##   ModifyStatOperationDef 敵人編成），驗證器結構上偵測不到這個內容多樣性缺口。
func _validate_challenge_affix_roles(levels: Dictionary) -> void:
	var affix_effects: Array[EffectDef] = []
	var authored := false
	for level in range(1, 6):
		if not levels.has(level): continue
		var unlock: UnlockDef = levels[level]
		for effect_id: StringName in unlock.modifier_refs:
			authored = true
			var definition: ContentDefinition = _by_id.get(effect_id)
			if definition == null: continue
			if not definition is EffectDef or (definition as EffectDef).content_role != CHALLENGE_AFFIX_ROLE:
				_issue(&"CONTENT_CHALLENGE_AFFIX_ROLE", effect_id, &"modifier_refs", String(unlock.id))
				continue
			var effect := definition as EffectDef
			if effect.content_role == CHALLENGE_AFFIX_ROLE and not affix_effects.has(effect):
				affix_effects.append(effect)
	if not authored: return
	var battle_track := false
	var shop_surcharge := false
	var expedition_drain := false
	for effect: EffectDef in affix_effects:
		if not effect.battle_operations.is_empty(): battle_track = true
		for operation: RunOperationDef in effect.run_operations:
			if operation is ShopSurchargeOperationDef: shop_surcharge = true
			elif operation is DrainExpeditionHpOperationDef: expedition_drain = true
	if battle_track and shop_surcharge and expedition_drain: return
	_issue(
		&"CONTENT_CHALLENGE_AFFIX_COVERAGE", &"catalog.challenge_affix", &"modifier_refs",
		"battle=%s/surcharge=%s/drain=%s" % [battle_track, shop_surcharge, expedition_drain]
	)

func _validate_economy(definitions: Array[ContentDefinition]) -> void:
	var has_meta_reward_table := false
	for definition in definitions:
		if definition is MetaRewardTableDef: has_meta_reward_table = true
		if not definition is EconomyConfigDef: continue
		var levels_seen: Dictionary = {}
		for row in definition.shop_odds_by_level:
			var total := 0
			for odds in row.tier_basis_points: total += odds
			if row.tier_basis_points.size() != 5 or total != 10000: _issue(&"CONTENT_SHOP_PROBABILITY", definition.id, &"shop_odds_by_level", str(row.level))
			levels_seen[row.level] = true
		for level in range(3, 10):
			if not levels_seen.has(level): _issue(&"CONTENT_SHOP_PROBABILITY", definition.id, &"shop_odds_by_level", str(level))
		var tiers: Dictionary = {}
		for pair in definition.pool_copies_by_tier:
			tiers[pair.key_u32] = pair.value_u32
		for tier in range(1, 6):
			if int(tiers.get(tier, 0)) < 9: _issue(&"CONTENT_POOL_COPIES", definition.id, &"pool_copies_by_tier", str(tier))
		# 以下鏡射 EconomyExpeditionCatalogBuilder._valid_config() 的必填欄位檢查——
		# 驗證器放行但 builder 拒絕即為分歧缺陷（T11 wave4 實測發現，見 HANDOFF.md）。
		if definition.layer_income.is_empty() or definition.interest_step_gold < 1 \
			or definition.gold_cap < 1 or definition.reroll_cost < 0 \
			or definition.xp_buy_cost < 1 or definition.xp_buy_amount < 1:
			_issue(&"CONTENT_ECONOMY_CONFIG_INCOMPLETE", definition.id, &"economy_config", "scalar")
		var costs: Dictionary = {}
		for pair in definition.unit_costs_by_tier: costs[pair.key_u32] = pair.value_u32
		for tier in range(1, 6):
			if int(costs.get(tier, 0)) < 1:
				_issue(&"CONTENT_ECONOMY_CONFIG_INCOMPLETE", definition.id, &"unit_costs_by_tier", str(tier))
		var xp_levels: Dictionary = {}
		for pair in definition.xp_thresholds: xp_levels[pair.key_u32] = pair.value_u32
		# W5 雙審 B5 裁定修正：一個新遠征從 economy level 1 起步
		# (RunBootstrapService.STARTING_ECONOMY_LEVEL)，門檻必須從 level 1 覆蓋到 8，
		# 不能只驗 3..8——否則驗證器放行、EconomyExpeditionCatalogBuilder._valid_config()
		# 卻拒絕的分歧會重演（見 tests/integration/meta_progression/
		# test_vertical_slice_xp_threshold_gap.gd）。
		for level in range(1, 9):
			if int(xp_levels.get(level, 0)) < 1:
				_issue(&"CONTENT_ECONOMY_CONFIG_INCOMPLETE", definition.id, &"xp_thresholds", str(level))
	if not has_meta_reward_table:
		_issue(&"CONTENT_META_REWARD_TABLE_MISSING", &"catalog.meta_reward_table", &"category")

## T10（design §7.2／§9「乘數單一權威＝表內 bps 欄」、§7.3「Challenge 1–5 最後乘以
## 100%+10%×challenge_level」）：MetaRewardTableDef.challenge_multiplier_bps 必須恰好覆蓋
## challenge_level 0..5（不缺漏、不含範圍外的 level——集合必須恰等於 {0,1,2,3,4,5}），且每筆
## basis_points 不得低於 100%（10000 bps，沒有折扣乘數的合理理由）。兩種違規任一成立即回一筆
## 聚合 issue（比照 CONTENT_ECONOMY_CONFIG_INCOMPLETE 的聚合風格）。
func _validate_challenge_multiplier_coverage(definitions: Array[ContentDefinition]) -> void:
	for definition in definitions:
		if not definition is MetaRewardTableDef: continue
		var table := definition as MetaRewardTableDef
		var levels_seen: Dictionary = {}
		var below_minimum := false
		for multiplier: ChallengeMultiplierDef in table.challenge_multiplier_bps:
			if multiplier == null: continue
			levels_seen[multiplier.challenge_level] = true
			if multiplier.basis_points < CHALLENGE_MULTIPLIER_MINIMUM_BPS: below_minimum = true
		var covers_exactly := levels_seen.size() == 6
		if covers_exactly:
			for level in range(0, 6):
				if not levels_seen.has(level):
					covers_exactly = false
					break
		if not covers_exactly or below_minimum:
			_issue(&"CONTENT_CHALLENGE_MULTIPLIER_COVERAGE", table.id, &"challenge_multiplier_bps")

func _validate_rewards(definitions: Array[ContentDefinition]) -> void:
	var has_standard := false
	var has_relic := false
	var has_event := false
	for definition in definitions:
		if not definition is RewardTableDef: continue
		var usable := 0
		var relic_candidates := 0
		var non_relic_candidates := 0
		var non_unit_candidates := 0
		var unconditional_relic := 0
		var unconditional_non_unit := 0
		var unconditional_non_relic := 0
		for candidate in definition.reward_candidates:
			for condition: ConditionDef in candidate.conditions:
				_validate_reward_condition(definition.id, condition)
			if candidate.kind == &"item" and candidate.has_content_ref \
				and _by_id.get(candidate.content_ref) is ItemComponentDef:
				_issue(&"CONTENT_ITEM_GRANT_COMPONENT", definition.id, &"reward_candidates", String(candidate.content_ref))
			if candidate.weight_i32 < 0:
				_issue(&"CONTENT_REWARD_WEIGHT", definition.id, &"reward_candidates", "negative")
			elif candidate.weight_i32 > 0:
				usable += 1
				if candidate.kind == &"relic":
					relic_candidates += 1
					if candidate.conditions.is_empty():
						unconditional_relic += 1
				else:
					non_relic_candidates += 1
					if candidate.conditions.is_empty():
						unconditional_non_relic += 1
					if candidate.kind != &"unit":
						non_unit_candidates += 1
						if candidate.conditions.is_empty():
							unconditional_non_unit += 1
		if usable == 0 or definition.draw_count != 3: _issue(&"CONTENT_REWARD_WEIGHT", definition.id, &"reward_candidates", "draw_count")
		if relic_candidates > 0 and non_relic_candidates > 0:
			_issue(&"CONTENT_REWARD_STAGE", definition.id, &"reward_candidates", "mixed")
		elif relic_candidates > 0:
			has_relic = unconditional_relic > 0
			if not has_relic:
				_issue(&"CONTENT_REWARD_FALLBACK", definition.id, &"reward_candidates", "relic")
		elif non_relic_candidates > 0 and non_unit_candidates > 0:
			has_standard = unconditional_non_unit > 0
			has_event = has_event or unconditional_non_relic > 0
			if not has_standard:
				_issue(&"CONTENT_REWARD_FALLBACK", definition.id, &"reward_candidates", "standard")
		elif non_relic_candidates > 0:
			has_event = has_event or unconditional_non_relic > 0
			if unconditional_non_relic == 0:
				_issue(&"CONTENT_REWARD_FALLBACK", definition.id, &"reward_candidates", "event")
	if not has_standard or not has_relic or not has_event:
		_issue(
			&"CONTENT_REWARD_STAGE_COVERAGE", &"catalog.reward_tables",
			&"reward_candidates", "%s/%s/%s" % [has_standard, has_relic, has_event]
		)

func _validate_reward_condition(source_id: StringName, condition: ConditionDef) -> void:
	if condition == null or not condition.has_int_value \
		or condition.has_max_uses_per_battle:
		_issue(&"CONTENT_REWARD_CONDITION", source_id, &"reward_candidates.conditions", "shape")
		return
	var valid := false
	match condition.kind:
		&"roster_space_at_least":
			valid = condition.subject == &"roster" and condition.comparator == &"gte" \
				and condition.int_value >= 0 and condition.int_value <= 9 \
				and not condition.has_stable_id_value
		&"inventory_space_at_least":
			valid = condition.subject == &"inventory" and condition.comparator == &"gte" \
				and condition.int_value >= 0 and condition.int_value <= 16 \
				and not condition.has_stable_id_value
		&"expedition_hp_below":
			valid = condition.subject == &"expedition_hp" and condition.comparator == &"lt" \
				and condition.int_value >= 1 and condition.int_value <= 101 \
				and not condition.has_stable_id_value
		&"pool_copies_at_least":
			var referenced: ContentDefinition = _by_id.get(condition.stable_id_value)
			valid = condition.subject == &"pool" and condition.comparator == &"gte" \
				and condition.int_value >= 1 and condition.int_value <= 999 \
				and condition.has_stable_id_value and referenced is UnitDef
	if not valid:
		_issue(&"CONTENT_REWARD_CONDITION", source_id, &"reward_candidates.conditions", String(condition.kind))

func _validate_unlock_graph(definitions: Array[ContentDefinition]) -> void:
	var unlocks: Dictionary = {}
	var base_profiles: Array[UnlockDef] = []
	for definition in definitions:
		if definition is UnlockDef:
			unlocks[definition.id] = definition
			if definition.unlock_kind == &"base_profile": base_profiles.append(definition)
	for unlock_id in unlocks.keys():
		if _unlock_cycle_from(unlock_id as StringName, unlocks, {}, {}): _issue(&"CONTENT_UNLOCK_CYCLE", unlock_id as StringName, &"prerequisite_refs")
	if base_profiles.size() != 1:
		_issue(&"CONTENT_BASE_BUILD_MISSING", &"catalog.base_profile", &"count", str(base_profiles.size()))
		return
	var unit_ids: Array[StringName] = []
	for content_id in base_profiles[0].unlocked_content_refs:
		if _by_id.has(content_id) and _by_id[content_id] is UnitDef and (_by_id[content_id] as UnitDef).availability in [&"player", &"shared"]:
			unit_ids.append(content_id)
	if unit_ids.size() < 3: _issue(&"CONTENT_BASE_BUILD_MISSING", base_profiles[0].id, &"unlocked_content_refs", str(unit_ids.size()))
	var reachable_trait := false
	for definition in definitions:
		if not definition is TraitDef or definition.thresholds.is_empty(): continue
		var members := 0
		for unit_id in unit_ids:
			if (_by_id[unit_id] as UnitDef).trait_refs.has(definition.id): members += 1
		if members >= definition.thresholds[0].required_count: reachable_trait = true
	if not reachable_trait: _issue(&"CONTENT_BASE_BUILD_MISSING", base_profiles[0].id, &"trait_threshold")

func _unlock_cycle_from(current: StringName, unlocks: Dictionary, visiting: Dictionary, done: Dictionary) -> bool:
	if done.has(current): return false
	if visiting.has(current): return true
	visiting[current] = true
	var unlock: UnlockDef = unlocks[current]
	for prerequisite in unlock.prerequisite_refs:
		if unlocks.has(prerequisite) and _unlock_cycle_from(prerequisite, unlocks, visiting, done): return true
	visiting.erase(current)
	done[current] = true
	return false

## T10（S5-AC-004／design.md §7.2）：局外成長禁提基礎戰力——unlock 的 unlocked_content_refs／
## modifier_refs 不得宣告永久基礎生命/攻防提升、商店免費刷新（reroll_cost 歸零）、固定起始
## 人口。現行 schema 沒有任何「永久修改 UnitDef.base_stats」的 operation 型別（三個禁項在目前
## schema 下不可能透過「正常」的引用機制真正產生永久基礎戰力提升），這條規則是內容著作期的
## 防禦性結構檢查，攔阻明顯不合理/會被誤用的引用形狀。三個具體、可機械判別的觸發形狀：
## a. 免費刷新：引用 id 解析為 EconomyConfigDef 且其 reroll_cost <= 0。
## b. 固定起始人口：引用 id 解析為 EffectDef，其 run_operations 含至少一個
##    PopulationSourceOperationDef（現有 schema 中唯一代表「授予起始人口」語意的 operation）。
## c. 永久基礎生命/攻防提升：僅 modifier_refs（不含 unlocked_content_refs——後者是「解鎖新
##    棋子」的正常管道，如 base_profile 引用 UnitDef，不可誤傷）中任一 id 直接解析為 UnitDef——
##    modifier_refs 的語意是「效果/修飾器引用」，直接指向一個 UnitDef 沒有合理解讀。
func _validate_meta_forbidden_growth(definitions: Array[ContentDefinition]) -> void:
	for definition in definitions:
		if not definition is UnlockDef: continue
		var unlock := definition as UnlockDef
		for content_id in unlock.unlocked_content_refs:
			_check_forbidden_growth_ref(unlock.id, &"unlocked_content_refs", content_id, false)
		for content_id in unlock.modifier_refs:
			_check_forbidden_growth_ref(unlock.id, &"modifier_refs", content_id, true)

func _check_forbidden_growth_ref(
	source_id: StringName, field_path: StringName, content_id: StringName, allow_unit_check: bool
) -> void:
	var resolved: ContentDefinition = _by_id.get(content_id)
	if resolved == null: return
	if resolved is EconomyConfigDef and (resolved as EconomyConfigDef).reroll_cost <= 0:
		_issue(&"CONTENT_META_FORBIDDEN_GROWTH", source_id, field_path, String(content_id))
		return
	if resolved is EffectDef:
		for operation: RunOperationDef in (resolved as EffectDef).run_operations:
			if operation is PopulationSourceOperationDef:
				_issue(&"CONTENT_META_FORBIDDEN_GROWTH", source_id, field_path, String(content_id))
				return
	if allow_unit_check and resolved is UnitDef:
		_issue(&"CONTENT_META_FORBIDDEN_GROWTH", source_id, field_path, String(content_id))

func _validate_operations(definitions: Array[ContentDefinition]) -> void:
	for definition in definitions:
		if definition is EffectDef:
			var effect_definition := definition as EffectDef
			if not EFFECT_TRIGGERS.has(effect_definition.trigger):
				_issue(&"CONTENT_EFFECT_TRIGGER", effect_definition.id, &"trigger")
			if (effect_definition.trigger == &"periodic" \
				and (effect_definition.periodic_interval_ticks < 1 \
					or effect_definition.periodic_interval_ticks > 1800)) \
				or (effect_definition.trigger != &"periodic" \
					and effect_definition.periodic_interval_ticks != 0):
				_issue(&"CONTENT_EFFECT_TRIGGER", effect_definition.id, &"periodic_interval_ticks")
			if not STACKING_RULES.has(effect_definition.stacking) \
				or effect_definition.max_stacks < 1 \
				or effect_definition.max_stacks > 99 \
				or effect_definition.duration_ticks < 1 \
				or effect_definition.duration_ticks > 1800:
				_issue(&"CONTENT_OPERATION_INVALID", effect_definition.id, &"stacking")
			_validate_conditions(effect_definition)
			_validate_battle_operations(effect_definition.id, effect_definition.battle_operations, &"battle_operations")
			_validate_run_operations(effect_definition.id, effect_definition.run_operations, &"run_operations", &"battle_effect", true, false)
		elif definition is ConsumableDef:
			var consumable_definition := definition as ConsumableDef
			_validate_run_operations(consumable_definition.id, consumable_definition.run_operations, &"run_operations", &"consumable", false, false)
			if consumable_definition.use_timing == &"dismantle" and not consumable_definition.run_operations.is_empty():
				_issue(&"CONTENT_CONSUMABLE_DISMANTLE", consumable_definition.id, &"run_operations", "dismantle")
		elif definition is EquipmentDef:
			var equipment_definition := definition as EquipmentDef
			if equipment_definition.has_unique_group:
				if equipment_definition.unique_group.is_empty() or not _stable_id_validator.is_valid(equipment_definition.unique_group):
					_issue(&"CONTENT_EQUIPMENT_UNIQUE_GROUP", equipment_definition.id, &"unique_group", String(equipment_definition.unique_group))
			elif not equipment_definition.unique_group.is_empty():
				_issue(&"CONTENT_EQUIPMENT_UNIQUE_GROUP", equipment_definition.id, &"unique_group", String(equipment_definition.unique_group))
		elif definition is MapNodeDef:
			var map_definition := definition as MapNodeDef
			var allow_capacity := map_definition.node_type == &"event"
			_validate_run_operations(map_definition.id, map_definition.enter_operations, &"enter_operations", &"map_node", false, allow_capacity)
			_validate_run_operations(map_definition.id, map_definition.exit_operations, &"exit_operations", &"map_node", false, allow_capacity)
	_validate_effect_trigger_cycles(definitions)

func _validate_effect_trigger_cycles(
	definitions: Array[ContentDefinition]
) -> void:
	var reactive_damage_effects: Array[EffectDef] = []
	for definition: ContentDefinition in definitions:
		if not definition is EffectDef:
			continue
		var effect := definition as EffectDef
		if effect.trigger not in [&"hit", &"damaged", &"kill", &"death"]:
			continue
		var produces_damage := false
		for operation: BattleOperationDef in effect.battle_operations:
			if operation is DamageOperationDef:
				produces_damage = true
				break
		if produces_damage:
			reactive_damage_effects.append(effect)
	reactive_damage_effects.sort_custom(func(left: EffectDef, right: EffectDef) -> bool:
		return String(left.id) < String(right.id))
	for effect: EffectDef in reactive_damage_effects:
		if not _has_finite_use_bound(effect.conditions):
			_issue(
				&"CONTENT_EFFECT_TRIGGER_CYCLE",
				effect.id,
				&"conditions.max_uses_per_battle"
			)

func _has_finite_use_bound(conditions: Array[ConditionDef]) -> bool:
	for condition: ConditionDef in conditions:
		if condition != null and condition.kind == &"max_uses_per_battle" \
			and condition.has_max_uses_per_battle \
			and condition.max_uses_per_battle >= 1 \
			and condition.max_uses_per_battle <= 99:
			return true
	return false

func _validate_encounter_sources(definitions: Array[ContentDefinition]) -> void:
	for definition: ContentDefinition in definitions:
		if not definition is EncounterDef:
			continue
		var encounter := definition as EncounterDef
		var spawn_keys: Dictionary = {}
		for spawn_index: int in range(encounter.enemy_spawns.size()):
			var spawn: EnemySpawnDef = encounter.enemy_spawns[spawn_index]
			if spawn == null or not _strict_ascii_token(spawn.spawn_key):
				_issue(&"CONTENT_ENCOUNTER_SPAWN_KEY", encounter.id, &"enemy_spawns", str(spawn_index))
				continue
			if spawn_keys.has(spawn.spawn_key):
				_issue(&"CONTENT_ENCOUNTER_SPAWN_KEY", encounter.id, &"enemy_spawns", spawn.spawn_key)
			else:
				spawn_keys[spawn.spawn_key] = true
		var previous_phase := -1
		for phase_index: int in range(encounter.boss_phases.size()):
			var phase: BossPhaseDef = encounter.boss_phases[phase_index]
			if phase == null \
				or phase.phase_index <= previous_phase \
				or phase.hp_threshold_bps < 0 \
				or phase.hp_threshold_bps > 10000:
				_issue(&"CONTENT_BOSS_PHASE_INVALID", encounter.id, &"boss_phases", str(phase_index))
				continue
			previous_phase = phase.phase_index
			if not _strict_ascii_token(phase.source_spawn_key) \
				or not spawn_keys.has(phase.source_spawn_key):
				_issue(&"CONTENT_BOSS_PHASE_SOURCE", encounter.id, &"boss_phases.source_spawn_key", phase.source_spawn_key)

func _validate_combat_config(
	definitions: Array[ContentDefinition],
	entity_stress_minimum: int
) -> void:
	var configs: Array[CombatConfigDef] = []
	for definition: ContentDefinition in definitions:
		if definition is CombatConfigDef:
			configs.append(definition as CombatConfigDef)
	if configs.size() != 1:
		_issue(&"CONTENT_COMBAT_CONFIG_COUNT", &"config.combat_default", &"count", str(configs.size()))
		return
	var config: CombatConfigDef = configs[0]
	if config.id != &"config.combat_default":
		_issue(&"CONTENT_COMBAT_CONFIG_ID", config.id, &"id")
	var fixed_values := PackedInt32Array([
		config.simulation_version,
		config.tick_rate,
		config.board_width,
		config.board_height,
		config.soft_limit_ticks,
		config.hard_limit_ticks,
		config.progress_scale,
		config.resistance_base,
		config.basis_points,
		config.overtime_interval_ticks,
		config.main_actions_per_tick,
	])
	if fixed_values != PackedInt32Array([1, 20, 8, 8, 1200, 1800, 1000, 100, 10000, 20, 1]):
		_issue(&"CONTENT_COMBAT_CONFIG_FIXED", config.id, &"fixed_rules")
	if config.attack_mana_gain < 0 or config.attack_mana_gain > 100:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"attack_mana_gain")
	if config.damage_mana_factor < 1 or config.damage_mana_factor > 100:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"damage_mana_factor")
	if config.damage_mana_min < 0 or config.damage_mana_max > 100 \
		or config.damage_mana_min > config.damage_mana_max:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"damage_mana")
	if config.overtime_step_bps < 1 or config.overtime_step_bps > 1000 \
		or config.overtime_cap_bps < config.overtime_step_bps \
		or config.overtime_cap_bps > 10000:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"overtime")
	for value: int in [config.act1_base_damage, config.act2_base_damage, config.act3_base_damage]:
		if value < 1 or value > 100:
			_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"act_base_damage")
			break
	if config.survivor_damage < 0 or config.survivor_damage > 100 \
		or config.boss_damage < 0 or config.boss_damage > 100:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"expedition_damage")
	if config.effect_resolution_budget < 64 or config.effect_resolution_budget > 65535:
		_issue(&"CONTENT_COMBAT_CONFIG_BUDGET", config.id, &"effect_resolution_budget")
	if config.operation_budget < config.effect_resolution_budget \
		or config.operation_budget > 65535:
		_issue(&"CONTENT_COMBAT_CONFIG_BUDGET", config.id, &"operation_budget")
	if config.event_budget < 64 or config.event_budget > 65535:
		_issue(&"CONTENT_COMBAT_CONFIG_BUDGET", config.id, &"event_budget")
	if config.entity_budget < 64 or config.entity_budget > 1024 \
		or config.entity_budget < entity_stress_minimum:
		_issue(&"CONTENT_COMBAT_CONFIG_BUDGET", config.id, &"entity_budget", str(entity_stress_minimum))
	# spec §5.13:第一幕的敵方成長乘數固定為恆等 10000(固定規則,非 TUNE)。
	if config.act1_enemy_stat_bps != 10000:
		_issue(&"CONTENT_COMBAT_CONFIG_FIXED", config.id, &"act1_enemy_stat_bps")
	# act2／act3 為 TUNE;值域沿用 EncounterCompiler 對縮放乘數的既有上下界。
	for value: int in [config.act2_enemy_stat_bps, config.act3_enemy_stat_bps]:
		if value < 1 or value > 100000:
			_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"act_enemy_stat_bps")
			break

func _validate_conditions(effect: EffectDef) -> void:
	for condition in effect.conditions:
		if condition == null or not EFFECT_CONDITIONS.has(condition.kind):
			_issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "kind")
			continue
		if condition.kind in [&"health_below_bps", &"health_above_bps"] and (not condition.has_int_value or condition.int_value < 0 or condition.int_value > 10000):
			_issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "bps")
		if condition.kind in [&"distance_at_most", &"distance_at_least"] and (not condition.has_int_value or condition.int_value < 0 or condition.int_value > 7):
			_issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "distance")
		if condition.kind in [&"source_tag", &"target_tag", &"has_status", &"lacks_status", &"has_equipment"]:
			if not condition.has_stable_id_value or not _by_id.has(condition.stable_id_value): _issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "reference")
		if condition.has_max_uses_per_battle and (condition.max_uses_per_battle < 1 or condition.max_uses_per_battle > 99):
			_issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "uses")

func _validate_battle_operations(source_id: StringName, operations: Array[BattleOperationDef], field_path: StringName) -> void:
	for index in operations.size():
		var operation := operations[index]
		if operation == null or operation.operation_index != index or not _is_known_battle_operation(operation):
			_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "index/type")
			continue
		if operation is DamageOperationDef:
			if operation.base < 0 or operation.scaling not in [&"flat", &"attack"] \
				or operation.damage_type not in DAMAGE_TYPES \
				or operation.target not in OPERATION_TARGETS:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "damage")
		elif operation is HealOperationDef:
			if operation.base < 0 or operation.scaling not in [&"flat", &"attack"] \
				or operation.target not in OPERATION_TARGETS:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "heal")
		elif operation is ShieldOperationDef:
			if operation.amount < 0 or operation.duration_ticks < 1 \
				or operation.duration_ticks > 1800 \
				or operation.target not in OPERATION_TARGETS:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "shield")
		elif operation is ModifyStatOperationDef:
			var mode_is_valid: bool = operation.mode in [&"add", &"multiply_bps"]
			var multiply_amount_is_valid: bool = operation.mode != &"multiply_bps" \
				or (operation.amount >= 0 and operation.amount <= 100000)
			if operation.stat not in MODIFY_STAT_NAMES or not mode_is_valid \
				or not multiply_amount_is_valid or operation.duration_ticks < 1 \
				or operation.duration_ticks > 1800 \
				or operation.target not in OPERATION_TARGETS:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "modify_stat")
		elif operation is ApplyStatusOperationDef:
			if operation.stacks < 1 or operation.stacks > 99 \
				or operation.duration_ticks < 1 or operation.duration_ticks > 1800 \
				or operation.target not in OPERATION_TARGETS:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "status")
		elif operation is RemoveStatusOperationDef:
			if operation.target not in OPERATION_TARGETS:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "remove_status")
		elif operation is MoveOperationDef:
			if operation.cells < 0 or operation.cells > 7 or operation.direction_or_target.is_empty():
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "move")
		elif operation is SummonOperationDef:
			if operation.count < 1 or operation.count > 64 or operation.max_active_per_source < 1 or operation.max_active_per_source > 64:
				_issue(&"CONTENT_ENTITY_BOUND", source_id, field_path, "summon_bound")
			if operation.placement_rule.is_empty(): _issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "summon")
		elif operation is GrantManaOperationDef:
			if operation.amount < 0 or operation.target not in OPERATION_TARGETS:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "grant_mana")


func _validate_global_effect_source_lifecycle(
	definitions: Array[ContentDefinition]
) -> void:
	var checked: Dictionary = {}
	for definition: ContentDefinition in definitions:
		if definition is RelicDef:
			var relic := definition as RelicDef
			if relic.category == &"battle":
				_validate_global_effect_refs(
					relic.effect_refs, relic.id, &"relic", &"player", checked
				)
		elif definition is TraitDef:
			var trait_definition := definition as TraitDef
			for threshold: TraitThresholdDef in trait_definition.thresholds:
				if threshold != null:
					_validate_global_effect_refs(
						threshold.effect_refs, trait_definition.id,
						&"trait", &"player", checked
					)
		elif definition is CommanderDef:
			var commander := definition as CommanderDef
			_validate_global_effect_refs(
				commander.passive_effect_refs, commander.id,
				&"commander", &"player", checked
			)
		elif definition is EncounterDef:
			var encounter := definition as EncounterDef
			_validate_global_effect_refs(
				encounter.affix_refs, encounter.id,
				&"encounter_affix", &"enemy", checked
			)
		elif definition is UnlockDef:
			var unlock := definition as UnlockDef
			if unlock.unlock_kind == &"challenge":
				_validate_global_effect_refs(
					unlock.modifier_refs, unlock.id,
					&"challenge", &"player", checked
				)


func _validate_global_effect_refs(
	effect_refs: Array[StringName],
	referrer_id: StringName,
	source_category: StringName,
	source_side: StringName,
	checked: Dictionary
) -> void:
	for effect_id: StringName in effect_refs:
		var key := "%s|%s|%s" % [effect_id, source_category, source_side]
		if checked.has(key):
			continue
		checked[key] = true
		var definition: ContentDefinition = _by_id.get(effect_id)
		if not definition is EffectDef:
			continue
		var effect := definition as EffectDef
		if not _global_effect_lifecycle_valid(effect, source_category, source_side):
			_issue(
				&"CONTENT_EFFECT_SOURCE_LIFECYCLE", effect_id, &"source_lifecycle",
				"category=%s/side=%s/referrer=%s" % [
					source_category, source_side, referrer_id,
				]
			)


func _global_effect_lifecycle_valid(
	effect: EffectDef,
	source_category: StringName,
	source_side: StringName
) -> bool:
	if effect.trigger not in GLOBAL_SOURCE_TRIGGERS:
		return false
	if effect.trigger == &"battle_end" and not effect.battle_operations.is_empty():
		return false
	for condition: ConditionDef in effect.conditions:
		if condition == null or condition.kind != &"max_uses_per_battle":
			return false
	# combat-core/design.md:117／:236：RunOperation 禁令的作用域限於進入 BattleSetup 的
	# EffectSourceState——只有效果同時帶 battle_operations（因此會被 pin 進 battle
	# catalog／setup）時，challenge 來源才不得再攜帶 run_operations（雙軌）；純
	# run_operations 的 challenge 詞綴（如 ShopSurcharge／DrainExpeditionHp）不進
	# BattleSetup，由 run 層 RunModifierTable 軌 B always-active 消費，不受本條禁令限制。
	# encounter_affix source 的 RunOperation 禁令不受此範圍限縮，維持全面禁止——判準是
	# source_category（不依 source_side）：即使日後出現非 enemy-side 的 encounter_affix
	# 呼叫點，帶 run_operations 依然必須被拒（review A F3／review B #3）。
	if source_category == &"challenge":
		if not effect.run_operations.is_empty() and not effect.battle_operations.is_empty():
			return false
	elif source_category == &"encounter_affix" and not effect.run_operations.is_empty():
		return false
	for operation: BattleOperationDef in effect.battle_operations:
		if operation is MoveOperationDef or operation is SummonOperationDef:
			return false
		if operation is DamageOperationDef \
			and (operation as DamageOperationDef).scaling == &"attack":
			return false
		if operation is HealOperationDef \
			and (operation as HealOperationDef).scaling == &"attack":
			return false
		if operation is ModifyStatOperationDef \
			and (operation as ModifyStatOperationDef).stat not in GLOBAL_MODIFY_STAT_NAMES:
			return false
		if _battle_operation_target(operation) in [&"self", &"target"]:
			return false
	return true


func _battle_operation_target(operation: BattleOperationDef) -> StringName:
	if operation is DamageOperationDef: return (operation as DamageOperationDef).target
	if operation is HealOperationDef: return (operation as HealOperationDef).target
	if operation is ShieldOperationDef: return (operation as ShieldOperationDef).target
	if operation is ModifyStatOperationDef: return (operation as ModifyStatOperationDef).target
	if operation is ApplyStatusOperationDef: return (operation as ApplyStatusOperationDef).target
	if operation is RemoveStatusOperationDef: return (operation as RemoveStatusOperationDef).target
	if operation is GrantManaOperationDef: return (operation as GrantManaOperationDef).target
	return &""

func _is_known_battle_operation(operation: BattleOperationDef) -> bool:
	return operation is DamageOperationDef \
		or operation is HealOperationDef \
		or operation is ShieldOperationDef \
		or operation is ModifyStatOperationDef \
		or operation is ApplyStatusOperationDef \
		or operation is RemoveStatusOperationDef \
		or operation is MoveOperationDef \
		or operation is SummonOperationDef \
		or operation is GrantManaOperationDef

func _validate_run_operations(
	source_id: StringName,
	operations: Array[RunOperationDef],
	field_path: StringName,
	source_context: StringName,
	battle_source: bool,
	allow_capacity: bool
) -> void:
	for index in operations.size():
		var operation := operations[index]
		if operation == null or operation.operation_index != index or not _is_known_run_operation(operation):
			_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "%s:index/type" % String(source_context))
			continue
		if _is_scalar_run_operation(operation):
			if _scalar_run_amount(operation) < 0 or _scalar_run_claim_scope(operation) not in [&"once_per_node", &"on_first_clear", &"always"]:
				var scalar_code := &"CONTENT_RUN_INTENT_FORBIDDEN" if battle_source else &"CONTENT_OPERATION_INVALID"
				_issue(scalar_code, source_id, field_path, "%s:amount/scope" % String(source_context))
			continue
		if not allow_capacity:
			_issue(&"CONTENT_RUN_INTENT_FORBIDDEN", source_id, field_path, "%s:capacity" % String(source_context))
		if operation is ModifyUnitPoolOperationDef:
			if not _stable_id_validator.is_valid(operation.unit_ref) \
				or not _by_id.has(operation.unit_ref) \
				or not _by_id[operation.unit_ref] is UnitDef \
				or operation.count == 0:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "modify_pool")
		elif operation is GrantItemOperationDef:
			if not _stable_id_validator.is_valid(operation.content_ref) \
				or not _is_item_content_ref(operation.content_ref) \
				or operation.count < 1:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "grant_item")
			elif _by_id.get(operation.content_ref) is ItemComponentDef:
				_issue(&"CONTENT_ITEM_GRANT_COMPONENT", source_id, field_path, String(operation.content_ref))
		elif operation is GrantRelicOperationDef:
			if not _stable_id_validator.is_valid(operation.relic_ref) or not _by_id.has(operation.relic_ref) or not _by_id[operation.relic_ref] is RelicDef:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "grant_relic")
		elif operation is PopulationSourceOperationDef:
			if not _stable_id_validator.is_valid(operation.source_id) or operation.amount < 1:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "population_source")

func _is_known_run_operation(operation: RunOperationDef) -> bool:
	return _is_scalar_run_operation(operation) \
		or operation is ModifyUnitPoolOperationDef \
		or operation is GrantItemOperationDef \
		or operation is GrantRelicOperationDef \
		or operation is PopulationSourceOperationDef

## scalar run intent＝「一個整數幅度＋claim_scope」形狀的 run operation（amount≥0 不變量、
## claim_scope 白名單皆共用同一組判準）。design §6.3 軌 B 的 ShopSurcharge／DrainExpeditionHp
## 以型別表達負向語意，amount 仍是 ≥0 的幅度，故同組驗證、不放寬不變量。
func _is_scalar_run_operation(operation: RunOperationDef) -> bool:
	return operation is AddGoldOperationDef \
		or operation is AddXpOperationDef \
		or operation is HealExpeditionHpOperationDef \
		or operation is ShopDiscountOperationDef \
		or operation is ShopSurchargeOperationDef \
		or operation is DrainExpeditionHpOperationDef

func _scalar_run_amount(operation: RunOperationDef) -> int:
	if operation is AddGoldOperationDef: return (operation as AddGoldOperationDef).amount
	if operation is AddXpOperationDef: return (operation as AddXpOperationDef).amount
	if operation is HealExpeditionHpOperationDef: return (operation as HealExpeditionHpOperationDef).amount
	if operation is ShopDiscountOperationDef: return (operation as ShopDiscountOperationDef).amount
	if operation is ShopSurchargeOperationDef: return (operation as ShopSurchargeOperationDef).amount
	if operation is DrainExpeditionHpOperationDef: return (operation as DrainExpeditionHpOperationDef).amount
	return 0

func _scalar_run_claim_scope(operation: RunOperationDef) -> StringName:
	if operation is AddGoldOperationDef: return (operation as AddGoldOperationDef).claim_scope
	if operation is AddXpOperationDef: return (operation as AddXpOperationDef).claim_scope
	if operation is HealExpeditionHpOperationDef: return (operation as HealExpeditionHpOperationDef).claim_scope
	if operation is ShopDiscountOperationDef: return (operation as ShopDiscountOperationDef).claim_scope
	if operation is ShopSurchargeOperationDef: return (operation as ShopSurchargeOperationDef).claim_scope
	if operation is DrainExpeditionHpOperationDef: return (operation as DrainExpeditionHpOperationDef).claim_scope
	return &""

func _is_item_content_ref(content_id: StringName) -> bool:
	if not _by_id.has(content_id): return false
	var definition: ContentDefinition = _by_id[content_id]
	return definition is ItemComponentDef or definition is EquipmentDef or definition is ConsumableDef

func _calculate_population_and_entities(input: ContentValidationInput, report: ContentValidationReport) -> void:
	var relic_bonuses: Array[int] = []
	var commander_bonus := 0
	var source_bonuses: Dictionary = {}
	for definition in input.definitions:
		if definition is RelicDef and definition.population_bonus > 0: relic_bonuses.append(definition.population_bonus)
		elif definition is CommanderDef: commander_bonus = maxi(commander_bonus, definition.population_bonus)
		elif definition is MapNodeDef:
			var map_definition := definition as MapNodeDef
			if map_definition.node_type == &"event":
				_collect_population_bonuses(map_definition.enter_operations, source_bonuses)
				_collect_population_bonuses(map_definition.exit_operations, source_bonuses)
	relic_bonuses.sort()
	var relic_total := 0
	for index in mini(5, relic_bonuses.size()): relic_total += relic_bonuses[relic_bonuses.size() - 1 - index]
	var extra := relic_total + commander_bonus
	for value in source_bonuses.values(): extra += int(value)
	report.version_maximum_population = input.base_population_cap + extra
	report.per_side_stress_minimum = maxi(16, report.version_maximum_population + 4)
	if report.version_maximum_population < input.base_population_cap: _issue(&"CONTENT_POPULATION_BOUND", &"catalog.population", &"maximum")
	var summon_bounds: Dictionary = {}
	for definition in input.definitions:
		if definition is UnitDef: summon_bounds[definition.id] = _unit_summon_bound(definition)
	for definition in input.definitions:
		if not definition is UnitDef: continue
		var targets := _unit_summon_targets(definition)
		for target in targets:
			if int(summon_bounds.get(target, 0)) > 0: _issue(&"CONTENT_ENTITY_BOUND", definition.id, &"summon", "chain")
			if _has_summon_cycle(definition.id, definition.id, {}): _issue(&"CONTENT_ENTITY_BOUND", definition.id, &"summon", "cycle")
	var player_best := 0
	for definition in input.definitions:
		if definition is UnitDef and definition.availability in [&"player", &"shared"]: player_best = maxi(player_best, int(summon_bounds.get(definition.id, 0)))
	var player_entities := report.version_maximum_population * (1 + player_best)
	var enemy_entities := 0
	for definition in input.definitions:
		if not definition is EncounterDef: continue
		var encounter := definition as EncounterDef
		var current: int = encounter.enemy_spawns.size()
		for spawn in encounter.enemy_spawns: current += int(summon_bounds.get(spawn.unit_ref, 0))
		enemy_entities = maxi(enemy_entities, current)
	report.maximum_simultaneous_entities = player_entities + enemy_entities
	report.entity_stress_minimum = maxi(64, report.maximum_simultaneous_entities)

func _collect_population_bonuses(operations: Array[RunOperationDef], source_bonuses: Dictionary) -> void:
	for operation in operations:
		if operation is PopulationSourceOperationDef and operation.amount > 0:
			source_bonuses[operation.source_id] = maxi(int(source_bonuses.get(operation.source_id, 0)), operation.amount)

func _unit_summon_bound(unit: UnitDef) -> int:
	if not unit.has_ability_ref or not _by_id.has(unit.ability_ref) or not _by_id[unit.ability_ref] is AbilityDef: return 0
	var ability: AbilityDef = _by_id[unit.ability_ref]
	var total := 0
	for effect_id in ability.effect_refs:
		if not _by_id.has(effect_id) or not _by_id[effect_id] is EffectDef: continue
		for operation in (_by_id[effect_id] as EffectDef).battle_operations:
			if operation is SummonOperationDef: total += operation.max_active_per_source
	return total

func _unit_summon_targets(unit: UnitDef) -> Array[StringName]:
	var result: Array[StringName] = []
	if not unit.has_ability_ref or not _by_id.has(unit.ability_ref) or not _by_id[unit.ability_ref] is AbilityDef: return result
	for effect_id in (_by_id[unit.ability_ref] as AbilityDef).effect_refs:
		if not _by_id.has(effect_id) or not _by_id[effect_id] is EffectDef: continue
		for operation in (_by_id[effect_id] as EffectDef).battle_operations:
			if operation is SummonOperationDef: result.append(operation.unit_ref)
	return result

func _has_summon_cycle(origin: StringName, current: StringName, visited: Dictionary) -> bool:
	if visited.has(current): return current == origin
	visited[current] = true
	if _by_id.has(current) and _by_id[current] is UnitDef:
		for target in _unit_summon_targets(_by_id[current]):
			if target == origin or _has_summon_cycle(origin, target, visited.duplicate()): return true
	return false

func _issue(code: StringName, source_id: StringName, path: StringName, detail: String = "") -> void:
	_issues.append(ContentValidationIssue.new(code, source_id, path, detail))

func _issue_less(left: ContentValidationIssue, right: ContentValidationIssue) -> bool:
	if left.code != right.code: return String(left.code) < String(right.code)
	if left.source_id != right.source_id: return String(left.source_id) < String(right.source_id)
	return String(left.field_path) < String(right.field_path)

func _string_name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _strict_ascii_token(value: String) -> bool:
	if value.is_empty():
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 33 or byte > 126:
			return false
	return true
