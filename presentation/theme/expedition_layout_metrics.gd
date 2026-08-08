class_name ExpeditionLayoutMetrics
extends RefCounted

## B1R3 對齊/尺寸契約的唯一入口：畫面程式碼不得再直接寫
## `custom_minimum_size = Vector2(硬編, 硬編)`。
## - `set_min()` 以 reference 空間（1280×720）登記基準尺寸，
##   ExpeditionThemeRuntime 依 UI 縮放把「高度」乘 factor（寬度屬版面欄位
##   預算，維持 reference 值；內容變大時 Godot 的 minimum size 仍會撐開）。
## - `set_fixed_cell()` 用於棋盤/bench 格這類「sprite 佔位」控制項：
##   兩軸皆固定、文字以省略號截斷，並攜帶幾何稽核的明示豁免 meta。
## - `px()` 讀取已隨縮放發布的 ExpeditionSpacing token。

const META_BASE_MINIMUM := &"expedition_theme_base_minimum"
const META_FIXED_MINIMUM := &"expedition_theme_fixed_minimum"
const META_ALLOW_TEXT_CLIP := &"expedition_allow_text_clip"


static func set_min(control: Control, width: float, height: float) -> void:
	if control == null:
		return
	control.set_meta(META_BASE_MINIMUM, Vector2(width, height))
	control.custom_minimum_size = Vector2(width, height)


static func set_fixed_cell(button: Button, width: float, height: float) -> void:
	if button == null:
		return
	button.set_meta(META_BASE_MINIMUM, Vector2(width, height))
	button.set_meta(META_FIXED_MINIMUM, true)
	button.set_meta(META_ALLOW_TEXT_CLIP, true)
	button.custom_minimum_size = Vector2(width, height)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


static func px(owner: Control, token: StringName) -> int:
	if owner == null:
		return 0
	return owner.get_theme_constant(token, &"ExpeditionSpacing")
