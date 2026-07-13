class_name PublishedIdRecord
extends RefCounted

const ACTIVE: StringName = &"active"
const ALIAS: StringName = &"alias"
const TOMBSTONE: StringName = &"tombstone"

var stable_id: StringName = &""
var status: StringName = &""
var alias_target: StringName = &""
var tombstone_policy: StringName = &""

static func active(id: StringName) -> PublishedIdRecord:
	var value := PublishedIdRecord.new()
	value.stable_id = id
	value.status = ACTIVE
	return value

static func alias(id: StringName, target: StringName) -> PublishedIdRecord:
	var value := PublishedIdRecord.new()
	value.stable_id = id
	value.status = ALIAS
	value.alias_target = target
	return value

static func tombstone(id: StringName, policy: StringName) -> PublishedIdRecord:
	var value := PublishedIdRecord.new()
	value.stable_id = id
	value.status = TOMBSTONE
	value.tombstone_policy = policy
	return value

func deep_clone() -> PublishedIdRecord:
	var value := PublishedIdRecord.new()
	value.stable_id = stable_id
	value.status = status
	value.alias_target = alias_target
	value.tombstone_policy = tombstone_policy
	return value
