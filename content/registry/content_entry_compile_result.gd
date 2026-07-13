class_name ContentEntryCompileResult
extends RefCounted

var ok: bool
var entry: ContentEntryValue
var error: ContentCodecError

static func success(value: ContentEntryValue) -> ContentEntryCompileResult:
	return ContentEntryCompileResult.new(true, value, null)

static func failure(path: StringName, source_id: StringName = &"") -> ContentEntryCompileResult:
	return ContentEntryCompileResult.new(false, null, ContentCodecError.new(path, source_id))

func _init(p_ok: bool, p_entry: ContentEntryValue, p_error: ContentCodecError) -> void:
	ResultInvariant.require(p_ok, p_error, p_entry != null, p_entry == null)
	ok = p_ok
	entry = p_entry.deep_clone() if p_ok and p_entry != null else null
	error = p_error if not p_ok else null
