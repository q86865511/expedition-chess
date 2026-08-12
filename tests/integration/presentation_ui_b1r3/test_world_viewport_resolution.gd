extends GutTest

## B1R3 T2：§10.1 要求世界 SubViewport 恆為 640×360。先前 stretch 開關
## 切換的寫法會被 stretch=true 的 recalc 覆寫回容器尺寸，authored 解析度
## 從未生效；本測試鎖住 stretch_shrink 方案的結果。


func test_world_subviewport_renders_at_authored_640x360() -> void:
	var packed := load("res://app/main.tscn") as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var main: Node = autofree(packed.instantiate())
	add_child(main)
	await wait_process_frames(1)
	var coordinator := main.get_node_or_null(
		^"AppRoot/ViewportCoordinator"
	) as ProductionViewportCoordinator
	assert_not_null(coordinator)
	if coordinator == null:
		return
	assert_eq(coordinator.synchronize(Vector2i(1920, 1080)), &"")
	var ui_root := main.get_node_or_null(
		^"AppRoot/UiLayer/UiRoot"
	) as Control
	assert_not_null(ui_root)
	if ui_root != null:
		assert_eq(
			ui_root.size,
			Vector2(1920, 1080),
			"coordinator must overwrite the legacy authored offset at runtime"
		)
	var world_viewport := main.get_node_or_null(
		^"AppRoot/WorldViewportContainer/WorldViewport"
	) as SubViewport
	assert_not_null(world_viewport)
	if world_viewport == null:
		return
	assert_eq(
		world_viewport.size,
		Vector2i(640, 360),
		"world subviewport must render at the authored 640x360 (spec §10.1)"
	)
	var container := main.get_node_or_null(
		^"AppRoot/WorldViewportContainer"
	) as SubViewportContainer
	assert_not_null(container)
	if container != null:
		assert_true(container.stretch)
		assert_eq(container.stretch_shrink, 3)
	remove_child(main)
