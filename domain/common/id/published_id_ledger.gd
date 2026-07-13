class_name PublishedIdLedger
extends RefCounted

const DUPLICATE: StringName = &"ID_DUPLICATE"
const ALIAS_CYCLE: StringName = &"ID_ALIAS_CYCLE"
const ALIAS_TARGET_MISSING: StringName = &"ID_ALIAS_TARGET_MISSING"
const TOMBSTONE_CONFLICT: StringName = &"ID_TOMBSTONE_CONFLICT"

var _records: Array[PublishedIdRecord] = []
var _validator := StableIdValidator.new()

func records_copy() -> Array[PublishedIdRecord]:
	var copied: Array[PublishedIdRecord] = []
	for record: PublishedIdRecord in _records:
		copied.append(record.deep_clone())
	return copied

func load_records(records: Array[PublishedIdRecord]) -> IdLedgerResult:
	var candidate: Array[PublishedIdRecord] = []
	for record: PublishedIdRecord in records:
		if record == null or not _validator.is_valid(record.stable_id):
			return IdLedgerResult.failure(&"ID_INVALID_FORMAT", &"", &"records")
		for existing: PublishedIdRecord in candidate:
			if existing.stable_id == record.stable_id:
				return IdLedgerResult.failure(DUPLICATE, record.stable_id)
		candidate.append(record.deep_clone())
	var previous := _records
	_records = candidate
	var validation := validate_all()
	if not validation.ok:
		_records = previous
		return validation
	_sort_records()
	return IdLedgerResult.success()

func add_active(stable_id: StringName) -> IdLedgerResult:
	var valid := _validator.validate(stable_id)
	if not valid.ok:
		return IdLedgerResult.failure(valid.error.code, stable_id)
	if _find_index(stable_id) >= 0:
		return IdLedgerResult.failure(DUPLICATE, stable_id)
	_records.append(PublishedIdRecord.active(stable_id))
	_sort_records()
	return IdLedgerResult.success(stable_id, PublishedIdRecord.ACTIVE)

func add_alias(source_id: StringName, target_id: StringName) -> IdLedgerResult:
	var source_valid := _validator.validate(source_id, &"alias.source_id")
	if not source_valid.ok:
		return IdLedgerResult.failure(source_valid.error.code, source_id, &"alias.source_id")
	var target_valid := _validator.validate(target_id, &"alias.target_id")
	if not target_valid.ok:
		return IdLedgerResult.failure(target_valid.error.code, target_id, &"alias.target_id")
	if _find_index(source_id) >= 0:
		return IdLedgerResult.failure(DUPLICATE, source_id)
	if _find_index(target_id) < 0:
		return IdLedgerResult.failure(ALIAS_TARGET_MISSING, target_id, &"alias.target_id")
	var candidate := PublishedIdRecord.alias(source_id, target_id)
	_records.append(candidate)
	var resolution := resolve(source_id)
	if not resolution.ok:
		_records.erase(candidate)
		return resolution
	_sort_records()
	return IdLedgerResult.success(resolution.resolved_id, resolution.resolved_status)

func add_tombstone(stable_id: StringName, policy: StringName = &"safe_absent") -> IdLedgerResult:
	var valid := _validator.validate(stable_id)
	if not valid.ok:
		return IdLedgerResult.failure(valid.error.code, stable_id)
	if _find_index(stable_id) >= 0:
		return IdLedgerResult.failure(TOMBSTONE_CONFLICT, stable_id)
	if policy != &"safe_absent" and policy != &"required_incompatible":
		return IdLedgerResult.failure(TOMBSTONE_CONFLICT, stable_id, &"tombstone_policy")
	_records.append(PublishedIdRecord.tombstone(stable_id, policy))
	_sort_records()
	return IdLedgerResult.success(stable_id, PublishedIdRecord.TOMBSTONE)

func resolve(stable_id: StringName) -> IdLedgerResult:
	var current := stable_id
	var visited: Array[StringName] = []
	while true:
		if visited.has(current):
			return IdLedgerResult.failure(ALIAS_CYCLE, current, &"alias")
		visited.append(current)
		var index := _find_index(current)
		if index < 0:
			return IdLedgerResult.failure(ALIAS_TARGET_MISSING, current, &"alias.target_id")
		var record := _records[index]
		if record.status == PublishedIdRecord.ACTIVE or record.status == PublishedIdRecord.TOMBSTONE:
			return IdLedgerResult.success(record.stable_id, record.status)
		if record.status != PublishedIdRecord.ALIAS:
			return IdLedgerResult.failure(TOMBSTONE_CONFLICT, record.stable_id)
		current = record.alias_target
	return IdLedgerResult.failure(ALIAS_CYCLE, current, &"alias")

func validate_all() -> IdLedgerResult:
	for record: PublishedIdRecord in _records:
		if record.status == PublishedIdRecord.ALIAS:
			var resolution := resolve(record.stable_id)
			if not resolution.ok:
				return resolution
	return IdLedgerResult.success()

func _find_index(stable_id: StringName) -> int:
	for index: int in range(_records.size()):
		if _records[index].stable_id == stable_id:
			return index
	return -1

func _sort_records() -> void:
	_records.sort_custom(func(left: PublishedIdRecord, right: PublishedIdRecord) -> bool:
		return String(left.stable_id) < String(right.stable_id)
	)
