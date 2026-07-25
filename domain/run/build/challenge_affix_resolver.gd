class_name ChallengeAffixResolver
extends RefCounted

## design §6.3（S5-AC-010）：解 challenge unlock 鏈 1..N 的 modifier_refs，把每個詞綴效果依其
## 內容分到兩軌——軌 A（battle_operations 非空→敵方 battle affix，交給 EncounterCompiler）與
## 軌 B（run_operations 非空→run 層負向機制，由 RunModifierTableBuilder 建 always-active 規則）。
## 兩軌非互斥：同一效果同時帶兩種 operation 時各產一筆 entry。
##
## 走訪方式與 RunModifierTableBuilder._append_challenge_rules 完全相同（unlock id 慣例
## unlock.slice_challenge_%d、level 1..challenge_level 逐一 resolve）——ContentRegistryService
## 無列舉能力，只能以已知命名逐一查。challenge_level 0＝無詞綴（不解析任何 unlock，回空清單）。
##
## 本 resolver 只做「結構性分軌」，不解碼 operation 種類：kind 的解碼與「是否有 always-active
## 消費端」的把關是 RunRelicTableBuilder／RunModifierTableBuilder 的既有職責，不在此重複。

func resolve(
	registry: ContentRegistryService,
	manifest_digest: String,
	challenge_level: int
) -> ChallengeAffixResolveResult:
	if registry == null or manifest_digest.length() != 64 or challenge_level < 0:
		return ChallengeAffixResolveResult.failure(
			RunRelicTableError.INPUT_INVALID, &"manifest_digest"
		)
	var entries: Array[ChallengeAffixEntryState] = []
	# W4-F7 修正（2026-07-25）：seen 移到 level 迴圈外——同一 effect_id 若被兩個不同階級的
	# modifier_refs 各自列出，只在其首次出現（最低階級）產生一筆 entry，對齊 design §6.3
	# 「sorted, dedup」的字面契約（原實作 seen 侷限在單一 level 迴圈內宣告，跨階級不去重；
	# 同階級內重複本就不可能發生，modifier_refs 是 canonical set，見
	# test_challenge_affix_resolver.gd 的仲裁記錄，故此去重實質只在跨階級時生效）。
	var seen: Array[StringName] = []
	for level: int in range(1, challenge_level + 1):
		var unlock_id := StringName("unlock.slice_challenge_%d" % level)
		var resolved := registry.resolve(ContentRef.new(manifest_digest, unlock_id))
		if not resolved.ok:
			return ChallengeAffixResolveResult.failure(
				RunRelicTableError.RESOLVE_FAILED, resolved.error.field_path, unlock_id
			)
		var view: ContentDefinitionView = resolved.value
		if view.category != &"unlock":
			return ChallengeAffixResolveResult.failure(
				RunRelicTableError.CATEGORY_MISMATCH, &"category", unlock_id
			)
		# UnlockDef payload：3 common ＋ 6 specifics ＝ 9 children；children[8]＝modifier_refs
		# （stable_id 集合，見 content_definition_compiler.gd:121）。
		if view.payload == null or view.payload.record_type != ContentCategory.UNLOCK \
			or view.payload.children.size() != 9:
			return ChallengeAffixResolveResult.failure(
				RunRelicTableError.PAYLOAD_INVALID, &"unlock.payload", unlock_id
			)
		for effect_id: StringName in _stable_id_names(view.payload.children[8]):
			if seen.has(effect_id):
				continue
			seen.append(effect_id)
			var failure := _append_effect_entries(
				registry, manifest_digest, effect_id, level, entries
			)
			if failure != null:
				return failure
	entries.sort_custom(_entry_before)
	return ChallengeAffixResolveResult.success(entries)

## 依效果內容分軌並 append entry。回 null＝成功、非 null＝具名失敗（沿用 RunRelicTableError 字彙）。
func _append_effect_entries(
	registry: ContentRegistryService, manifest_digest: String, effect_id: StringName,
	level: int, entries: Array[ChallengeAffixEntryState]
) -> ChallengeAffixResolveResult:
	var resolved := registry.resolve(ContentRef.new(manifest_digest, effect_id))
	if not resolved.ok:
		return ChallengeAffixResolveResult.failure(
			RunRelicTableError.RESOLVE_FAILED, resolved.error.field_path, effect_id
		)
	var view: ContentDefinitionView = resolved.value
	if view.category != &"effect":
		return ChallengeAffixResolveResult.failure(
			RunRelicTableError.CATEGORY_MISMATCH, &"category", effect_id
		)
	# EffectDef payload：12 children；children[7]＝battle_operations、children[8]＝run_operations
	# （形狀見 battle_rule_catalog_builder._decode_effect 與 run_relic_table_builder）。
	if view.payload == null or view.payload.record_type != ContentCategory.EFFECT \
		or view.payload.children.size() != 12:
		return ChallengeAffixResolveResult.failure(
			RunRelicTableError.PAYLOAD_INVALID, &"effect.payload", effect_id
		)
	if not view.payload.children[7].children.is_empty():
		entries.append(ChallengeAffixEntryState.new(
			effect_id, level, ChallengeAffixEntryState.BATTLE_AFFIX_TRACK
		))
	if not view.payload.children[8].children.is_empty():
		entries.append(ChallengeAffixEntryState.new(
			effect_id, level, ChallengeAffixEntryState.RUN_MODIFIER_TRACK
		))
	return null

## 決定性排序：challenge_level 升序 → effect_id 字典序 → track 字典序。
func _entry_before(
	left: ChallengeAffixEntryState, right: ChallengeAffixEntryState
) -> bool:
	if left.challenge_level != right.challenge_level:
		return left.challenge_level < right.challenge_level
	if left.effect_id != right.effect_id:
		return String(left.effect_id) < String(right.effect_id)
	return String(left.track) < String(right.track)

func _stable_id_names(value: ContentValue) -> Array[StringName]:
	var result: Array[StringName] = []
	if value == null:
		return result
	for child: ContentValue in value.children:
		result.append(StringName(child.string_value))
	return result
