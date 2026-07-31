class_name NodeChoiceOverlaySnapshot
extends RefCounted

## design.md §5:173-178：overlay 是 commit payload 的唯一來源，故 pending 的十個
## identity 欄位（除了玩家當下選的 choice_id）都要投影出來，UI 才能在「看到選項的
## 那一刻」把 payload 抄完整；少一欄就等於讓 factory／service 回頭讀 latest state。
var choice_set_id: StringName
var display_name_key: StringName
var pending_digest: String
var node_id: StringName
var content_version: String
var catalog_schema_version: int
var content_codec_version: int
var manifest_digest: String
var lifecycle_nonce: String
var options: Array[NodeChoiceOptionSnapshot] = []


static func from_rule(
	rule: NodeChoiceSetRule,
	pending: NodeChoicePendingState
) -> NodeChoiceOverlaySnapshot:
	if (
		rule == null
		or pending == null
		or rule.choice_set_id != pending.choice_set_id
	):
		return null
	var result := NodeChoiceOverlaySnapshot.new()
	result.choice_set_id = rule.choice_set_id
	result.display_name_key = rule.display_name_key
	result.pending_digest = pending.pending_digest
	result.node_id = pending.node_id
	result.content_version = pending.content_version
	result.catalog_schema_version = pending.catalog_schema_version
	result.content_codec_version = pending.content_codec_version
	result.manifest_digest = pending.manifest_digest
	result.lifecycle_nonce = pending.lifecycle_nonce
	for choice: NodeChoiceRule in rule.choices:
		if not pending.choice_ids.has(choice.choice_id):
			return null
		result.options.append(
			NodeChoiceOptionSnapshot.new(
				choice.choice_id,
				choice.title_key,
				choice.description_key,
				choice.preview_key,
				choice.confirmation_required
			)
		)
	return result if result.options.size() >= 2 else null


func try_option(choice_id: StringName) -> NodeChoiceOptionSnapshot:
	for option: NodeChoiceOptionSnapshot in options:
		if option.choice_id == choice_id:
			return option.deep_clone()
	return null


## design.md §5:174-178 的 exact payload：只有 choice_id 來自玩家當下的選擇，
## 其餘欄位一律是 overlay 建立當下抄下的 pending identity。
func commit_payload(
	run_id: StringName,
	choice_id: StringName
) -> NodeChoiceCommitPayload:
	return NodeChoiceCommitPayload.new(
		String(run_id),
		node_id,
		choice_set_id,
		pending_digest,
		content_version,
		catalog_schema_version,
		content_codec_version,
		manifest_digest,
		lifecycle_nonce,
		choice_id
	)


func deep_clone() -> NodeChoiceOverlaySnapshot:
	var clone := NodeChoiceOverlaySnapshot.new()
	clone.choice_set_id = choice_set_id
	clone.display_name_key = display_name_key
	clone.pending_digest = pending_digest
	clone.node_id = node_id
	clone.content_version = content_version
	clone.catalog_schema_version = catalog_schema_version
	clone.content_codec_version = content_codec_version
	clone.manifest_digest = manifest_digest
	clone.lifecycle_nonce = lifecycle_nonce
	for option: NodeChoiceOptionSnapshot in options:
		clone.options.append(option.deep_clone())
	return clone
