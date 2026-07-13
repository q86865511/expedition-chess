class_name ResolutionRetryResult
extends RefCounted

var ok: bool
var field_path: StringName
var before_json: String
var after_json: String
var before_key_count: int
var after_key_count: int

static func success(
	before: String,
	after: String,
	p_before_key_count: int = -1,
	p_after_key_count: int = -1
) -> ResolutionRetryResult:
	return ResolutionRetryResult.new(
		true, &"", before, after, p_before_key_count, p_after_key_count
	)

static func failure(
	path: StringName,
	before: String = "",
	after: String = "",
	p_before_key_count: int = -1,
	p_after_key_count: int = -1
) -> ResolutionRetryResult:
	return ResolutionRetryResult.new(
		false, path, before, after, p_before_key_count, p_after_key_count
	)

func _init(
	p_ok: bool,
	p_field_path: StringName,
	p_before: String,
	p_after: String,
	p_before_key_count: int,
	p_after_key_count: int
) -> void:
	ok = p_ok
	field_path = p_field_path
	before_json = p_before
	after_json = p_after
	before_key_count = p_before_key_count
	after_key_count = p_after_key_count
