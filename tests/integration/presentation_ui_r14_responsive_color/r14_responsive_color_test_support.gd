extends RefCounted

const SCENE_PATH := "res://scenes/production/run_combat.tscn"


static func instantiate_combat(
	test: GutTest,
	size: Vector2
) -> ProductionScreen:
	var packed := load(SCENE_PATH) as PackedScene
	test.assert_not_null(packed)
	if packed == null:
		return null
	var screen := packed.instantiate() as ProductionScreen
	test.assert_not_null(screen)
	if screen == null:
		return null
	screen.size = size
	test.add_child_autofree(screen)
	return screen


static func accessibility_runtime(screen: ProductionScreen) -> Control:
	return (
		screen.get_node_or_null("AccessibilityRuntime") as Control
		if screen != null
		else null
	)


static func consumer(screen: ProductionScreen) -> PresentationSettingsRuntimeConsumer:
	return PresentationSettingsRuntimeConsumer.new(screen)


static func activate(
	test: GutTest,
	consumer_value: PresentationSettingsRuntimeConsumer,
	snapshot: SettingsSnapshot
) -> void:
	for kind: StringName in [&"theme", &"viewport", &"localization"]:
		test.assert_eq(consumer_value.activate(kind, snapshot), &"")


static func rect_inside(
	control: Control,
	safe_size: Vector2
) -> bool:
	if control == null:
		return false
	var rect := Rect2(control.position, control.size)
	return Rect2(Vector2.ZERO, safe_size).encloses(rect)


static func visual_signature(screen: ProductionScreen) -> String:
	var runtime := accessibility_runtime(screen)
	if runtime == null:
		return ""
	var background := runtime.get_node_or_null("Background") as ColorRect
	var summary := runtime.get_node_or_null("StateSummary") as Label
	var damage := runtime.get_node_or_null("DamageEvents") as Control
	var cjk := runtime.get_node_or_null("CjkBody") as Label
	return "|".join([
		str(runtime.scale),
		str(background.color if background != null else Color.TRANSPARENT),
		str(summary.get_theme_color(&"font_color") if summary != null else Color.TRANSPARENT),
		str(damage.position if damage != null else Vector2.ZERO),
		str(damage.size if damage != null else Vector2.ZERO),
		str(cjk.position if cjk != null else Vector2.ZERO),
		str(cjk.size if cjk != null else Vector2.ZERO),
	])
