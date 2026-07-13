extends SceneTree

func _init() -> void:
	var suite_script := load("res://tests/fixtures/content/content_verification_suite.gd")
	if suite_script == null:
		push_error("content verification suite failed to load")
		quit(3)
		return
	var suite: RefCounted = suite_script.new()
	if suite == null:
		push_error("content verification suite failed to instantiate")
		quit(3)
		return
	var result: Dictionary = suite.call("run")
	print(JSON.stringify(result))
	quit(0 if bool(result["ok"]) else 2)
