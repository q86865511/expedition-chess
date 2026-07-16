class_name ContentGenerationMigrationPort
extends RefCounted

func migrate_generation(_request: ContentGenerationMigrationRequest) -> ContentGenerationMigrationResult:
	return ContentGenerationMigrationResult.failure(
		ContentGenerationMigrationError.new(
			ContentGenerationMigrationError.PORT_UNCONFIGURED,
			&"run.content_snapshot"
		)
	)
