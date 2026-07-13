extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const SUITE_PATH: String = "res://tests/fixtures/content/content_verification_suite.gd"
const ARTIFACT_PATH: String = "res://artifacts/test/content-validation.json"

var _started_at_utc: String = ""


func _init() -> void:
	_started_at_utc = Support.utc_now()
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists(SUITE_PATH):
		_finish_infrastructure("Content verification suite is missing")
		return
	var suite_script: Script = load(SUITE_PATH) as Script
	if suite_script == null:
		_finish_infrastructure("Content verification suite could not be loaded")
		return
	var suite: RefCounted = suite_script.new()
	if suite == null or not suite.has_method("run"):
		_finish_infrastructure("Content verification suite lacks run()")
		return
	var result_value: Variant = suite.call("run", _case_filter())
	if not result_value is Dictionary:
		_finish_infrastructure("Content verification suite returned an invalid report")
		return
	var result: Dictionary = result_value
	var case_count: int = int(result.get("case_count", 0))
	var failures_value: Variant = result.get("failures", null)
	if case_count <= 0 or not failures_value is Array:
		_finish_infrastructure("Content verification suite executed no cases or omitted failures")
		return
	var failures: Array = failures_value
	var completed: Array[String] = []
	for scope: Variant in result.get("completed_scopes", []):
		completed.append(str(scope))
	var deferred: Array[String] = ["formal_content", "battle_entity_stress", "gameplay_soak"]
	var report: Dictionary = Support.base_report("content-validation", _started_at_utc, completed, deferred)
	report["case_filter"] = _case_filter()
	report["case_count"] = case_count
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	if result.has("population_report"):
		report["population_report"] = result["population_report"]
	if result.has("entity_report"):
		report["entity_report"] = result["entity_report"]
	var artifact_error: int = Support.write_json_artifact(ARTIFACT_PATH, report)
	if artifact_error != OK:
		quit(3)
	elif failures.is_empty():
		quit(0)
	else:
		quit(2)


func _case_filter() -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == "--case":
			return arguments[index + 1]
	return ""


func _finish_infrastructure(message: String) -> void:
	var completed: Array[String] = []
	var deferred: Array[String] = ["formal_content", "battle_entity_stress", "gameplay_soak"]
	var report: Dictionary = Support.base_report("content-validation", _started_at_utc, completed, deferred)
	report["case_count"] = 0
	report["failures"] = [message]
	report["passed"] = false
	Support.write_json_artifact(ARTIFACT_PATH, report)
	quit(3)
