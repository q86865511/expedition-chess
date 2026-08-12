class_name ContentRegistryMigrationAdapter
extends ContentIdMigrationPort

var _registry: ContentRegistryService

func _init(registry: ContentRegistryService) -> void:
	_registry = registry

func resolve(request: ContentIdMigrationRequest) -> ContentIdMigrationResult:
	if _registry == null or request == null:
		return _incompatible(request)
	var lookup := _registry._migration_lookup(request.content_id)
	if lookup.kind == ContentMigrationLookup.Kind.MISSING or not request.accepts_category(lookup.category):
		return _incompatible(request)
	match lookup.kind:
		ContentMigrationLookup.Kind.ACTIVE:
			return ContentIdMigrationResult.active(lookup.resolved_id)
		ContentMigrationLookup.Kind.ALIAS:
			return ContentIdMigrationResult.alias(lookup.resolved_id)
		ContentMigrationLookup.Kind.TOMBSTONE:
			if request.required_for_active_run or lookup.tombstone.policy == &"incompatible_required": return _incompatible(request)
			if lookup.tombstone.policy == &"safe_replace" and lookup.tombstone.has_replacement:
				var replacement := _registry._migration_lookup(lookup.tombstone.replacement_id)
				if replacement.kind in [ContentMigrationLookup.Kind.ACTIVE, ContentMigrationLookup.Kind.ALIAS]:
					return ContentIdMigrationResult.safe_replace(replacement.resolved_id)
				return _incompatible(request)
			return ContentIdMigrationResult.safe_absent()
	return _incompatible(request)

func _incompatible(request: ContentIdMigrationRequest) -> ContentIdMigrationResult:
	var path := request.field_path if request != null else &"content_id"
	var source := request.content_id if request != null else &"unknown.missing"
	return ContentIdMigrationResult.incompatible(ContentIdMigrationError.new(
		ContentIdMigrationError.TOMBSTONE_REQUIRED, path, OptionalStringNameValue.new(source)))
