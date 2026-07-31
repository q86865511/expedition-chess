extends SceneTree

const OUTPUT_PATH := "res://localization/catalog.v2.csv"


func _init() -> void:
	var catalog := LocalizationCatalog.new()
	var keys := catalog.keys_for_locale(&"zh_TW")
	if keys != catalog.keys_for_locale(&"en") or keys.is_empty():
		push_error("localization key sets are not equal or are empty")
		quit(2)
		return
	var lines: Array[String] = ["key,zh_TW,en"]
	for key: StringName in keys:
		var zh := catalog.resolve(&"zh_TW", key)
		var en := catalog.resolve(&"en", key)
		if not zh.ok or not en.ok or zh.value.is_empty() or en.value.is_empty():
			push_error("invalid localization value: %s" % key)
			quit(2)
			return
		lines.append(
			"%s,%s,%s" % [
				_csv(String(key)),
				_csv(zh.value),
				_csv(en.value),
			]
		)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://localization")
	)
	if directory_error != OK:
		push_error("could not create localization output directory")
		quit(3)
		return
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("could not open localization output")
		quit(3)
		return
	file.store_buffer(("\n".join(lines) + "\n").to_utf8_buffer())
	file.close()
	print("exported %d localization rows to %s" % [keys.size(), OUTPUT_PATH])
	quit(0)


func _csv(value: String) -> String:
	if (
		value.contains(",")
		or value.contains("\"")
		or value.contains("\n")
		or value.contains("\r")
	):
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value
