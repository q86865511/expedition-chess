class_name ContentGenerationMigrationValidationResult
extends RefCounted

var ok: bool
var receipt: ContentGenerationMigrationReceipt
var error: ContentGenerationMigrationError

static func success(p_receipt: ContentGenerationMigrationReceipt) -> ContentGenerationMigrationValidationResult:
	return ContentGenerationMigrationValidationResult.new(true, p_receipt, null)

static func failure(p_error: ContentGenerationMigrationError) -> ContentGenerationMigrationValidationResult:
	return ContentGenerationMigrationValidationResult.new(false, null, p_error)

func _init(
	p_ok: bool,
	p_receipt: ContentGenerationMigrationReceipt,
	p_error: ContentGenerationMigrationError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_receipt != null,
		p_receipt == null
	)
	ok = p_ok
	receipt = p_receipt.deep_clone() if p_receipt != null else null
	error = p_error.deep_clone() if p_error != null else null
