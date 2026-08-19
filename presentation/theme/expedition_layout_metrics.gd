class_name ExpeditionLayoutMetrics
extends RefCounted

const COMBAT_ATLAS_CELL_SIZE := Vector2i(128, 128)
const COMBAT_EFFECT_LAYER: int = 1000
const COMBAT_VFX_SCALE: float = 0.42
const COMBAT_VFX_SKILL_OFFSET := Vector2(-20.0, -48.0)
const COMBAT_VFX_ATTACK_OFFSET := Vector2(18.0, -28.0)
const COMBAT_VFX_HIT_OFFSET := Vector2(0.0, -34.0)
const COMBAT_VFX_STATUS_OFFSET := Vector2(22.0, -48.0)
const COMBAT_VFX_DURATION_MS: float = 1280.0
const COMBAT_DAMAGE_FLOAT_OFFSET := Vector2(-38.0, -98.0)
const COMBAT_DAMAGE_FLOAT_SIZE := Vector2(84.0, 34.0)
const COMBAT_DAMAGE_FLOAT_RISE: float = 42.0
const COMBAT_DAMAGE_FLOAT_DURATION_MS: float = 1450.0
const COMBAT_DAMAGE_FONT_SIZE: int = 24
const COMBAT_DAMAGE_OUTLINE_SIZE: int = 4
const COMBAT_DAMAGE_LABEL_LAYER: int = 1100
const COMBAT_BACKGROUND_MODULATE := Color(0.78, 0.84, 0.94, 0.72)
const COMBAT_PLAYBACK_CUE_HEIGHT: float = 28.0

## PREPARE 與 COMBAT 共用的商店卡。in-run-hud reference 的 197×134 是
## 1920/UI100 上限；182×108 讓五卡加商店／分組／固定動作欄後，仍在
## UI150 的既有安全區與 111px 底帶內
## 完整可見，仍保留同一張卡的滿版構圖比例。
const SHOP_CARD_SIZE := Vector2(182.0, 108.0)
const SHOP_CARD_BORDER_INSET: float = 2.0
const SHOP_CARD_BOTTOM_INFO_HEIGHT: float = 27.0
const SHOP_CARD_BOTTOM_GRADIENT_START: float = 0.42
const SHOP_CARD_CONTENT_INSET: float = 5.0
const SHOP_CARD_TRAIT_BADGE_HEIGHT: float = 19.0
const SHOP_CARD_TRAIT_BADGE_WIDTH: float = 76.0
const SHOP_CARD_TRAIT_BADGE_ICON_SIZE: float = 13.0
const SHOP_CARD_TRAIT_BADGE_GAP: float = 2.0
const SHOP_CARD_TRAIT_BADGE_MAX: int = 3
const SHOP_CARD_TRAIT_ATLAS_CELL_SIZE := Vector2(128.0, 128.0)
const SHOP_CARD_COST_ICON_SIZE: float = 13.0
const SHOP_CARD_TIER_PIP_SIZE: float = 5.0
const SHOP_CARD_TIER_CUE_WIDTH: float = 31.0
const SHOP_CARD_OWNED_PIP_SIZE: float = 5.0
const SHOP_CARD_OWNED_CUE_WIDTH: float = 24.0
const SHOP_CARD_STAR_CUE_SIZE := Vector2(22.0, 12.0)

## B1 對齊/尺寸契約的唯一 setter：presentation 程式碼不得再直接寫
## `custom_minimum_size`。所有輸入皆為 1920×1080 reference 空間的實際值；
## 呼叫端若由舊 1280×720 基準遷移，必須顯式乘 1.5，避免 helper 隱藏單位。
## ExpeditionThemeRuntime 依 UI 縮放把「高度」乘 factor（寬度屬版面欄位
## 預算，維持 reference 值；內容變大時 Godot 的 minimum size 仍會撐開）。
## - `set_fixed_cell()` 用於棋盤/bench 格這類「sprite 佔位」控制項：
##   兩軸皆固定、文字以省略號截斷，並攜帶幾何稽核的明示豁免 meta。
## 寬度值屬各畫面的欄位預算，直接以字面值寫在呼叫端（單一事實來源；
## 曾考慮 theme token 但零消費者的平行常數只會分歧）。

const META_BASE_MINIMUM := &"expedition_theme_base_minimum"
const META_FIXED_MINIMUM := &"expedition_theme_fixed_minimum"
const META_ALLOW_TEXT_CLIP := &"expedition_allow_text_clip"

## MENU_MAIN 仍使用同一個 1920×1080 reference 空間；key art 全幅鋪底，
## 標題留在左上安全區，按鈕直接落在 ImageGen 特意保留的右側暗部。
const MENU_TITLE_RECT := Rect2(108.0, 66.0, 930.0, 96.0)
const MENU_ACTIONS_RECT := Rect2(1356.0, 222.0, 432.0, 636.0)

## SETTINGS / RESULTS 已由 ProductionLayoutShell 持有外框與安全區；以下只描述
## composition 內部的 reference 尺度，避免 scene offset 與程式布局分裂。
const SETTINGS_DRAFT_STATUS_HEIGHT: float = 66.0
const SETTINGS_SECTION_GAP: float = 18.0
const RESULTS_CARD_GAP: float = 18.0
const RESULTS_CARD_INSET: Vector2 = Vector2(30.0, 21.0)
const RESULTS_OUTCOME_CARD_HEIGHT: float = 132.0
const RESULTS_PRIMARY_CARD_HEIGHT: float = 174.0
const RESULTS_AUDIT_CARD_HEIGHT: float = 96.0
const RESULTS_METRIC_LABEL_HEIGHT: float = 36.0
const RESULTS_METRIC_LABEL_GAP: float = 6.0

## RUN_MAP 的節點圖完全位於 UI reference 空間。集中持有幾何可讓三種
## resolution 與 UI scale 共用同一套布局，且不把 presentation 尺寸散落
## 在畫面或繪圖程式中。
const RUN_MAP_GRAPH_MINIMUM := Vector2(840.0, 420.0)
const RUN_MAP_NODE_SIZE := Vector2(78.0, 34.0)
const RUN_MAP_HORIZONTAL_INSET: float = 54.0
const RUN_MAP_ACT_GAP: float = 6.0
const RUN_MAP_ACT_HEADER_HEIGHT: float = 24.0
const RUN_MAP_SLOT_COUNT: int = 3
const RUN_MAP_LAYER_COUNT: int = 7
const RUN_MAP_STATE_FRAME_INSET: float = 4.0
const RUN_MAP_SELECTED_FRAME_INSET: float = 7.0
const RUN_MAP_CURRENT_MARKER_WIDTH: float = 20.0
const RUN_MAP_SEPARATOR_WIDTH: float = 1.0
const RUN_MAP_EDGE_BACKGROUND_WIDTH: float = 1.0
const RUN_MAP_EDGE_TRAVERSED_WIDTH: float = 2.0
const RUN_MAP_EDGE_FRONTIER_WIDTH: float = 4.0
const RUN_MAP_EDGE_BACKGROUND_ALPHA: float = 0.16
const RUN_MAP_EDGE_TRAVERSED_ALPHA: float = 0.68
const RUN_MAP_EDGE_FRONTIER_ALPHA: float = 0.96
const RUN_MAP_UNREACHABLE_ALPHA: float = 0.42
const RUN_MAP_DASH_LENGTH: float = 6.0
const RUN_MAP_ACCESSIBILITY_MINIMUM_HEIGHT: float = 168.0


static func set_min(control: Control, width: float, height: float) -> void:
	_set_minimum(control, Vector2(width, height), true)


## 動態計算、但已位於 1920×1080 reference 空間的尺寸也必須走唯一 setter。
static func set_reference_min(control: Control, minimum: Vector2) -> void:
	_set_minimum(control, minimum, true)


## Theme runtime 套用縮放後的值時不可覆寫已登記的 reference baseline。
static func set_runtime_min(control: Control, minimum: Vector2) -> void:
	_set_minimum(control, minimum, false)


## reference 空間固定尺寸（兩軸皆不隨縮放）：底部帶/棋盤等骨架內的控制項，
## 縮放感由字級與內距呈現，尺寸由版面預算持有。
static func set_fixed_min(control: Control, width: float, height: float) -> void:
	set_min(control, width, height)
	control.set_meta(META_FIXED_MINIMUM, true)


static func set_fixed_cell(button: Button, width: float, height: float) -> void:
	if button == null:
		return
	set_min(button, width, height)
	button.set_meta(META_FIXED_MINIMUM, true)
	button.set_meta(META_ALLOW_TEXT_CLIP, true)
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


static func _set_minimum(
	control: Control,
	minimum: Vector2,
	record_reference: bool
) -> void:
	if control == null:
		return
	if record_reference:
		control.set_meta(META_BASE_MINIMUM, minimum)
	control.custom_minimum_size = minimum
