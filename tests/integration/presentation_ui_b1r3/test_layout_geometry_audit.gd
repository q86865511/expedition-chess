extends GutTest

## B1R3 A4：自動幾何稽核。取代「以截圖宣稱版面正確」——同容器同類控制項同高、
## 按鈕文字不得寬於按鈕、互動控制項落在安全區、分組頁初始即有高度（P1）、
## 設定動作列底緣不出安全區（P3）。三種 UI 縮放皆須成立（REQ-UX-003）。

const FunctionalSupport = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)

const SAFE_RECT := Rect2(36.0, 36.0, 1848.0, 1008.0)
const SCALES: Array[int] = [100, 125, 150]
const INTERACTIVE_CLASSES: Array[String] = [
	"Button", "OptionButton", "SpinBox", "HSlider", "LineEdit", "ItemList",
]


func test_menu_camp_settings_geometry_across_scales() -> void:
	for percent: int in SCALES:
		var harness: Variant = await _boot_sized()
		var menu := FunctionalSupport.active_screen(harness)
		assert_not_null(menu)
		if menu == null:
			return
		assert_true(FunctionalSupport.press(self, menu, &"menu.start"))
		var camp := FunctionalSupport.active_screen(harness)
		assert_true(FunctionalSupport.press(self, camp, &"camp.settings"))
		var settings := FunctionalSupport.active_screen(harness)
		await _apply_scale_via_settings(settings, percent)
		_audit_screen(settings, percent)
		_audit_settings_actions_bottom(settings, percent)

		assert_true(FunctionalSupport.press(self, settings, &"settings.back"))
		var camp_scaled := FunctionalSupport.active_screen(harness)
		await wait_process_frames(2)
		_audit_screen(camp_scaled, percent)

		assert_true(FunctionalSupport.press(self, camp_scaled, &"camp.menu"))
		var menu_scaled := FunctionalSupport.active_screen(harness)
		await wait_process_frames(2)
		_audit_screen(menu_scaled, percent)


func test_run_prepare_geometry_across_scales() -> void:
	for percent: int in SCALES:
		var harness: Variant = await _boot_sized()
		var menu := FunctionalSupport.active_screen(harness)
		assert_not_null(menu)
		if menu == null:
			return
		assert_true(FunctionalSupport.press(self, menu, &"menu.start"))
		var pre_settings_camp := FunctionalSupport.active_screen(harness)
		assert_true(
			FunctionalSupport.press(self, pre_settings_camp, &"camp.settings")
		)
		var settings := FunctionalSupport.active_screen(harness)
		await _apply_scale_via_settings(settings, percent)
		assert_true(FunctionalSupport.press(self, settings, &"settings.back"))
		var camp := FunctionalSupport.active_screen(harness)
		await wait_process_frames(2)
		var commander := camp.find_child(
			"CommanderSelector", true, false
		) as OptionButton
		var challenge := camp.find_child(
			"ChallengeSelector", true, false
		) as SpinBox
		assert_not_null(commander)
		assert_not_null(challenge)
		if commander == null or challenge == null:
			return
		commander.item_selected.emit(0)
		challenge.value_changed.emit(0.0)
		assert_true(FunctionalSupport.press(self, camp, &"camp.start"))
		var map_screen := FunctionalSupport.active_screen(harness)
		assert_eq(map_screen.route_kind, &"RUN_MAP")
		assert_true(FunctionalSupport.press(self, map_screen, &"map.select"))
		await wait_process_frames(1)
		map_screen = FunctionalSupport.active_screen(harness)
		assert_true(FunctionalSupport.press(self, map_screen, &"map.confirm"))
		await wait_process_frames(1)
		var prepare := FunctionalSupport.active_screen(harness)
		assert_eq(
			prepare.route_kind,
			&"RUN_PREPARE",
			"map.select + map.confirm must reach RUN_PREPARE at ui%d" % percent
		)
		if prepare.route_kind != &"RUN_PREPARE":
			return
		await wait_process_frames(6)
		# autowrap 夾制回歸鎖（見 run_prepare_screen.refresh_layout_rects）：
		# 左欄必須收斂到縮放後的區域高度，不得停在暴漲的過渡 min。
		var left_probe := prepare.find_child(
			"PrepareLeftContent", true, false
		) as Control
		if percent == 150 and left_probe != null:
			var shell := prepare.get("_layout_shell") as ProductionLayoutShell
			assert_not_null(shell)
			if shell != null:
				assert_almost_eq(
					left_probe.size.y,
					shell.current_content_rect(
						ProductionLayoutShell.REGION_LEFT
					).size.y,
					2.0,
					"left content must settle at the scaled region height"
				)
		_audit_screen(prepare, percent)
		_audit_prepare_group_pages(prepare, percent)
		await _audit_prepare_action_scroll(prepare, percent)
		_audit_shop_cards_in_focus_ring(prepare, percent)
		if percent == 100:
			await _audit_modal_centering(prepare)


## --- 稽核規則 -------------------------------------------------------------


## host 在 lifecycle harness 中沒有尺寸，anchors 版面會塌到 0；
## 稽核前先給 1920×1080 reference 尺寸。
func _boot_sized() -> Variant:
	var harness: Variant = FunctionalSupport.boot(self)
	if harness != null and harness.host != null:
		harness.host.position = Vector2.ZERO
		harness.host.size = Vector2(1920.0, 1080.0)
	await wait_process_frames(1)
	return harness


## 縮放一律走真實設定套用管線（draft → settings.apply → consumer 套用），
## 而不是直接呼叫 theme runtime——app 的 settings consumer 會以它記住的
## 縮放值延遲重套，直接呼叫會被蓋回。
func _apply_scale_via_settings(
	settings: ProductionScreen,
	percent: int
) -> void:
	var composition: Node = FunctionalSupport.composition(settings)
	assert_not_null(composition)
	if composition == null:
		return
	var draft := composition.call(&"settings_draft") as SettingsSnapshot
	assert_not_null(draft)
	if draft == null:
		return
	draft.ui_scale_percent = percent
	assert_eq(
		StringName(composition.call(&"replace_settings_draft", draft)),
		&""
	)
	assert_true(FunctionalSupport.press(self, settings, &"settings.apply"))
	await wait_process_frames(3)


func _audit_screen(screen: ProductionScreen, percent: int) -> void:
	var context := "%s@ui%d" % [String(screen.route_kind), percent]
	_audit_sibling_heights(screen, context)
	_audit_band_uniform_heights(screen, context)
	_audit_button_text_fits(screen, context)
	_audit_safe_area(screen, context)


## (a2) 底部帶（Actions 子樹）內所有可見 Button/OptionButton 必須同高——
## 跨欄位（分組欄 vs 常駐欄 vs 商店動作欄）也要一致，補殺
## 「下拉與鄰欄按鈕不同高」這類跨 parent 症狀（B1R3 N6）。
func _audit_band_uniform_heights(
	screen: ProductionScreen,
	context: String
) -> void:
	if screen.route_kind != &"RUN_PREPARE":
		return
	var band := screen.find_child("Actions", true, false) as Control
	if band == null:
		return
	var reference_height := -1.0
	var reference_name := ""
	for node: Node in band.find_children("*", "Button", true, false):
		var control := node as Control
		if (
			control == null
			or not control.is_visible_in_tree()
			or control.has_meta(&"shop_offer_id")
			or control.theme_type_variation == &"ExpeditionShopCard"
		):
			continue
		var height := control.get_global_rect().size.y
		if reference_height < 0.0:
			reference_height = height
			reference_name = control.name
			continue
		assert_almost_eq(
			height,
			reference_height,
			1.0,
			"%s: band action %s (%.0f) differs from %s (%.0f)" % [
				context, control.name, height, reference_name, reference_height,
			]
		)


## (a) 同 parent 之下所有可見 Button（含 OptionButton）高度必須一致。
func _audit_sibling_heights(screen: ProductionScreen, context: String) -> void:
	var by_parent: Dictionary = {}
	for node: Node in screen.find_children("*", "Button", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var parent_id := control.get_parent().get_instance_id()
		if not by_parent.has(parent_id):
			by_parent[parent_id] = []
		(by_parent[parent_id] as Array).append(control)
	for parent_id: int in by_parent:
		var members: Array = by_parent[parent_id]
		if members.size() < 2:
			continue
		var reference := members[0] as Control
		for value: Variant in members:
			var member := value as Control
			assert_almost_eq(
				member.get_global_rect().size.y,
				reference.get_global_rect().size.y,
				1.0,
				"%s: sibling controls %s and %s must share one height" % [
					context, reference.name, member.name,
				]
			)


## (b) 按鈕文字（含 content margin）不得寬於按鈕本身。
## 豁免：帶 `expedition_allow_text_clip` meta 的控制項（棋盤/bench 格在
## Phase C sprite 落地前以省略號截斷是明示的設計決定，設 meta 者必須
## 同時設定 ellipsis overrun）。
func _audit_button_text_fits(screen: ProductionScreen, context: String) -> void:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button == null
			or not button.is_visible_in_tree()
			or button.text.is_empty()
			or button.has_meta(&"expedition_allow_text_clip")
			or button.autowrap_mode != TextServer.AUTOWRAP_OFF
		):
			# autowrap 按鈕以換行吸收長文字，寬度規則不適用；
			# 垂直溢出由安全區/區域規則把關。
			continue
		var font := button.get_theme_font(&"font")
		var font_size := button.get_theme_font_size(&"font_size")
		var text_width := font.get_multiline_string_size(
			button.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		).x
		var style := button.get_theme_stylebox(&"normal")
		var padding := (
			style.get_content_margin(SIDE_LEFT)
			+ style.get_content_margin(SIDE_RIGHT)
			if style != null
			else 0.0
		)
		assert_true(
			text_width + padding <= button.get_global_rect().size.x + 1.0,
			"%s: button %s clips its text (\"%s\" needs %.0fpx, has %.0fpx)" % [
				context,
				button.name,
				button.text,
				text_width + padding,
				button.get_global_rect().size.x,
			]
		)


## (c) 可見互動控制項必須落在安全區內。巢狀 follow_focus 容器允許 inner
## viewport 超出 outer 的裁切範圍；最外層必須完整落在安全區，持有焦點的
## control 則必須落在所有 scroll 與安全區的有效交集內。
func _audit_safe_area(screen: ProductionScreen, context: String) -> void:
	for class_hint: String in INTERACTIVE_CLASSES:
		for node: Node in screen.find_children("*", class_hint, true, false):
			var control := node as Control
			if control == null or not control.is_visible_in_tree():
				continue
			var scrolls := _focus_following_scroll_ancestors(control, screen)
			if not scrolls.is_empty():
				var effective_rect := SAFE_RECT.grow(1.0)
				for scroll: ScrollContainer in scrolls:
					var viewport_rect := scroll.get_global_rect()
					assert_true(
						viewport_rect.size.x > 0.0 and viewport_rect.size.y > 0.0,
						"%s: scroll viewport %s must have non-zero geometry" % [
							context, scroll.name,
						]
					)
					assert_true(
						scroll.follow_focus,
						"%s: scroll viewport %s must follow focus" % [
							context, scroll.name,
						]
					)
					effective_rect = effective_rect.intersection(viewport_rect)
				var outermost := scrolls[scrolls.size() - 1]
				assert_true(
					SAFE_RECT.grow(1.0).encloses(outermost.get_global_rect()),
					"%s: outer scroll %s must stay in the safe area" % [
						context, outermost.name,
					]
				)
				if control.has_focus():
					assert_true(
						effective_rect.size.x > 0.0
						and effective_rect.size.y > 0.0
						and effective_rect.grow(1.0).encloses(control.get_global_rect()),
						"%s: focused %s was not visible through every scroll" % [
							context, control.name,
						]
					)
				continue
			var rect := control.get_global_rect()
			# grow(1)：多層 ceil 換算允許 1px 容差。
			var parent_control := control.get_parent() as Control
			var sibling_dump := ""
			if parent_control != null and not SAFE_RECT.grow(1.0).encloses(rect):
				for sibling: Node in parent_control.get_children():
					var sib := sibling as Control
					if sib != null:
						sibling_dump += "%s min=%s flags=%d | " % [
							sib.name,
							sib.get_combined_minimum_size(),
							sib.size_flags_vertical,
						]
			assert_true(
				SAFE_RECT.grow(1.0).encloses(rect),
				"%s: %s (%s) escapes the safe area (%s; parent %s %s; sibs: %s)" % [
					context,
					control.name,
					class_hint,
					rect,
					parent_control.name if parent_control != null else "?",
					parent_control.get_global_rect() if parent_control != null else Rect2(),
					sibling_dump,
				]
			)


## (d) P1：分組頁一進畫面（不先切組）就必須有高度可容納其動作。
func _audit_prepare_group_pages(screen: ProductionScreen, percent: int) -> void:
	var pages := screen.find_child("PrepareActionGroupPages", true, false) as Control
	assert_not_null(
		pages,
		"RUN_PREPARE must expose action group pages (ui%d)" % percent
	)
	if pages == null:
		return
	assert_true(
		pages.get_combined_minimum_size().y > 0.0,
		"ui%d: group pages must reserve height before any manual group switch"
			% percent
	)
	var visible_actions := 0
	for node: Node in pages.find_children("*", "Button", true, false):
		var button := node as Control
		if button != null and button.is_visible_in_tree() \
			and button.get_global_rect().size.y > 0.0:
			visible_actions += 1
	assert_true(
		visible_actions > 0,
		"ui%d: the default action group must show usable buttons" % percent
	)


## 125% / 150% 時 action page 會高於 bottom band；逐組以真實 focus 路徑
## 把最後一顆 enabled action 捲入可見範圍，避免 follow_focus 成為全面豁免。
func _audit_prepare_action_scroll(
	screen: ProductionScreen,
	percent: int
) -> void:
	var selector := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton
	var scroll := screen.find_child(
		"PrepareActionGroupScroll", true, false
	) as ScrollContainer
	var outer_scroll := screen.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	assert_not_null(selector, "ui%d: prepare group selector is required" % percent)
	assert_not_null(scroll, "ui%d: prepare action scroll is required" % percent)
	assert_not_null(outer_scroll, "ui%d: outer bottom scroll is required" % percent)
	assert_not_null(shell, "ui%d: prepare layout shell is required" % percent)
	if selector == null or scroll == null or outer_scroll == null or shell == null:
		return
	assert_true(scroll.follow_focus, "ui%d: action scroll must follow focus" % percent)
	assert_true(outer_scroll.follow_focus, "ui%d: bottom scroll must follow focus" % percent)

	for group_index: int in selector.item_count:
		var focus_owner := screen.get_viewport().gui_get_focus_owner()
		if focus_owner != null:
			focus_owner.release_focus()
		await wait_process_frames(1)
		selector.select(group_index)
		selector.item_selected.emit(group_index)
		scroll.scroll_vertical = 0
		outer_scroll.scroll_vertical = 0
		await wait_process_frames(3)

		var viewport_rect := scroll.get_global_rect()
		var outer_viewport_rect := outer_scroll.get_global_rect()
		var bottom_control := screen.layout_content(
			ProductionLayoutShell.REGION_BOTTOM
		)
		assert_not_null(
			bottom_control,
			"ui%d group%d: bottom content control is required" % [
				percent, group_index,
			]
		)
		if bottom_control == null:
			continue
		var effective_viewport := (
			SAFE_RECT.grow(1.0)
			.intersection(viewport_rect)
			.intersection(outer_viewport_rect)
		)
		assert_true(
			viewport_rect.size.x > 0.0 and viewport_rect.size.y > 0.0,
			"ui%d group%d: action scroll viewport must be non-zero" % [
				percent, group_index,
			]
		)
		assert_true(
			SAFE_RECT.grow(1.0).encloses(outer_viewport_rect),
			"ui%d group%d: outer scroll %s must remain in safe area %s" % [
				percent, group_index, outer_viewport_rect, SAFE_RECT,
			]
		)

		var last_enabled := _last_enabled_button_in_scroll(scroll)
		if last_enabled == null:
			# Some canonical states intentionally disable an entire contextual
			# group (for example advance without a pending choice). There is no
			# legal focus target in that group, but the viewport checks still apply.
			continue
		var before_inner_scroll := scroll.scroll_vertical
		var before_outer_scroll := outer_scroll.scroll_vertical
		var was_outside := not effective_viewport.encloses(
			last_enabled.get_global_rect()
		)
		last_enabled.grab_focus()
		await wait_process_frames(5)
		var settled_viewport := scroll.get_global_rect()
		var settled_outer := outer_scroll.get_global_rect()
		var action_rect := last_enabled.get_global_rect()
		var settled_effective := (
			SAFE_RECT.grow(1.0)
			.intersection(settled_viewport)
			.intersection(settled_outer)
		)
		assert_true(
			last_enabled.has_focus(),
			"ui%d group%d: last enabled action must accept keyboard focus" % [
				percent, group_index,
			]
		)
		assert_true(
			action_rect.size.x <= settled_viewport.size.x + 1.0
			and action_rect.size.y <= settled_viewport.size.y + 1.0
			and action_rect.size.x <= settled_outer.size.x + 1.0
			and action_rect.size.y <= settled_outer.size.y + 1.0,
			"ui%d group%d: action %s must fit inner %s and outer %s" % [
				percent, group_index, action_rect, settled_viewport, settled_outer,
			]
		)
		assert_true(
			settled_viewport.grow(1.0).encloses(action_rect)
			and settled_outer.grow(1.0).encloses(settled_viewport)
			and settled_outer.grow(1.0).encloses(action_rect)
			and settled_effective.grow(1.0).encloses(action_rect),
			"ui%d group%d: %s action %s / inner %s / outer %s / effective %s" % [
				percent, group_index, last_enabled.name, action_rect,
				settled_viewport, settled_outer, settled_effective,
			]
		)
		if was_outside:
			assert_true(
				scroll.scroll_vertical > before_inner_scroll
				or outer_scroll.scroll_vertical > before_outer_scroll,
				"ui%d group%d: focus must advance a nested scroll position" % [
					percent, group_index,
				]
			)


func _last_enabled_button_in_scroll(scroll: ScrollContainer) -> Button:
	var result: Button = null
	for node: Node in scroll.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.is_visible_in_tree()
			and not button.disabled
			and button.focus_mode != Control.FOCUS_NONE
		):
			result = button
	return result


## (e) P3：設定畫面動作列底緣不得低於 reference 安全區底（1044）。
func _audit_settings_actions_bottom(
	screen: ProductionScreen,
	percent: int
) -> void:
	var actions := screen.get_node_or_null(^"Actions") as Control
	assert_not_null(actions, "SETTINGS must expose an Actions row (ui%d)" % percent)
	if actions == null:
		return
	var bottom := actions.get_global_rect().end.y
	assert_true(
		bottom <= SAFE_RECT.end.y + 1.0,
		"ui%d: settings actions bottom %.0f exceeds safe area %.0f" % [
			percent, bottom, SAFE_RECT.end.y,
		]
	)


## P2：商店卡必須在鍵盤焦點環內（Tab 可達、Enter 可購買）。
func _audit_shop_cards_in_focus_ring(
	screen: ProductionScreen,
	percent: int
) -> void:
	var cards: Array[Button] = []
	for node: Node in screen.find_children("ShopCard*", "Button", true, false):
		var card := node as Button
		if card != null and card.has_meta(&"shop_offer_id") \
			and card.is_visible_in_tree() and not card.disabled:
			cards.append(card)
	assert_true(
		cards.size() > 0,
		"ui%d: the live prepare screen must offer shop cards" % percent
	)
	var ring: Array = screen.call(&"_ordered_focus_controls")
	for card: Button in cards:
		assert_true(
			ring.has(card),
			"ui%d: shop card %s must be reachable by keyboard" % [
				percent, card.name,
			]
		)


## P10：確認 modal 必須置中於畫面（非左上角落在中心）。
func _audit_modal_centering(screen: ProductionScreen) -> void:
	if not FunctionalSupport.press(self, screen, &"run.menu"):
		return
	await wait_process_frames(1)
	var dialog := screen.find_child(
		"RunMenuConfirmation", true, false
	) as Control
	assert_not_null(dialog, "run.menu during a live run must open a modal")
	if dialog == null:
		return
	var center := dialog.get_global_rect().get_center()
	assert_almost_eq(center.x, 960.0, 4.0, "modal must center horizontally")
	assert_almost_eq(center.y, 540.0, 4.0, "modal must center vertically")
	# 取消鈕在 confirm 之後建立——取 dialog 內最後一顆按鈕關閉 modal。
	var cancel: Button = null
	for node: Node in dialog.find_children("*", "Button", true, false):
		var candidate_button := node as Button
		if candidate_button != null:
			cancel = candidate_button
	if cancel != null:
		cancel.pressed.emit()
		await wait_process_frames(1)


func _focus_following_scroll_ancestors(
	control: Control,
	stop_at: Node
) -> Array[ScrollContainer]:
	var result: Array[ScrollContainer] = []
	var ancestor := control.get_parent()
	while ancestor != null and ancestor != stop_at:
		var scroll := ancestor as ScrollContainer
		if scroll != null:
			result.append(scroll)
		ancestor = ancestor.get_parent()
	return result
