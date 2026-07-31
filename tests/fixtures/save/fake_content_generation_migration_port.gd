class_name FakeContentGenerationMigrationPort
extends ContentGenerationMigrationPort

var requests: Array[ContentGenerationMigrationRequest] = []
var result: ContentGenerationMigrationResult


func _init(p_result: ContentGenerationMigrationResult = null) -> void:
	result = p_result


func migrate_generation(request: ContentGenerationMigrationRequest) -> ContentGenerationMigrationResult:
	requests.append(request.deep_clone())
	if result == null:
		return ContentGenerationMigrationResult.failure(
			ContentGenerationMigrationError.new(
				ContentGenerationMigrationError.PORT_UNCONFIGURED,
				&"content_generation_migration"
			)
		)
	return ContentGenerationMigrationResult.new(
		result.ok,
		result.target_receipt,
		result.migration_receipt,
		result.error,
		result.plan
	)
