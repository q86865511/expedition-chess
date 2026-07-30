extends GutTest

const PRESENTER_PATH := "res://presentation/screens/menu_exit_presenter.gd"


class FakeExitHost:
	extends RefCounted

	var request_count: int = 0
	var state_mutations: int = 0
	var route_mutations: int = 0
	var save_mutations: int = 0

	func request_exit() -> AppActionResult:
		request_count += 1
		return AppActionResult.success(false)


func test_exit_button_host_binding_keeps_fake_runner_alive() -> void:
	var script := _load_script(PRESENTER_PATH)
	if script == null:
		return
	var presenter: Object = script.new()
	if not _require_methods(presenter, [&"bind_exit_button"]):
		return
	var button := Button.new()
	button.name = "Exit"
	var runner := Node.new()
	add_child_autofree(runner)
	runner.add_child(button)
	var host := FakeExitHost.new()
	var bind_error: Variant = presenter.call("bind_exit_button", button, host)
	assert_eq(bind_error, &"", "MENU Exit button must bind through the injected host")
	if bind_error != &"":
		return

	button.pressed.emit()
	assert_eq(host.request_count, 1, "one click forwards exactly one request_exit")
	assert_true(runner.is_inside_tree(), "the presenter must never quit the fake SceneTree")
	assert_eq(host.state_mutations, 0)
	assert_eq(host.route_mutations, 0)
	assert_eq(host.save_mutations, 0)


func _load_script(path: String) -> GDScript:
	if not FileAccess.file_exists(path):
		assert_true(false, "%s must provide the T08 injected host boundary" % path)
		return null
	var script := load(path) as GDScript
	assert_not_null(script)
	return script


func _require_methods(target: Object, methods: Array[StringName]) -> bool:
	for method: StringName in methods:
		if not target.has_method(method):
			assert_true(false, "%s must implement %s" % [PRESENTER_PATH, method])
			return false
	return true
