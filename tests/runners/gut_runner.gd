extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const GutScript = preload("res://addons/gut/gut.gd")
const GutConfigScript = preload("res://addons/gut/gut_config.gd")
const JunitExportScript = preload("res://addons/gut/junit_xml_export.gd")
const ResultExportScript = preload("res://addons/gut/result_exporter.gd")
const ARTIFACT_PATH: String = "res://artifacts/test/gut.xml"

var _gut: GutMain
var _registered_logger: bool = false
var _finished: bool = false
var _contract_force_infrastructure_error: bool = false
var _contract_simulate_logger_leak: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var config: RefCounted = GutConfigScript.new()
	var load_result: int = int(config.call("load_options", "res://.gutconfig.json"))
	if load_result < 0:
		_finish(3)
		return
	_apply_user_arguments(config)
	if _contract_force_infrastructure_error:
		_finish(3)
		return
	_gut = GutScript.new()
	_gut.error_tracker = GutUtils.get_error_tracker()
	_gut.add_children_to = get_root()
	get_root().add_child(_gut)
	_gut.end_run.connect(_on_end_run, CONNECT_ONE_SHOT)
	config.call("apply_options", _gut)
	_gut.ignore_pause_before_teardown = true
	GutErrorTracker.register_logger(_gut.error_tracker)
	_registered_logger = true
	_gut.test_scripts(true)


func _apply_user_arguments(config: RefCounted) -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var options: Dictionary = config.get("options") as Dictionary
	var index: int = 0
	while index < arguments.size():
		if arguments[index] == "--contract-force-infrastructure-error":
			_contract_force_infrastructure_error = true
			index += 1
			continue
		if arguments[index] == "--contract-simulate-logger-leak":
			_contract_simulate_logger_leak = true
			index += 1
			continue
		if arguments[index] == "--test-path" and index + 1 < arguments.size():
			var test_path: String = arguments[index + 1]
			if test_path.ends_with(".gd"):
				options["dirs"] = []
				options["tests"] = [test_path]
			else:
				options["dirs"] = [test_path]
				options["tests"] = []
			index += 2
			continue
		index += 1
	# Object.get() does not promise that a container mutation will be written
	# back to a script property.  Assign it explicitly so TestPath is a hard
	# selection boundary rather than a best-effort hint.
	config.set("options", options)


func _on_end_run() -> void:
	if _finished:
		return
	var result_exporter: RefCounted = ResultExportScript.new()
	var exported_value: Variant = result_exporter.call("get_results_dictionary", _gut)
	if not exported_value is Dictionary:
		_finish(3)
		return
	var exported: Dictionary = exported_value
	var scripts_value: Variant = exported.get("test_scripts", null)
	if not scripts_value is Dictionary:
		_finish(3)
		return
	var scripts: Dictionary = scripts_value
	var properties_value: Variant = scripts.get("props", null)
	if not properties_value is Dictionary:
		_finish(3)
		return
	var properties: Dictionary = properties_value
	var test_count: int = int(properties.get("tests", 0))
	var fail_count: int = maxi(_gut.get_fail_count(), int(properties.get("failures", 0)))
	var error_count: int = int(properties.get("errors", 0))
	var orphan_count: int = int(properties.get("orphans", 0))
	var assertion_count: int = _gut.get_assert_count()
	if test_count <= 0:
		_finish(3)
		return
	var exporter: RefCounted = JunitExportScript.new()
	var xml: String = str(exporter.call("get_results_xml", _gut))
	xml = _insert_root_diagnostics(xml, error_count, orphan_count, assertion_count)
	xml = _insert_version_properties(xml)
	var write_result: int = _write_and_verify_xml(xml)
	if write_result != OK:
		_finish(3)
	elif fail_count > 0 or error_count > 0 or orphan_count > 0:
		_finish(2)
	else:
		_finish(0)


func _insert_root_diagnostics(
	xml: String,
	error_count: int,
	orphan_count: int,
	assertion_count: int
) -> String:
	var marker: String = "<testsuites "
	var replacement: String = (
		'<testsuites errors="%d" orphans="%d" assertions="%d" '
		% [error_count, orphan_count, assertion_count]
	)
	return xml.replace(marker, replacement)


func _insert_version_properties(xml: String) -> String:
	var properties: Dictionary = Support.version_properties()
	var property_xml: String = "    <properties>"
	var keys: Array = properties.keys()
	keys.sort()
	for key: Variant in keys:
		property_xml += "<property name=\"%s\" value=\"%s\"/>" % [
			Support.xml_escape(str(key)),
			Support.xml_escape(str(properties[key])),
		]
	property_xml += "</properties>"
	var output: PackedStringArray = PackedStringArray()
	for line: String in xml.split("\n"):
		output.append(line)
		if line.strip_edges().begins_with("<testsuite "):
			output.append(property_xml)
	return "\n".join(output)


func _write_and_verify_xml(xml: String) -> int:
	var absolute_path: String = ProjectSettings.globalize_path(ARTIFACT_PATH)
	var directory_error: int = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(xml)
	file.flush()
	var write_error: int = file.get_error()
	file = null
	if write_error != OK:
		return write_error
	var read_back: String = FileAccess.get_file_as_string(absolute_path)
	if read_back != xml:
		return ERR_FILE_CORRUPT
	var parser: XMLParser = XMLParser.new()
	var parse_error: int = parser.open_buffer(read_back.to_utf8_buffer())
	if parse_error != OK:
		return parse_error
	var saw_root: bool = false
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "testsuites":
			saw_root = true
	if not saw_root:
		return ERR_PARSE_ERROR
	return OK


func _finish(exit_code: int) -> void:
	if _finished:
		return
	_finished = true
	var logger_cleanup_failed: bool = false
	if _registered_logger:
		if not _contract_simulate_logger_leak:
			GutErrorTracker.deregister_logger(_gut.error_tracker)
		logger_cleanup_failed = GutErrorTracker.registered_loggers.has(_gut.error_tracker)
		if logger_cleanup_failed:
			# The contract probe intentionally exercises this branch.  Remove the
			# logger after observing the leak so the process still tears down cleanly.
			GutErrorTracker.deregister_logger(_gut.error_tracker)
		_registered_logger = false
	if _gut != null and _gut.get_parent() != null:
		_gut.get_parent().remove_child(_gut)
		_gut.queue_free()
	quit(3 if logger_cleanup_failed else exit_code)
