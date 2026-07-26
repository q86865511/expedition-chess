class_name MetaRewardTableReader
extends RefCounted

## S5-AC-006／REQ-DATA-008：由 pinned registry canonical payload 重建
## MetaRewardTableDef 純值 clone。consumer 取得的 Resource 與 authoring `.tres`、registry
## view 都不共享可變子物件。
##
## payload 佈局（content_definition_compiler.gd）：
## 3 common + 4 specifics = 7 children；
## [3] node_scores set(record 0x200b [enum, i32])
## [4] completion_reward i32
## [5] failure_reward i32
## [6] challenge_multiplier_bps set(record 0x200c [u32, u32])

const _CHILD_COUNT: int = 7
const _CHILD_NODE_SCORES: int = 3
const _CHILD_COMPLETION_REWARD: int = 4
const _CHILD_FAILURE_REWARD: int = 5
const _CHILD_CHALLENGE_MULTIPLIERS: int = 6
const _PAIR_CHILD_COUNT: int = 2
const _NODE_SCORE_RECORD_TYPE: int = 0x200b
const _CHALLENGE_MULTIPLIER_RECORD_TYPE: int = 0x200c


func try_read(
	registry: ContentRegistryService,
	manifest_digest: String,
	table_id: StringName
) -> MetaRewardTableDef:
	if registry == null or manifest_digest.length() != 64 or table_id.is_empty():
		return null
	var resolved := registry.resolve(ContentRef.new(manifest_digest, table_id))
	if not resolved.ok:
		return null
	var view: ContentDefinitionView = resolved.value
	if view.category != &"meta_reward_table" or view.payload == null \
		or view.payload.record_type != ContentCategory.META_REWARD_TABLE \
		or view.payload.children.size() != _CHILD_COUNT:
		return null

	var node_scores: Array[EnumIntPairDef] = []
	for record: ContentValue in view.payload.children[_CHILD_NODE_SCORES].children:
		if record == null or record.record_type != _NODE_SCORE_RECORD_TYPE \
			or record.children.size() != _PAIR_CHILD_COUNT:
			return null
		var score := EnumIntPairDef.new()
		score.enum_key = StringName(record.children[0].string_value)
		score.value_i32 = record.children[1].int_value
		node_scores.append(score)

	var multipliers: Array[ChallengeMultiplierDef] = []
	for record: ContentValue in view.payload.children[_CHILD_CHALLENGE_MULTIPLIERS].children:
		if record == null or record.record_type != _CHALLENGE_MULTIPLIER_RECORD_TYPE \
			or record.children.size() != _PAIR_CHILD_COUNT:
			return null
		var multiplier := ChallengeMultiplierDef.new()
		multiplier.challenge_level = record.children[0].int_value
		multiplier.basis_points = record.children[1].int_value
		multipliers.append(multiplier)

	var definition := MetaRewardTableDef.new()
	definition.id = table_id
	definition.node_scores = node_scores
	definition.completion_reward = (
		view.payload.children[_CHILD_COMPLETION_REWARD].int_value
	)
	definition.failure_reward = view.payload.children[_CHILD_FAILURE_REWARD].int_value
	definition.challenge_multiplier_bps = multipliers
	return definition
