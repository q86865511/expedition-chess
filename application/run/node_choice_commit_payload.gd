class_name NodeChoiceCommitPayload
extends RefCounted

## specs/content-production/design.md §5（:173-178）規定 COMMIT_NODE_CHOICE intent 與
## CommitNodeChoiceCommand exact 攜帶的十個欄位。payload 由 presentation 在「顯示
## overlay 的那一刻」從 committed snapshot 抄下，之後不再重讀 canonical state——
## RunCommandFactory 因此不得以 latest state 覆蓋任何欄位（design :177），
## 否則 stale payload 會在 commit 時被悄悄修正成合法值。

var expected_run_id: String
var node_id: StringName
var choice_set_id: StringName
var pending_digest: String
var content_version: String
var catalog_schema_version: int
var content_codec_version: int
var manifest_digest: String
var lifecycle_nonce: String
var choice_id: StringName


func _init(
	p_expected_run_id: String = "",
	p_node_id: StringName = &"",
	p_choice_set_id: StringName = &"",
	p_pending_digest: String = "",
	p_content_version: String = "",
	p_catalog_schema_version: int = 0,
	p_content_codec_version: int = 0,
	p_manifest_digest: String = "",
	p_lifecycle_nonce: String = "",
	p_choice_id: StringName = &""
) -> void:
	expected_run_id = p_expected_run_id
	node_id = p_node_id
	choice_set_id = p_choice_set_id
	pending_digest = p_pending_digest
	content_version = p_content_version
	catalog_schema_version = p_catalog_schema_version
	content_codec_version = p_content_codec_version
	manifest_digest = p_manifest_digest
	lifecycle_nonce = p_lifecycle_nonce
	choice_id = p_choice_id


## 唯一的 production 建構路徑：committed pending state ＋ 玩家選定的 choice_id。
static func from_pending(
	run_id: String,
	pending: NodeChoicePendingState,
	choice_id: StringName
) -> NodeChoiceCommitPayload:
	if pending == null:
		return null
	return NodeChoiceCommitPayload.new(
		run_id,
		pending.node_id,
		pending.choice_set_id,
		pending.pending_digest,
		pending.content_version,
		pending.catalog_schema_version,
		pending.content_codec_version,
		pending.manifest_digest,
		pending.lifecycle_nonce,
		choice_id
	)


func is_concrete() -> bool:
	return (
		not expected_run_id.is_empty()
		and not String(node_id).is_empty()
		and not String(choice_set_id).is_empty()
		and not pending_digest.is_empty()
		and not lifecycle_nonce.is_empty()
		and not String(choice_id).is_empty()
	)


func deep_clone() -> NodeChoiceCommitPayload:
	return NodeChoiceCommitPayload.new(
		expected_run_id,
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


## Confirmation payload digest（design :177-178「涵蓋相同 sequence 與 choice_id」）
## 與 LiveScreenIntentPort._intent_digest 共用同一串序列，故 draft 開出去之後
## payload 任一欄被改動都會在 confirm 時對不上 issued digest。
func digest_sequence() -> String:
	return "%s|%s|%s|%s|%s|%d|%d|%s|%s|%s" % [
		expected_run_id,
		String(node_id),
		String(choice_set_id),
		pending_digest,
		content_version,
		catalog_schema_version,
		content_codec_version,
		manifest_digest,
		lifecycle_nonce,
		String(choice_id),
	]
