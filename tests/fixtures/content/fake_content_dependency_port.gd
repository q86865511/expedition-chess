class_name FakeContentDependencyPort
extends ContentDependencyPort

var missing_assets: Array[String] = []
var missing_localization_keys: Array[StringName] = []

func asset_exists(path: String) -> bool:
	return not path.is_empty() and not missing_assets.has(path)

func localization_key_exists(key: StringName) -> bool:
	return not key.is_empty() and not missing_localization_keys.has(key)
