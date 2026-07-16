class_name ContentGenerationMigrationDraftResult
extends RefCounted

var ok: bool
var snapshot: ContentCatalogSnapshot
var selection: CatalogSelection
var active_entry_ids: Array[StringName] = []
var error: ContentGenerationMigrationError

static func success(
	p_snapshot: ContentCatalogSnapshot,
	p_selection: CatalogSelection,
	p_active_entry_ids: Array[StringName]
) -> ContentGenerationMigrationDraftResult:
	return ContentGenerationMigrationDraftResult.new(
		true, p_snapshot, p_selection, p_active_entry_ids, null
	)

static func failure(
	code: StringName,
	field_path: StringName
) -> ContentGenerationMigrationDraftResult:
	var empty_ids: Array[StringName] = []
	return ContentGenerationMigrationDraftResult.new(
		false,
		null,
		null,
		empty_ids,
		ContentGenerationMigrationError.new(code, field_path)
	)

func _init(
	p_ok: bool,
	p_snapshot: ContentCatalogSnapshot,
	p_selection: CatalogSelection,
	p_active_entry_ids: Array[StringName],
	p_error: ContentGenerationMigrationError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_snapshot != null and p_selection != null,
		p_snapshot == null and p_selection == null and p_active_entry_ids.is_empty()
	)
	ok = p_ok
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	selection = p_selection.deep_clone() if p_selection != null else null
	if p_ok: active_entry_ids.assign(p_active_entry_ids)
	error = p_error.deep_clone() if p_error != null else null
