class_name FakeContentIdMigrationPort
extends ContentIdMigrationPort

func resolve(request: ContentIdMigrationRequest) -> ContentIdMigrationResult:
	return ContentIdMigrationResult.active(request.content_id)
