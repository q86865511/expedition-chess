class_name ContentSnapshotState
extends RefCounted

static var _construction_seal: RefCounted = RefCounted.new()

var _content_version: String
var _enabled_content_ids: Array[StringName] = []
var _economy_config_id: StringName
var _combat_config_id: StringName
var _reward_table_ids: Array[StringName] = []
var _map_node_def_ids: Array[StringName] = []
var _challenge_unlock_def_ids: Array[StringName] = []
var _meta_reward_table_id: StringName
var _manifest_digest: String
var _validated: bool = false

static func from_pinned_receipt(
	receipt: PinnedCatalogBuildReceipt
) -> ContentSnapshotBuildResult:
	if receipt == null:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt"
		)
	if receipt.catalog_schema_version != 1:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt.catalog_schema_version"
		)
	if receipt.content_codec_version != 2:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt.content_codec_version"
		)
	if not _is_digest(receipt.selection_digest):
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt.selection_digest"
		)
	var candidate := _build_candidate(
		receipt.content_version,
		receipt.active_entry_ids,
		receipt.economy_config_id,
		receipt.combat_config_id,
		receipt.reward_table_ids,
		receipt.map_node_def_ids,
		receipt.challenge_unlock_def_ids,
		receipt.meta_reward_table_id,
		receipt.manifest_digest
	)
	if not candidate.ok:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			candidate.error.field_path
		)
	if candidate.snapshot.enabled_content_ids_copy() != receipt.active_entry_ids:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt.active_entry_ids"
		)
	if candidate.snapshot.combat_config_id_value() != receipt.combat_config_id:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt.combat_config_id"
		)
	if candidate.snapshot.reward_table_ids_copy() != receipt.reward_table_ids:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt.reward_table_ids"
		)
	if candidate.snapshot.map_node_def_ids_copy() != receipt.map_node_def_ids:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt.map_node_def_ids"
		)
	if candidate.snapshot.challenge_unlock_def_ids_copy() \
		!= receipt.challenge_unlock_def_ids:
		return _failure(
			ContentSnapshotBuildError.RECEIPT_INVALID,
			&"content_snapshot.receipt.challenge_unlock_def_ids"
		)
	return candidate

static func from_persisted(
	p_content_version: String,
	p_enabled_content_ids: Array[StringName],
	p_economy_config_id: StringName,
	p_combat_config_id: StringName,
	p_reward_table_ids: Array[StringName],
	p_map_node_def_ids: Array[StringName],
	p_challenge_unlock_def_ids: Array[StringName],
	p_meta_reward_table_id: StringName,
	p_manifest_digest: String,
	receipt: PinnedCatalogBuildReceipt
) -> ContentSnapshotBuildResult:
	var expected := from_pinned_receipt(receipt)
	if not expected.ok:
		return expected
	var candidate := _build_candidate(
		p_content_version,
		p_enabled_content_ids,
		p_economy_config_id,
		p_combat_config_id,
		p_reward_table_ids,
		p_map_node_def_ids,
		p_challenge_unlock_def_ids,
		p_meta_reward_table_id,
		p_manifest_digest
	)
	if not candidate.ok:
		return candidate
	if not candidate.snapshot.canonical_equals(expected.snapshot):
		return _failure(
			ContentSnapshotBuildError.RECEIPT_MISMATCH,
			&"content_snapshot.receipt"
		)
	return candidate

static func _build_candidate(
	p_content_version: String,
	p_enabled_content_ids: Array[StringName],
	p_economy_config_id: StringName,
	p_combat_config_id: StringName,
	p_reward_table_ids: Array[StringName],
	p_map_node_def_ids: Array[StringName],
	p_challenge_unlock_def_ids: Array[StringName],
	p_meta_reward_table_id: StringName,
	p_manifest_digest: String
) -> ContentSnapshotBuildResult:
	if not _is_ascii_nonempty(p_content_version):
		return _failure(
			ContentSnapshotBuildError.INPUT_INVALID,
			&"content_snapshot.content_version"
		)
	if not _is_digest(p_manifest_digest):
		return _failure(
			ContentSnapshotBuildError.INPUT_INVALID,
			&"content_snapshot.manifest_digest"
		)
	var stable_ids := StableIdValidator.new()
	if not stable_ids.is_valid(p_economy_config_id):
		return _failure(
			ContentSnapshotBuildError.INPUT_INVALID,
			&"content_snapshot.economy_config_id"
		)
	if p_combat_config_id != &"config.combat_default":
		return _failure(
			ContentSnapshotBuildError.INPUT_INVALID,
			&"content_snapshot.combat_config_id"
		)
	if not stable_ids.is_valid(p_meta_reward_table_id):
		return _failure(
			ContentSnapshotBuildError.INPUT_INVALID,
			&"content_snapshot.meta_reward_table_id"
		)
	var enabled_ids: Array[StringName] = []
	var reward_ids: Array[StringName] = []
	var map_ids: Array[StringName] = []
	var challenge_ids: Array[StringName] = []
	var invalid_path := _canonicalize_ids(
		p_enabled_content_ids,
		enabled_ids,
		&"content_snapshot.enabled_content_ids"
	)
	if not invalid_path.is_empty():
		return _failure(ContentSnapshotBuildError.INPUT_INVALID, invalid_path)
	invalid_path = _canonicalize_ids(
		p_reward_table_ids,
		reward_ids,
		&"content_snapshot.reward_table_ids"
	)
	if not invalid_path.is_empty():
		return _failure(ContentSnapshotBuildError.INPUT_INVALID, invalid_path)
	invalid_path = _canonicalize_ids(
		p_map_node_def_ids,
		map_ids,
		&"content_snapshot.map_node_def_ids"
	)
	if not invalid_path.is_empty():
		return _failure(ContentSnapshotBuildError.INPUT_INVALID, invalid_path)
	invalid_path = _canonicalize_ids(
		p_challenge_unlock_def_ids,
		challenge_ids,
		&"content_snapshot.challenge_unlock_def_ids"
	)
	if not invalid_path.is_empty():
		return _failure(ContentSnapshotBuildError.INPUT_INVALID, invalid_path)
	if not enabled_ids.has(p_economy_config_id):
		return _failure(
			ContentSnapshotBuildError.INPUT_INVALID,
			&"content_snapshot.economy_config_id"
		)
	if not enabled_ids.has(p_combat_config_id):
		return _failure(
			ContentSnapshotBuildError.INPUT_INVALID,
			&"content_snapshot.combat_config_id"
		)
	if not enabled_ids.has(p_meta_reward_table_id):
		return _failure(
			ContentSnapshotBuildError.INPUT_INVALID,
			&"content_snapshot.meta_reward_table_id"
		)
	for value: StringName in reward_ids:
		if not enabled_ids.has(value):
			return _failure(
				ContentSnapshotBuildError.INPUT_INVALID,
				&"content_snapshot.reward_table_ids"
			)
	for value: StringName in map_ids:
		if not enabled_ids.has(value):
			return _failure(
				ContentSnapshotBuildError.INPUT_INVALID,
				&"content_snapshot.map_node_def_ids"
			)
	for value: StringName in challenge_ids:
		if not enabled_ids.has(value):
			return _failure(
				ContentSnapshotBuildError.INPUT_INVALID,
				&"content_snapshot.challenge_unlock_def_ids"
			)
	return ContentSnapshotBuildResult.success(
		ContentSnapshotState.new(
			p_content_version,
			enabled_ids,
			p_economy_config_id,
			p_combat_config_id,
			reward_ids,
			map_ids,
			challenge_ids,
			p_meta_reward_table_id,
			p_manifest_digest,
			_construction_seal
		)
	)

static func _canonicalize_ids(
	values: Array[StringName],
	output: Array[StringName],
	field_path: StringName
) -> StringName:
	var stable_ids := StableIdValidator.new()
	output.assign(values)
	output.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	var previous := ""
	for value: StringName in output:
		var current := String(value)
		if not stable_ids.is_valid(value) or current == previous:
			return field_path
		previous = current
	return &""

static func _is_ascii_nonempty(value: String) -> bool:
	if value.is_empty():
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 0x21 or byte > 0x7e:
			return false
	return true

static func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) \
			and not (code >= 97 and code <= 102):
			return false
	return true

static func _failure(
	code: StringName,
	field_path: StringName
) -> ContentSnapshotBuildResult:
	return ContentSnapshotBuildResult.failure(
		ContentSnapshotBuildError.new(code, field_path)
	)

func _init(
	p_content_version: String,
	p_enabled_content_ids: Array[StringName],
	p_economy_config_id: StringName,
	p_combat_config_id: StringName,
	p_reward_table_ids: Array[StringName],
	p_map_node_def_ids: Array[StringName],
	p_challenge_unlock_def_ids: Array[StringName],
	p_meta_reward_table_id: StringName,
	p_manifest_digest: String,
	p_construction_seal: RefCounted = null
) -> void:
	_content_version = p_content_version
	_enabled_content_ids.assign(p_enabled_content_ids)
	_economy_config_id = p_economy_config_id
	_combat_config_id = p_combat_config_id
	_reward_table_ids.assign(p_reward_table_ids)
	_map_node_def_ids.assign(p_map_node_def_ids)
	_challenge_unlock_def_ids.assign(p_challenge_unlock_def_ids)
	_meta_reward_table_id = p_meta_reward_table_id
	_manifest_digest = p_manifest_digest
	_validated = p_construction_seal == _construction_seal

func is_validated() -> bool:
	return _validated

func content_version_value() -> String:
	return _content_version

func enabled_content_ids_copy() -> Array[StringName]:
	return _enabled_content_ids.duplicate()

func economy_config_id_value() -> StringName:
	return _economy_config_id

func combat_config_id_value() -> StringName:
	return _combat_config_id

func reward_table_ids_copy() -> Array[StringName]:
	return _reward_table_ids.duplicate()

func map_node_def_ids_copy() -> Array[StringName]:
	return _map_node_def_ids.duplicate()

func challenge_unlock_def_ids_copy() -> Array[StringName]:
	return _challenge_unlock_def_ids.duplicate()

func meta_reward_table_id_value() -> StringName:
	return _meta_reward_table_id

func manifest_digest_value() -> String:
	return _manifest_digest

func deep_clone() -> ContentSnapshotState:
	return ContentSnapshotState.new(
		_content_version,
		_enabled_content_ids,
		_economy_config_id,
		_combat_config_id,
		_reward_table_ids,
		_map_node_def_ids,
		_challenge_unlock_def_ids,
		_meta_reward_table_id,
		_manifest_digest,
		_construction_seal if _validated else null
	)

func canonical_equals(other: ContentSnapshotState) -> bool:
	if other == null or not _validated or not other._validated:
		return false
	return _content_version == other._content_version \
		and _enabled_content_ids == other._enabled_content_ids \
		and _economy_config_id == other._economy_config_id \
		and _combat_config_id == other._combat_config_id \
		and _reward_table_ids == other._reward_table_ids \
		and _map_node_def_ids == other._map_node_def_ids \
		and _challenge_unlock_def_ids == other._challenge_unlock_def_ids \
		and _meta_reward_table_id == other._meta_reward_table_id \
		and _manifest_digest == other._manifest_digest
