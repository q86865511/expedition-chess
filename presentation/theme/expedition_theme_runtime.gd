class_name ExpeditionThemeRuntime
extends RefCounted

const BASE_THEME: Theme = preload("res://theme/expedition_theme.tres")
const SUPPORTED_SCALES: Array[int] = [100, 125, 150]
const TYPE_SIZES: Dictionary = {
	&"ExpeditionTitle": 48,
	&"ExpeditionHeading": 36,
	&"ExpeditionAuxiliary": 24,
}
const TOKEN_SIZES: Dictionary = {
	&"title": 48,
	&"heading": 36,
	&"body": 27,
	&"auxiliary": 24,
}
## 這些型別是 reference 空間的「固定格陣/帶列」：水平間距屬寬度預算，
## 不隨 UI 縮放（否則 5 卡＋兩側欄在 150% 會擠出 1848 內容寬）。
const REFERENCE_SPACING_TYPES: Array[StringName] = [
	&"ExpeditionPrepareBottomBand",
	&"ExpeditionPrepareShopBand",
	&"ExpeditionShopCardsRow",
	&"ExpeditionBenchRow",
	&"ExpeditionInventoryRow",
	&"ExpeditionBoardGrid",
]
const SPACING_TOKENS: Dictionary = {
	&"space_1": 6,
	&"space_2": 12,
	&"space_3": 18,
	&"space_4": 24,
	&"space_6": 36,
	&"space_8": 48,
	&"safe_margin": 36,
	&"gutter": 24,
	&"min_button_height": 72,
}


func apply(host: Control, scale_percent: int) -> bool:
	# freed 物件在 GDScript 4 不等於 null；consumer 的 deferred apply 可能
	# 在 host 已釋放後才輪到（跨測試 teardown 邊界實測會發生）。
	# 只擋已釋放者——尚未進場景樹的 host 是合法呼叫端。
	if (
		host == null
		or not is_instance_valid(host)
		or scale_percent not in SUPPORTED_SCALES
	):
		return false
	var factor := float(scale_percent) / 100.0
	var base_metrics := _capture_control_metrics(host)
	var runtime_theme := BASE_THEME.duplicate(false) as Theme
	if runtime_theme == null:
		return false
	_scale_theme(runtime_theme, factor)
	host.theme = runtime_theme
	_apply_control_metrics(host, factor, base_metrics)
	host.set_meta(&"effective_theme_scale_percent", scale_percent)
	# host 自身不在 find_children 的結果裡；畫面級 relayout
	#（如 SETTINGS 的 _apply_settings_layout）必須一併通知。
	if host.has_method(&"apply_theme_scale_layout"):
		host.call(&"apply_theme_scale_layout", scale_percent)
	for node: Node in host.find_children("*", "", true, false):
		if node.has_method(&"apply_theme_scale_layout"):
			node.call(&"apply_theme_scale_layout", scale_percent)
	return true


## 縮放契約（REQ-UX-003）：字級、separation/spacing 常數、StyleBox content
## margin 一律 ×factor；border 與 texture margin 維持像素原值（nearest 像素風）。
## 逐 type 讀 BASE_THEME 的 authored 值計算，杜絕「variation 自帶字級不縮放」
## 一類的盲區。
func _scale_theme(runtime_theme: Theme, factor: float) -> void:
	runtime_theme.default_font_size = roundi(
		float(BASE_THEME.default_font_size) * factor
	)
	for type_name: StringName in BASE_THEME.get_type_list():
		for size_name: StringName in BASE_THEME.get_font_size_list(type_name):
			runtime_theme.set_font_size(
				size_name,
				type_name,
				roundi(
					float(BASE_THEME.get_font_size(size_name, type_name)) * factor
				)
			)
		for constant_name: StringName in BASE_THEME.get_constant_list(type_name):
			var constant_factor := (
				1.0
				if type_name in REFERENCE_SPACING_TYPES
				else factor
			)
			runtime_theme.set_constant(
				constant_name,
				type_name,
				roundi(
					float(
						BASE_THEME.get_constant(constant_name, type_name)
					) * constant_factor
				)
			)
		for style_name: StringName in BASE_THEME.get_stylebox_list(type_name):
			var base_style := BASE_THEME.get_stylebox(style_name, type_name)
			if base_style == null:
				continue
			var scaled := base_style.duplicate() as StyleBox
			for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				var margin := base_style.get_content_margin(side)
				if margin >= 0.0:
					scaled.set_content_margin(side, roundf(margin * factor))
			runtime_theme.set_stylebox(style_name, type_name, scaled)


func _capture_control_metrics(host: Control) -> Dictionary:
	var result: Dictionary = {}
	for control: Control in _metric_controls(host):
		var baseline: Vector2
		if control.has_meta(&"expedition_theme_base_minimum"):
			baseline = control.get_meta(&"expedition_theme_base_minimum")
		else:
			baseline = _authored_button_minimum(control)
		if control is BaseButton:
			baseline.y = maxf(
				baseline.y, float(SPACING_TOKENS[&"min_button_height"])
			)
		control.set_meta(&"expedition_theme_base_minimum", baseline)
		result[control.get_instance_id()] = baseline
	return result


## 縮放對象：所有 BaseButton（自動納入）＋任何由 ExpeditionLayoutMetrics
## 登記過 base meta 的 Control（Label/HSlider/GridContainer 等）。
func _metric_controls(host: Control) -> Array[Control]:
	var seen: Dictionary = {}
	var result: Array[Control] = []
	for node: Node in host.find_children("*", "BaseButton", true, false):
		var button := node as Control
		if button != null and not seen.has(button.get_instance_id()):
			seen[button.get_instance_id()] = true
			result.append(button)
	for node: Node in host.find_children("*", "Control", true, false):
		var control := node as Control
		if (
			control != null
			and control.has_meta(&"expedition_theme_base_minimum")
			and not seen.has(control.get_instance_id())
		):
			seen[control.get_instance_id()] = true
			result.append(control)
	return result


func _authored_button_minimum(button: Control) -> Vector2:
	var baseline := button.custom_minimum_size
	if baseline.x > 0.0 and baseline.y > 0.0:
		return baseline
	# 新畫面會先進入已套縮放 Theme 的 host，之後才觸發 deferred reapply。
	# 暫時以 100% 權威 Theme 量測未 authored 的軸，避免把繼承到的 150% 尺寸
	# 寫入 base meta，亦保留文字按鈕的真實最小寬度。
	var assigned_theme := button.theme
	button.theme = BASE_THEME
	var combined := button.get_combined_minimum_size()
	button.theme = assigned_theme
	if baseline.x <= 0.0:
		baseline.x = combined.x
	if baseline.y <= 0.0:
		baseline.y = combined.y
	return baseline


## 最小尺寸契約：寬度屬版面欄位預算（reference 空間，不縮）；高度隨縮放
## ×factor。`expedition_theme_fixed_minimum`（棋盤/bench 格等 sprite 佔位）
## 兩軸皆維持 reference 值——字級縮放對它們的視覺影響由 ellipsis 截斷吸收。
func _apply_control_metrics(
	host: Control,
	factor: float,
	base_metrics: Dictionary
) -> void:
	for control: Control in _metric_controls(host):
		var base_size: Vector2 = control.get_meta(
			&"expedition_theme_base_minimum",
			base_metrics.get(control.get_instance_id(), Vector2.ZERO)
		)
		var runtime_size := (
			base_size
			if bool(control.get_meta(&"expedition_theme_fixed_minimum", false))
			else Vector2(base_size.x, ceilf(base_size.y * factor))
		)
		ExpeditionLayoutMetrics.set_runtime_min(control, runtime_size)
