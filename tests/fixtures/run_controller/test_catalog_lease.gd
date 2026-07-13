class_name TestCatalogLease
extends CatalogLease

var _test_active: bool = true

func _init(p_manifest_digest: String) -> void:
	super(null, p_manifest_digest)

func is_active() -> bool:
	return _test_active

func release() -> void:
	_test_active = false
