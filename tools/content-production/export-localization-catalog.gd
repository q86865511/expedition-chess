extends SceneTree

const OUTPUT_PATH := "res://localization/catalog.v2.csv"
# runtime checksum 讀取的 byte-identical 副本(app/content/project_content_bootstrap.gd
# LOCALIZATION_CATALOG_PATH)。導出工具必須與 .csv 同步寫出,否則兩檔會漂移
# (review B-03):tests/unit/presentation_ui_content/test_localization_catalog_raw_parity.gd
# 用 SHA-256 相等斷言守住這件事。
const OUTPUT_RAW_PATH := "res://localization/catalog.v2.csv.raw"


func _init() -> void:
	# 匯出工具是 CSV 的產生端：來源是 GDScript 內建（restricted）目錄，
	# 產物 catalog.v2.csv 才是 runtime 的文案來源（review N3）。
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
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
	var buffer := ("\n".join(lines) + "\n").to_utf8_buffer()
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("could not open localization output")
		quit(3)
		return
	file.store_buffer(buffer)
	file.close()
	# byte-identical .raw 副本是 runtime SHA-256 checksum 的實際讀取來源(見上方常數
	# 註解);兩檔必須同一次寫出,避免只更新 .csv 造成 checksum 漂移。
	var raw_file := FileAccess.open(OUTPUT_RAW_PATH, FileAccess.WRITE)
	if raw_file == null:
		push_error("could not open localization raw output")
		quit(3)
		return
	raw_file.store_buffer(buffer)
	raw_file.close()
	print("exported %d localization rows to %s and %s" % [keys.size(), OUTPUT_PATH, OUTPUT_RAW_PATH])
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
