class_name CatalogLease
extends RefCounted

var manifest_digest: String
var _registry: ContentRegistryService
var _released: bool

func _init(p_registry: ContentRegistryService = null, p_digest: String = "") -> void:
	_registry = p_registry
	manifest_digest = p_digest
	_released = false

func is_active() -> bool:
	return not _released \
		and _registry != null \
		and _registry._lease_is_active(manifest_digest)

func release() -> void:
	_release_internal()

func _release_internal() -> void:
	if _released: return
	_released = true
	if _registry != null:
		_registry.release_catalog_lease(manifest_digest)
	_registry = null

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _released:
		return
	_released = true
	if _registry != null:
		_registry.release_catalog_lease(manifest_digest)
	_registry = null
