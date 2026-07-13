class_name ContentIdMigrationPort
extends RefCounted

func resolve(request: ContentIdMigrationRequest) -> ContentIdMigrationResult:
	return ContentIdMigrationResult.incompatible(
		ContentIdMigrationError.new(
			ContentIdMigrationError.TOMBSTONE_REQUIRED,
			request.field_path,
			OptionalStringNameValue.new(request.content_id)
		)
	)
