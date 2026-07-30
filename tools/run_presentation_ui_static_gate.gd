extends SceneTree

const OUTPUT_PATH := "res://artifacts/test/presentation-ui-static-gate.json"


func _init() -> void:
	var report := PresentationUiStaticGate.new().validate_project("res://")
	var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		printerr("PUI static gate could not open evidence output.")
		quit(3)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	var read_back := FileAccess.get_file_as_string(OUTPUT_PATH)
	var parsed: Variant = JSON.parse_string(read_back)
	if not parsed is Dictionary:
		printerr("PUI static gate evidence read-back failed.")
		quit(3)
		return
	var exit_code := int((parsed as Dictionary).get("exit_code", 3))
	if exit_code == 0:
		print("PUI static gate passed.")
	else:
		printerr("PUI static gate failed: %s" % [
			(parsed as Dictionary).get("issues", [])
		])
	quit(exit_code)
