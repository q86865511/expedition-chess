class_name PlaytestSessionReportWriter
extends RefCounted

const REPORT_ROOT: String = "user://playtest_reports"


func write(report: PlaytestSessionReport) -> StringName:
	var text := PlaytestSessionReportCodecV1.new().encode(report)
	if text.is_empty():
		return &"PLAYTEST_REPORT_INVALID"
	var absolute_root := ProjectSettings.globalize_path(REPORT_ROOT)
	if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
		return &"PLAYTEST_REPORT_DIRECTORY_FAILED"
	var final_path := REPORT_ROOT.path_join("session-%s.json" % report.session_id)
	var temp_path := final_path + ".tmp"
	var absolute_final := ProjectSettings.globalize_path(final_path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return &"PLAYTEST_REPORT_WRITE_FAILED"
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.get_file_as_string(temp_path) != text:
		DirAccess.remove_absolute(absolute_temp)
		return &"PLAYTEST_REPORT_READBACK_FAILED"
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(absolute_temp)
		return &"PLAYTEST_REPORT_ALREADY_EXISTS"
	if DirAccess.rename_absolute(absolute_temp, absolute_final) != OK:
		return &"PLAYTEST_REPORT_RENAME_FAILED"
	return &""


static func new_session_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
