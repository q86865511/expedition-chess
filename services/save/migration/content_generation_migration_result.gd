class_name ContentGenerationMigrationResult
extends RefCounted

var ok: bool
var target_receipt: PinnedCatalogBuildReceipt
var migration_receipt: RefCounted
var error: ContentGenerationMigrationError

static func success(
	p_target_receipt: PinnedCatalogBuildReceipt,
	p_migration_receipt: RefCounted
) -> ContentGenerationMigrationResult:
	return ContentGenerationMigrationResult.new(true, p_target_receipt, p_migration_receipt, null)

static func failure(p_error: ContentGenerationMigrationError) -> ContentGenerationMigrationResult:
	return ContentGenerationMigrationResult.new(false, null, null, p_error)

func _init(
	p_ok: bool,
	p_target_receipt: PinnedCatalogBuildReceipt,
	p_migration_receipt: RefCounted,
	p_error: ContentGenerationMigrationError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_target_receipt != null and p_migration_receipt != null,
		p_target_receipt == null and p_migration_receipt == null
	)
	ok = p_ok
	target_receipt = p_target_receipt.deep_clone() if p_target_receipt != null else null
	migration_receipt = p_migration_receipt.deep_clone() if p_migration_receipt != null else null
	error = p_error.deep_clone() if p_error != null else null
