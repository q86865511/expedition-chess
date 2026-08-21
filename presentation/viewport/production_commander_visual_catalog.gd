class_name ProductionCommanderVisualCatalog
extends RefCounted

## Presentation-only commander portrait cues. The vertical slice does not ship
## canonical commander art, so the facility screens use distinct, original
## pixel silhouettes instead of pretending that a unit portrait is a commander.

const PORTRAIT_SIZE := 96
const COMMANDER_IDS: Array[StringName] = [
	&"commander.slice_c0",
	&"commander.slice_c1",
	&"commander.slice_c2",
]
const PALETTES: Array[Dictionary] = [
	{
		"background": Color("172c3d"),
		"frame": Color("8fd8c7"),
		"shadow": Color("10202f"),
		"cloth": Color("2c6d73"),
		"highlight": Color("d6f1dc"),
	},
	{
		"background": Color("3d2523"),
		"frame": Color("e6a05a"),
		"shadow": Color("21191d"),
		"cloth": Color("8b4332"),
		"highlight": Color("ffe0a1"),
	},
	{
		"background": Color("292642"),
		"frame": Color("b6a4e8"),
		"shadow": Color("17182a"),
		"cloth": Color("534b86"),
		"highlight": Color("e6ddff"),
	},
]

var _cache: Dictionary[StringName, Texture2D] = {}


func try_portrait(commander_id: StringName) -> Texture2D:
	var commander_index := COMMANDER_IDS.find(commander_id)
	if commander_index < 0:
		return null
	if _cache.has(commander_id):
		return _cache[commander_id]
	var portrait := _build_portrait(commander_index)
	_cache[commander_id] = portrait
	return portrait


func _build_portrait(commander_index: int) -> Texture2D:
	var palette := PALETTES[commander_index]
	var image := Image.create(
		PORTRAIT_SIZE, PORTRAIT_SIZE, false, Image.FORMAT_RGBA8
	)
	var frame := palette["frame"] as Color
	var background := palette["background"] as Color
	var shadow := palette["shadow"] as Color
	var cloth := palette["cloth"] as Color
	var highlight := palette["highlight"] as Color
	image.fill(frame)
	image.fill_rect(Rect2i(4, 4, 88, 88), shadow)
	image.fill_rect(Rect2i(8, 8, 80, 80), background)
	# Recessed rays make the cue read as a portrait card, even at 150% UI.
	for ray_index: int in 5:
		image.fill_rect(
			Rect2i(18 + ray_index * 14, 12, 4, 60),
			Color(background, 0.78)
		)
	# Broad stepped shoulders and a shadowed face form a neutral commander bust.
	for row_index: int in 7:
		image.fill_rect(Rect2i(
			28 - row_index * 3,
			58 + row_index * 4,
			40 + row_index * 6,
			4
		), cloth)
	image.fill_rect(Rect2i(34, 27, 28, 31), frame)
	image.fill_rect(Rect2i(38, 31, 20, 23), shadow)
	image.fill_rect(Rect2i(43, 36, 4, 4), highlight)
	image.fill_rect(Rect2i(51, 36, 4, 4), highlight)
	image.fill_rect(Rect2i(45, 48, 8, 3), frame)
	match commander_index:
		0:
			_draw_crowned_helm(image, frame, highlight)
		1:
			_draw_horned_helm(image, frame, highlight)
		2:
			_draw_hood(image, frame, highlight, cloth)
	image.fill_rect(Rect2i(42, 67, 12, 12), shadow)
	image.fill_rect(Rect2i(46, 70, 4, 6), highlight)
	return ImageTexture.create_from_image(image)


func _draw_crowned_helm(image: Image, frame: Color, highlight: Color) -> void:
	image.fill_rect(Rect2i(32, 24, 34, 7), frame)
	image.fill_rect(Rect2i(35, 17, 6, 10), highlight)
	image.fill_rect(Rect2i(46, 13, 6, 14), highlight)
	image.fill_rect(Rect2i(57, 17, 6, 10), highlight)


func _draw_horned_helm(image: Image, frame: Color, highlight: Color) -> void:
	image.fill_rect(Rect2i(32, 23, 34, 8), frame)
	image.fill_rect(Rect2i(24, 18, 12, 5), highlight)
	image.fill_rect(Rect2i(22, 14, 7, 5), highlight)
	image.fill_rect(Rect2i(62, 18, 12, 5), highlight)
	image.fill_rect(Rect2i(69, 14, 7, 5), highlight)


func _draw_hood(
	image: Image,
	frame: Color,
	highlight: Color,
	cloth: Color
) -> void:
	image.fill_rect(Rect2i(30, 25, 38, 8), cloth)
	image.fill_rect(Rect2i(27, 31, 9, 29), cloth)
	image.fill_rect(Rect2i(62, 31, 9, 29), cloth)
	image.fill_rect(Rect2i(38, 21, 22, 6), frame)
	image.fill_rect(Rect2i(46, 17, 6, 6), highlight)
