class_name CommanderContentReader
extends RefCounted

## S5 wave5 修正 B4（REQ-DATA-008）：composition root 取得指揮官資料的**唯一**管道。
## 只走 ContentRegistryService.resolve(ContentRef(manifest_digest, id))——registry-owned
## canonical value snapshot 的 deep-clone view（content_definition_view.gd:16）——再把純值
## 重組成一個**新建的** CommanderDef 值載體，交給 StartExpeditionCommand／RunBootstrapService
## （兩者的既有簽章要求 CommanderDef，見 run_bootstrap_service.gd:18-24）。
## 因此 app 層永遠不持有 authoring .tres 那一份共享實例，也不可能經由它改到 registry 內的
## 內容而 manifest digest 未察覺（RSK-012）。
##
## payload 佈局：3 common ＋ 4 specifics ＝ 7 children（content_definition_compiler.gd:117），
## children[3]=starting_pack、[4]=passive_effect_refs、[5]=route_preferences、[6]=population_bonus。
## starting_pack 的每個成員是 record(0x2004)＝[stable_id(content_id), u32(count_u32)]
## （content_definition_compiler.gd:287-290）。解碼手法與 RunModifierTableBuilder
## ._append_commander_rules（同一份 payload、同一組 children 索引）保持一致，避免兩處分歧。
##
## 未還原的欄位：display_name_key（純顯示用，domain 不讀）與 route_preferences（目前無
## 消費端）。需要時照同樣手法從 payload 補，不要改回讀 authoring 定義。

const _CHILD_COUNT: int = 7
const _CHILD_STARTING_PACK: int = 3
const _CHILD_PASSIVE_EFFECT_REFS: int = 4
const _CHILD_POPULATION_BONUS: int = 6
const _AMOUNT_CHILD_COUNT: int = 2


## 指揮官不存在／世代查無／payload 形狀不符時回 null（try_ 前綴即此契約）。
func try_read(
	registry: ContentRegistryService,
	manifest_digest: String,
	commander_id: StringName
) -> CommanderDef:
	var payload := _try_payload(registry, manifest_digest, commander_id)
	if payload == null:
		return null
	var starting_pack: Array[ContentAmountDef] = []
	for record: ContentValue in payload.children[_CHILD_STARTING_PACK].children:
		if record == null or record.children.size() != _AMOUNT_CHILD_COUNT:
			return null
		var entry := ContentAmountDef.new()
		entry.content_id = StringName(record.children[0].string_value)
		entry.count_u32 = record.children[1].int_value
		starting_pack.append(entry)
	var definition := CommanderDef.new()
	definition.id = commander_id
	definition.starting_pack = starting_pack
	definition.passive_effect_refs = _stable_ids(payload.children[_CHILD_PASSIVE_EFFECT_REFS])
	definition.population_bonus = payload.children[_CHILD_POPULATION_BONUS].int_value
	return definition


## §6.2／S5-AC-003 的指揮官被動 effect id 清單（BattleSetupSourceCompiler.compile() 的第三
## 參數）。查無時回空陣列——「沒有被動」與「查不到指揮官」對戰鬥編譯是同一件事：不貢獻效果。
func passive_effect_ids(
	registry: ContentRegistryService,
	manifest_digest: String,
	commander_id: StringName
) -> Array[StringName]:
	var payload := _try_payload(registry, manifest_digest, commander_id)
	if payload == null:
		return [] as Array[StringName]
	return _stable_ids(payload.children[_CHILD_PASSIVE_EFFECT_REFS])


func _try_payload(
	registry: ContentRegistryService,
	manifest_digest: String,
	commander_id: StringName
) -> ContentValue:
	if registry == null or manifest_digest.length() != 64 or commander_id.is_empty():
		return null
	var resolved := registry.resolve(ContentRef.new(manifest_digest, commander_id))
	if not resolved.ok:
		return null
	var view: ContentDefinitionView = resolved.value
	if view.category != &"commander" or view.payload == null \
		or view.payload.record_type != ContentCategory.COMMANDER \
		or view.payload.children.size() != _CHILD_COUNT:
		return null
	return view.payload


func _stable_ids(value: ContentValue) -> Array[StringName]:
	var result: Array[StringName] = []
	if value == null:
		return result
	for child: ContentValue in value.children:
		result.append(StringName(child.string_value))
	return result
