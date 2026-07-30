class_name ProjectContentDependencyPort
extends ContentDependencyPort

var _localization_catalog: LocalizationCatalog


func _init(localization_catalog: LocalizationCatalog) -> void:
	_localization_catalog = localization_catalog


func asset_exists(path: String) -> bool:
	return not path.is_empty() and ResourceLoader.exists(path)


func localization_key_exists(key: StringName) -> bool:
	if _localization_catalog == null:
		return false
	return _localization_catalog.resolve(
		_localization_catalog.default_locale(), key
	).ok
