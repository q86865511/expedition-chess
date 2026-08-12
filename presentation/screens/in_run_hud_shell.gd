class_name InRunHudShell
extends Control

## 四個局內 route 共用的 presentation-only HUD 骨架。所有資料在 bind 時 clone-in；
## 本節點不持 RunController、catalog 或其他 domain 可變引用，也不在 _process 輪詢。

const REGION_NAMES: Array[StringName] = [
	ProductionLayoutShell.REGION_TOP,
	ProductionLayoutShell.REGION_LEFT,
	ProductionLayoutShell.REGION_CENTER,
	ProductionLayoutShell.REGION_RIGHT,
	ProductionLayoutShell.REGION_BOTTOM,
	ProductionLayoutShell.REGION_OVERLAY,
]
const PROGRESS_STATE_COMPLETED: StringName = &"completed"
const PROGRESS_STATE_CURRENT: StringName = &"current"
const PROGRESS_STATE_UNREACHED: StringName = &"unreached"
const PROGRESS_STATE_SIGNALS := {
	PROGRESS_STATE_COMPLETED: "✓",
	PROGRESS_STATE_CURRENT: "▶",
	PROGRESS_STATE_UNREACHED: "○",
}
const NODE_KIND_SIGNALS := {
	&"normal": "●",
	&"elite": "▲",
	&"merchant": "■",
	&"event": "?",
	&"rest": "⌂",
	&"treasure": "◇",
	&"boss": "★",
}

var _snapshot: RunPresentationSnapshot
var _route_kind: StringName = &""
var _ui_text: Callable
var _content_text: Callable
var _region_rect_provider: Callable
var _hosts: Dictionary = {}
var _unit_visuals := ProductionUnitVisualCatalog.new()
var _unit_inspector: VBoxContainer


func _ready() -> void:
	_arm_transition_banner_hide_timer()


func bind(
	snapshot: RunPresentationSnapshot,
	route_kind: StringName,
	region_rect_provider: Callable,
	ui_text: Callable,
	content_text: Callable
) -> StringName:
	if snapshot == null or not region_rect_provider.is_valid():
		return &"IN_RUN_HUD_BIND_INVALID"
	_snapshot = snapshot.deep_clone()
	_route_kind = route_kind
	_ui_text = ui_text
	_content_text = content_text
	_region_rect_provider = region_rect_provider
	_build_hosts()
	_render_top_hud()
	_render_left_hud()
	_render_transition_banner()
	show_inspector_empty()
	refresh_layout_rects()
	return &""


func host(region: StringName) -> Control:
	return _hosts.get(region) as Control


## The shell owns the inspector's identity even when a route mounts it into a
## sibling scroll container. Keeping this operation typed prevents route code
## from rediscovering the panel through a fragile scene-tree search.
func mount_unit_inspector(target: VBoxContainer) -> bool:
	if target == null:
		return false
	var panel := _inspector_panel()
	if panel == null:
		return false
	var current_parent := panel.get_parent()
	if current_parent != target:
		if current_parent != null:
			current_parent.remove_child(panel)
		target.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return true


func snapshot_clone() -> RunPresentationSnapshot:
	return _snapshot.deep_clone() if _snapshot != null else null


## Layout changes are event-driven by ProductionScreen after shell scale/status
## settles. Hosts keep their children and focus/scroll state; only reference rects
## and absolute top-HUD geometry are updated.
func refresh_layout_rects() -> void:
	if not _region_rect_provider.is_valid():
		return
	for region: StringName in REGION_NAMES:
		var region_host := host(region)
		if region_host == null:
			continue
		var value: Variant = _region_rect_provider.call(region)
		if not value is Rect2:
			continue
		var rect: Rect2 = value
		region_host.position = rect.position
		region_host.size = rect.size
		region_host.clip_contents = (
			region != ProductionLayoutShell.REGION_OVERLAY
		)
	_layout_top_hud()
	var left := host(ProductionLayoutShell.REGION_LEFT)
	var left_stack := find_child("InRunLeftStack", true, false) as Control
	if left != null and left_stack != null:
		ExpeditionLayoutMetrics.set_reference_min(
			left_stack, Vector2(left.size.x, 0.0)
		)


func show_prepare_unit(unit_instance_id: String) -> void:
	var panel := _inspector_panel()
	if panel == null:
		return
	_clear_children(panel)
	var inspection := _find_prepare_inspection(unit_instance_id)
	if inspection == null:
		show_inspector_empty()
		return
	panel.set_meta(&"unit_instance_id", inspection.unit_instance_id)
	panel.add_child(_heading(&"prepare.panel.units"))
	panel.add_child(_prepare_portrait(inspection))
	var unit_name := _value_label(_content(inspection.unit_def_id))
	unit_name.name = "PrepareUnitName"
	panel.add_child(unit_name)
	var star := _metric(&"combat.stat.star", str(inspection.star))
	star.name = "PrepareUnitStar"
	panel.add_child(star)
	var cost_tier := _metric(&"tooltip.cost", str(inspection.cost_tier))
	cost_tier.name = "PrepareUnitCostTier"
	panel.add_child(cost_tier)
	panel.add_child(_heading(&"prepare.panel.synergies"))
	if inspection.trait_ids.is_empty():
		panel.add_child(_value_label(_text(&"combat.inspection.none")))
	else:
		for trait_id: StringName in inspection.trait_ids:
			var trait_label := _value_label(_content(trait_id))
			trait_label.name = "PrepareTrait_%s" % String(trait_id).replace(".", "_")
			trait_label.set_meta(&"trait_id", trait_id)
			panel.add_child(trait_label)
	panel.add_child(_heading(&"prepare.panel.party"))
	var ability := _value_label(
		_content(inspection.ability_id)
		if not inspection.ability_id.is_empty()
		else _text(&"combat.inspection.none")
	)
	ability.name = "PrepareUnitAbility"
	ability.set_meta(&"ability_id", inspection.ability_id)
	panel.add_child(ability)
	var role_trait_id := _prepare_role_trait_id(inspection)
	var role := _value_label(
		_content(role_trait_id)
		if not role_trait_id.is_empty()
		else _text(&"combat.inspection.none")
	)
	role.name = "PrepareUnitRole"
	role.set_meta(&"ai_profile", inspection.ai_profile)
	role.set_meta(&"role_trait_id", role_trait_id)
	panel.add_child(role)
	panel.add_child(_heading(&"prepare.group.forge_equipment"))
	for slot_index: int in range(3):
		var item_name := _text(&"combat.inspection.none")
		if slot_index < inspection.equipment_instance_ids.size():
			item_name = _item_name(inspection.equipment_instance_ids[slot_index])
		var slot := _value_label(item_name)
		slot.name = "PrepareEquipmentSlot%d" % slot_index
		slot.set_meta(&"slot_index", slot_index)
		panel.add_child(slot)
	panel.add_child(_heading(&"combat.inspect"))
	if inspection.stats == null:
		var unavailable := _value_label(_text(&"combat.inspection.none"))
		unavailable.name = "StatsUnavailable"
		panel.add_child(unavailable)
		return
	for row: Array in [
		[&"combat.stat.health", inspection.stats.health],
		[&"combat.stat.attack", inspection.stats.attack],
		[&"combat.stat.armor", inspection.stats.armor],
		[&"combat.stat.magic_resist", inspection.stats.magic_resist],
		[&"combat.stat.attack_speed_milli", inspection.stats.attack_speed_milli],
		[&"combat.stat.attack_range_cells", inspection.stats.attack_range_cells],
		[&"combat.stat.start_mana", inspection.stats.start_mana],
		[&"combat.stat.max_mana", inspection.stats.max_mana],
		[&"combat.stat.move_speed_milli", inspection.stats.move_speed_milli],
	]:
		var stat := _metric(row[0] as StringName, str(row[1]))
		stat.name = "PrepareStat_%s" % String(row[0]).replace(".", "_")
		panel.add_child(stat)


func show_combat_unit(inspection: CombatUnitInspectionSnapshot) -> void:
	var panel := _inspector_panel()
	if panel == null:
		return
	_clear_children(panel)
	if inspection == null:
		show_inspector_empty()
		return
	panel.add_child(_heading(&"prepare.panel.units"))
	panel.add_child(_value_label(_content(inspection.source_id)))
	for stat_key: String in RunCombatScreen.INSPECTION_STAT_ORDER:
		if inspection.stats.has(stat_key):
			panel.add_child(_metric(
				StringName(RunCombatScreen.STAT_TEXT_KEY_PREFIX + stat_key),
				str(inspection.stats[stat_key])
			))


func show_inspector_empty() -> void:
	var panel := _inspector_panel()
	if panel == null:
		return
	_clear_children(panel)
	panel.remove_meta(&"unit_instance_id")
	panel.add_child(_heading(&"prepare.panel.units"))
	var empty := _value_label(_text(&"combat.inspection.none"))
	empty.name = "InspectorEmptyState"
	panel.add_child(empty)


func _build_hosts() -> void:
	if (
		is_instance_valid(_unit_inspector)
		and is_ancestor_of(_unit_inspector)
	):
		# _clear_children() synchronously frees descendants. Clear the cached
		# identity first so a subsequent bind cannot observe a freed instance.
		_unit_inspector = null
	_clear_children(self)
	_hosts.clear()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for region: StringName in REGION_NAMES:
		var region_host := Control.new()
		region_host.name = "Hud%sHost" % String(region).to_pascal_case()
		var rect: Rect2 = _region_rect_provider.call(region)
		region_host.position = rect.position
		region_host.size = rect.size
		region_host.clip_contents = (
			region != ProductionLayoutShell.REGION_OVERLAY
		)
		region_host.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE
			if region == ProductionLayoutShell.REGION_OVERLAY
			else Control.MOUSE_FILTER_PASS
		)
		region_host.set_meta(&"hud_region", region)
		add_child(region_host)
		if region == ProductionLayoutShell.REGION_OVERLAY:
			region_host.add_to_group(
				ProductionWorldSurface.OVERLAY_MOUNT_GROUP,
				true
			)
		_hosts[region] = region_host


func _render_top_hud() -> void:
	var top := host(ProductionLayoutShell.REGION_TOP)
	if top == null:
		return
	var row := VBoxContainer.new()
	row.name = "InRunProgressBar"
	row.clip_contents = true
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	var metrics := GridContainer.new()
	metrics.name = "InRunResourceMetrics"
	metrics.columns = 4
	metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(metrics)
	var hp := _metric(
		&"prepare.resource.hp",
		(
			str(_snapshot.view.expedition_hp)
			if _snapshot.view != null
			else _text(&"combat.inspection.none")
		)
	)
	hp.name = "ExpeditionHpValue"
	hp.theme_type_variation = &"ExpeditionSection"
	hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(hp)
	if _snapshot.economy != null:
		var gold := _metric(
			&"prepare.resource.gold", str(_snapshot.economy.gold)
		)
		gold.name = "GoldValue"
		gold.theme_type_variation = &"ExpeditionSection"
		gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		metrics.add_child(gold)
		var level_xp := _metric(
			&"prepare.resource.level_xp",
			"%s / %s" % [_snapshot.economy.level, _snapshot.economy.xp]
		)
		level_xp.name = "LevelXpValue"
		level_xp.theme_type_variation = &"ExpeditionSection"
		level_xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		metrics.add_child(level_xp)
	if _route_kind == &"RUN_PREPARE" and _snapshot.board_validation_report != null:
		var deployed := 0
		if _snapshot.roster != null and _snapshot.roster.board != null:
			deployed = _snapshot.roster.board.placements.size()
		var population := _metric(
			&"prepare.resource.capacity",
			"%d / %d" % [
				deployed,
				_snapshot.board_validation_report.derived_capacity,
			]
		)
		population.name = "PopulationValue"
		population.theme_type_variation = &"ExpeditionSection"
		population.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		metrics.add_child(population)
	var progress_row := HBoxContainer.new()
	progress_row.name = "RunProgressRow"
	progress_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(progress_row)
	var progress := Label.new()
	progress.name = "RunProgressTracker"
	progress.theme_type_variation = &"ExpeditionSection"
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.size_flags_vertical = Control.SIZE_EXPAND_FILL
	progress.clip_text = true
	progress.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progress.text = _progress_text()
	progress.set_meta(&"accessible_text", progress.text)
	progress_row.add_child(progress)
	var sequence := _progress_sequence_label()
	sequence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_row.add_child(sequence)
	_layout_top_hud()


func _layout_top_hud() -> void:
	var top := host(ProductionLayoutShell.REGION_TOP)
	var row := find_child("InRunProgressBar", true, false) as Control
	if top == null or row == null:
		return
	# ProductionScreen title occupies TITLE_COLUMN_WIDTH; SystemMenuButton owns
	# the rightmost 270px plus a 12px gap. Two explicit rows prevent the progress
	# text from competing with resource metrics at 150% UI scale.
	row.position = Vector2(ProductionLayoutShell.TITLE_COLUMN_WIDTH, 0.0)
	row.size = Vector2(
		maxf(
			0.0,
			top.size.x
			- ProductionLayoutShell.TITLE_COLUMN_WIDTH
			- 282.0
		),
		top.size.y
	)


func _render_left_hud() -> void:
	var left := host(ProductionLayoutShell.REGION_LEFT)
	if left == null:
		return
	var scroll := ScrollContainer.new()
	scroll.name = "InRunLeftScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	left.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.name = "InRunLeftStack"
	ExpeditionLayoutMetrics.set_reference_min(stack, Vector2(left.size.x, 0.0))
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	stack.add_child(_heading(&"prepare.panel.synergies"))
	var traits := ItemList.new()
	traits.name = "TraitList"
	ExpeditionLayoutMetrics.set_min(traits, 0.0, 150.0)
	traits.focus_mode = Control.FOCUS_ALL
	traits.set_meta(&"typed_data_kind", &"trait_preview")
	if _snapshot.active_trait_progress.is_empty():
		traits.add_item(_text(&"prepare.empty.synergies"))
		traits.set_item_disabled(0, true)
	else:
		for progress: TraitProgressPresentationSnapshot in \
			_snapshot.active_trait_progress:
			if progress == null:
				continue
			# member_instance_ids are not the domain's distinct-definition count.
			# Do not present them as threshold progress; show only the active trait
			# and the pinned authored threshold ladder below.
			traits.add_item("▶ %s" % _content(progress.trait_id))
			traits.set_item_metadata(
				traits.item_count - 1, progress.trait_id
			)
			var tooltip_lines: Array[String] = []
			for threshold: TraitThresholdPresentationSnapshot in \
				progress.thresholds:
				if threshold == null:
					continue
				var threshold_line := "%s %s %d" % [
					"▶" if threshold.tier == progress.current_tier else "○",
					_text(&"prepare.panel.units"),
					threshold.required_count,
				]
				var effects: Array[String] = []
				for effect_id: StringName in threshold.effect_ids:
					if not effect_id.is_empty():
						effects.append(_content(effect_id))
				if not effects.is_empty():
					threshold_line += " · %s" % ", ".join(effects)
				tooltip_lines.append(threshold_line)
			traits.set_item_tooltip(
				traits.item_count - 1, "\n".join(tooltip_lines)
			)
	stack.add_child(traits)
	stack.add_child(_heading(&"prepare.panel.inventory"))
	var inventory := ItemList.new()
	inventory.name = "HudInventory"
	ExpeditionLayoutMetrics.set_min(inventory, 0.0, 168.0)
	inventory.focus_mode = Control.FOCUS_ALL
	inventory.set_meta(&"typed_data_kind", &"item_instance")
	_render_inventory(inventory)
	stack.add_child(inventory)
	var relics := ItemList.new()
	relics.name = "HudRelicSlots"
	ExpeditionLayoutMetrics.set_min(relics, 0.0, 126.0)
	relics.focus_mode = Control.FOCUS_ALL
	relics.set_meta(&"typed_data_kind", &"relic_slot")
	_render_relics(relics)
	stack.add_child(relics)


func _render_economy_hud() -> void:
	# Bottom region is owned by route actions/confirm controls. Economy values
	# live in the common top row so they never paint through those controls.
	return


func _render_transition_banner() -> void:
	if (
		_snapshot == null
		or not (
			_snapshot.progress_act_transitioned
			or _snapshot.progress_node_transitioned
		)
	):
		return
	var overlay := host(ProductionLayoutShell.REGION_OVERLAY)
	if overlay == null:
		return
	var banner := Label.new()
	banner.name = "RunTransitionBanner"
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 0.5
	banner.anchor_bottom = 0.5
	banner.offset_left = -450.0
	banner.offset_right = 450.0
	banner.offset_top = -72.0
	banner.offset_bottom = 72.0
	ExpeditionLayoutMetrics.set_fixed_min(banner, 900.0, 144.0)
	banner.theme_type_variation = &"ExpeditionSection"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.z_index = 50
	banner.text = _transition_text()
	banner.set_meta(&"accessible_text", banner.text)
	overlay.add_child(banner)
	_arm_transition_banner_hide_timer()


func _arm_transition_banner_hide_timer() -> void:
	if not is_inside_tree():
		return
	var banner := find_child("RunTransitionBanner", true, false) as Label
	if banner == null or bool(banner.get_meta(&"hide_timer_armed", false)):
		return
	banner.set_meta(&"hide_timer_armed", true)
	get_tree().create_timer(0.75).timeout.connect(
		_hide_transition_banner.bind(banner), CONNECT_ONE_SHOT
	)


func _hide_transition_banner(banner: Label) -> void:
	if banner != null and is_instance_valid(banner):
		banner.visible = false


func _render_inventory(list: ItemList) -> void:
	if _snapshot.roster == null:
		list.add_item(_text(&"combat.inspection.none"))
		list.set_item_disabled(0, true)
		return
	for item_id: String in _snapshot.roster.inventory_item_instance_ids:
		list.add_item(_item_name(item_id))
		list.set_item_metadata(list.item_count - 1, item_id)
	for overflow_id: String in _snapshot.roster.pending_item_overflow:
		list.add_item("! %s" % _item_name(overflow_id))
		list.set_item_metadata(list.item_count - 1, overflow_id)
		list.set_item_tooltip(
			list.item_count - 1, _text(&"prepare.panel.overflow")
		)
	if list.item_count == 0:
		list.add_item(_text(&"combat.inspection.none"))
		list.set_item_disabled(0, true)


func _render_relics(list: ItemList) -> void:
	if _snapshot.roster == null or _snapshot.roster.active_relic_slots.is_empty():
		list.add_item(_text(&"combat.inspection.none"))
		list.set_item_disabled(0, true)
		return
	for slot: RelicSlotState in _snapshot.roster.active_relic_slots:
		var value := _text(&"combat.inspection.none")
		if slot.relic_id != null:
			value = _content(slot.relic_id.value)
		list.add_item("%d  %s" % [slot.slot_index + 1, value])
		list.set_item_metadata(list.item_count - 1, slot.slot_index)


func _inspector_panel() -> VBoxContainer:
	if is_instance_valid(_unit_inspector):
		return _unit_inspector
	var right := host(ProductionLayoutShell.REGION_RIGHT)
	if right == null:
		return null
	var panel := right.get_node_or_null(^"UnitInspector") as VBoxContainer
	if panel != null:
		_unit_inspector = panel
		return panel
	panel = VBoxContainer.new()
	panel.name = "UnitInspector"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.set_meta(&"typed_data_kind", &"unit_inspector")
	right.add_child(panel)
	_unit_inspector = panel
	return panel


func _find_prepare_inspection(
	unit_instance_id: String
) -> PrepareUnitInspectionSnapshot:
	if _snapshot == null:
		return null
	for inspection: PrepareUnitInspectionSnapshot in \
		_snapshot.prepare_unit_inspections:
		if (
			inspection != null
			and String(inspection.unit_instance_id) == unit_instance_id
		):
			return inspection.deep_clone()
	return null


func _prepare_portrait(
	inspection: PrepareUnitInspectionSnapshot
) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.name = "PreparePortraitBlock"
	var portrait := TextureRect.new()
	portrait.name = "PrepareUnitPortrait"
	ExpeditionLayoutMetrics.set_fixed_min(portrait, 180.0, 180.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.texture = _unit_visuals.try_portrait(inspection.unit_def_id)
	portrait.set_meta(&"unit_def_id", inspection.unit_def_id)
	result.add_child(portrait)
	if portrait.texture == null:
		var unavailable := _value_label(_text(&"combat.inspection.none"))
		unavailable.name = "PortraitUnavailable"
		result.add_child(unavailable)
	return result


func _prepare_role_trait_id(
	inspection: PrepareUnitInspectionSnapshot
) -> StringName:
	for trait_id: StringName in inspection.trait_ids:
		var value := String(trait_id)
		if value.begins_with("trait.role_") or value.begins_with("trait.role."):
			return trait_id
	return &""


func _item_name(instance_id: String) -> String:
	if _snapshot != null and _snapshot.roster != null:
		for item: ItemInstanceState in _snapshot.roster.item_instances:
			if item != null and item.instance_id == instance_id:
				return _content(item.def_id)
	return _text(&"combat.inspection.none")


func _progress_text() -> String:
	var node := _current_progress_node()
	if _snapshot == null or _snapshot.view == null or node == null:
		return "%s · %s" % [
			_text(&"prepare.panel.expedition"),
			_text(&"combat.inspection.none"),
		]
	return "%s · %d / %d · %s" % [
		_text(&"prepare.panel.expedition"),
		_snapshot.view.act_index + 1,
		node.layer_index + 1,
		_content(node.def_id),
	]


func _progress_sequence_label() -> Label:
	var label := Label.new()
	label.name = "RunNodeSequence"
	label.theme_type_variation = &"ExpeditionAuxiliary"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var state_names: Array[StringName] = []
	var node_kinds: Array[StringName] = []
	var state_signals: Array[String] = []
	var kind_signals: Array[String] = []
	var visible_tokens: Array[String] = []
	var accessible_tokens: Array[String] = []
	if _snapshot != null:
		var current_node_id := _snapshot.progress_current_node_id()
		for node: MapNodePresentation in _snapshot.progress_nodes():
			var state := _progress_state(node, current_node_id)
			var state_signal := String(PROGRESS_STATE_SIGNALS[state])
			var kind_signal := String(NODE_KIND_SIGNALS.get(node.kind, "?"))
			state_names.append(state)
			node_kinds.append(node.kind)
			state_signals.append(state_signal)
			kind_signals.append(kind_signal)
			visible_tokens.append("%s%s" % [state_signal, kind_signal])
			accessible_tokens.append("%s%s %s %s" % [
				state_signal,
				kind_signal,
				_text(StringName("map.node_kind.%s" % String(node.kind))),
				_content(node.def_id),
			])
	label.text = (
		"  ".join(visible_tokens)
		if not visible_tokens.is_empty()
		else _text(&"combat.inspection.none")
	)
	label.tooltip_text = " · ".join(accessible_tokens)
	label.set_meta(
		&"accessible_text",
		label.tooltip_text if not label.tooltip_text.is_empty() else label.text
	)
	label.set_meta(&"progress_states", state_names)
	label.set_meta(&"node_kinds", node_kinds)
	label.set_meta(&"state_signals", state_signals)
	label.set_meta(&"kind_signals", kind_signals)
	return label


func _progress_state(
	node: MapNodePresentation,
	current_node_id: String
) -> StringName:
	if not current_node_id.is_empty() and node.node_id == current_node_id:
		return PROGRESS_STATE_CURRENT
	if node.completed:
		return PROGRESS_STATE_COMPLETED
	return PROGRESS_STATE_UNREACHED


func _current_progress_node() -> MapNodePresentation:
	if _snapshot == null:
		return null
	var current_node_id := _snapshot.progress_current_node_id()
	if current_node_id.is_empty():
		return null
	for node: MapNodePresentation in _snapshot.progress_nodes():
		if node.node_id == current_node_id:
			return node
	return null


func _transition_text() -> String:
	if _snapshot == null or _snapshot.view == null:
		return _text(&"combat.inspection.none")
	if _snapshot.progress_node_transitioned:
		return _progress_text()
	return "%s · %d" % [
		_text(&"prepare.panel.expedition"),
		_snapshot.view.act_index + 1,
	]


func _route_title_key() -> StringName:
	return {
		&"RUN_PREPARE": &"screen.run_prepare.title",
		&"RUN_COMBAT": &"screen.run_combat.title",
		&"RUN_MAP": &"screen.run_map.title",
		&"RUN_REWARD": &"screen.run_reward.title",
	}.get(_route_kind, &"screen.run_container.title") as StringName


func _heading(key: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ExpeditionSection"
	label.text = _text(key)
	return label


func _metric(key: StringName, value: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ExpeditionMetric"
	label.text = "%s  %s" % [_text(key), value]
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.set_meta(&"accessible_text", label.text)
	return label


func _value_label(value: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ExpeditionAuxiliary"
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_meta(&"accessible_text", value)
	return label


func _text(key: StringName) -> String:
	return String(_ui_text.call(key)) if _ui_text.is_valid() else String(key)


func _content(key: StringName) -> String:
	return String(_content_text.call(key)) if _content_text.is_valid() else String(key)


func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		# HUD 會在同一個 compose/refresh 週期內重建區域；節點一旦先從
		# tree 拆下，queue_free 直到 idle frame 才回收，會在 route 釋放與
		# GUT orphan scan 之間留下 detached UI graph。此處沒有訊號 callback
		# 需要延後，故同步釋放可讓生命週期與 shell 一起結束。
		child.free()
