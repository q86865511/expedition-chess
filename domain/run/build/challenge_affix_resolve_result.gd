class_name ChallengeAffixResolveResult
extends RefCounted

## ChallengeAffixResolver.resolve 的具名結果。錯誤型別重用 RunRelicTableError——resolver 與
## RunModifierTableBuilder._append_challenge_rules 解析同一條 challenge unlock 鏈，失敗字彙
## （RESOLVE_FAILED／CATEGORY_MISMATCH／PAYLOAD_INVALID）語意完全對齊，不另造同構的錯誤類。

var ok: bool
var entries: Array[ChallengeAffixEntryState] = []
var error: RunRelicTableError

static func success(p_entries: Array[ChallengeAffixEntryState]) -> ChallengeAffixResolveResult:
	return ChallengeAffixResolveResult.new(true, p_entries, null)

static func failure(
	code: StringName, path: StringName, source_id: StringName = &""
) -> ChallengeAffixResolveResult:
	var empty: Array[ChallengeAffixEntryState] = []
	return ChallengeAffixResolveResult.new(
		false, empty, RunRelicTableError.new(code, path, source_id)
	)

func _init(
	p_ok: bool,
	p_entries: Array[ChallengeAffixEntryState],
	p_error: RunRelicTableError
) -> void:
	ResultInvariant.require(p_ok, p_error, true, p_entries.is_empty())
	ok = p_ok
	for entry: ChallengeAffixEntryState in p_entries:
		entries.append(entry.deep_clone())
	error = p_error.deep_clone() if p_error != null else null
