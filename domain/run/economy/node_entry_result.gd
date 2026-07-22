class_name NodeEntryResult
extends RefCounted

var ok: bool
var draft: RunState
var error: NodeEntryError

static func success(value: RunState) -> NodeEntryResult:
	return NodeEntryResult.new(true, value, null)

static func failure(code: StringName, path: StringName) -> NodeEntryResult:
	return NodeEntryResult.new(false, null, NodeEntryError.new(code, path))

func _init(p_ok: bool, p_draft: RunState, p_error: NodeEntryError) -> void:
	ResultInvariant.require(p_ok, p_error, p_draft != null, p_draft == null)
	ok = p_ok
	draft = p_draft.deep_clone() if p_draft != null else null
	error = p_error.deep_clone() if p_error != null else null
