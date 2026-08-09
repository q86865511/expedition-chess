class_name ExpeditionLayoutMetrics
extends RefCounted

## B1R3 對齊/尺寸契約的唯一入口：畫面程式碼不得再直接寫
## `custom_minimum_size = Vector2(硬編, 硬編)`。
## - `set_min()` 以 reference 空間（1280×720）登記基準尺寸，
##   ExpeditionThemeRuntime 依 UI 縮放把「高度」乘 factor（寬度屬版面欄位
##   預算，維持 reference 值；內容變大時 Godot 的 minimum size 仍會撐開）。
## - `set_fixed_cell()` 用於棋盤/bench 格這類「sprite 佔位」控制項：
##   兩軸皆固定、文字以省略號截斷，並攜帶幾何稽核的明示豁免 meta。
## 寬度值屬各畫面的欄位預算，直接以字面值寫在呼叫端（單一事實來源；
## 曾考慮 theme token 但零消費者的平行常數只會分歧）。

const META_BASE_MINIMUM := &"expedition_theme_base_minimum"
const META_FIXED_MINIMUM := &"expedition_theme_fixed_minimum"
const META_ALLOW_TEXT_CLIP := &"expedition_allow_text_clip"


static func set_min(control: Control, width: float, height: float) -> void:
	if control == null:
		return
	control.set_meta(META_BASE_MINIMUM, Vector2(width, height))
	control.custom_minimum_size = Vector2(width, height)


## reference 空間固定尺寸（兩軸皆不隨縮放）：底部帶/棋盤等骨架內的控制項，
## 縮放感由字級與內距呈現，尺寸由版面預算持有。
static func set_fixed_min(control: Control, width: float, height: float) -> void:
	set_min(control, width, height)
	control.set_meta(META_FIXED_MINIMUM, true)


static func set_fixed_cell(button: Button, width: float, height: float) -> void:
	if button == null:
		return
	button.set_meta(META_BASE_MINIMUM, Vector2(width, height))
	button.set_meta(META_FIXED_MINIMUM, true)
	button.set_meta(META_ALLOW_TEXT_CLIP, true)
	button.custom_minimum_size = Vector2(width, height)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


