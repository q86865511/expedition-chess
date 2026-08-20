class_name ResultsScreenComposition
extends Control

const COMPOSE_INVALID: StringName = &"RESULTS_COMPOSE_INVALID"
const AUTHORITATIVE_PAIR_INVALID: StringName = \
	&"RESULTS_AUTHORITATIVE_PAIR_INVALID"

var _snapshot: ResultsPresentationSnapshot
var _localized_text: Dictionary[StringName, String] = {}

const VALUE_NAMES: Array[StringName] = [
	&"OutcomeValue",
	&"RewardValue",
	&"ProfileValue",
	&"ReceiptValue",
	&"DigestValue",
]
const METRIC_LABEL_KEYS: Dictionary[StringName, StringName] = {
	&"RewardValue": &"results.metric.currency_delta",
	&"ProfileValue": &"results.metric.profile_currency",
}


func compose(
	snapshot: ResultsPresentationSnapshot,
	localized_text: Dictionary = {}
) -> StringName:
	if snapshot == null:
		return COMPOSE_INVALID
	var owned_snapshot := snapshot.deep_clone()
	if not owned_snapshot.has_authoritative_pair():
		return AUTHORITATIVE_PAIR_INVALID
	_snapshot = owned_snapshot
	_set_localized_text(localized_text)
	_configure_visuals()
	_set_value(^"ReceiptValue", String(_snapshot.receipt_id), &"receipt")
	_set_value(
		^"OutcomeValue",
		_outcome_text(_snapshot.receipt.outcome),
		&"outcome"
	)
	_set_value(
		^"RewardValue",
		str(_snapshot.receipt.currency_delta),
		&"reward"
	)
	_set_value(
		^"ProfileValue",
		str(_snapshot.profile.meta_currency),
		&"profile_currency"
	)
	_set_value(
		^"DigestValue",
		_snapshot.committed_file_digest,
		&"committed_digest"
	)
	refresh_layout_rects()
	return &""


func snapshot_clone() -> ResultsPresentationSnapshot:
	return _snapshot.deep_clone() if _snapshot != null else null


func refresh_layout_rects() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var gap := ExpeditionLayoutMetrics.RESULTS_CARD_GAP
	var hero := Rect2(
		Vector2.ZERO,
		Vector2(size.x, ExpeditionLayoutMetrics.RESULTS_OUTCOME_CARD_HEIGHT)
	)
	var primary_top := hero.end.y + gap
	var primary_width := (size.x - gap) * 0.5
	var reward := Rect2(
		0.0,
		primary_top,
		primary_width,
		ExpeditionLayoutMetrics.RESULTS_PRIMARY_CARD_HEIGHT
	)
	var profile := Rect2(
		primary_width + gap,
		primary_top,
		primary_width,
		ExpeditionLayoutMetrics.RESULTS_PRIMARY_CARD_HEIGHT
	)
	var audit_top := reward.end.y + gap
	var audit_height := minf(
		ExpeditionLayoutMetrics.RESULTS_AUDIT_CARD_HEIGHT,
		maxf(0.0, size.y - audit_top)
	)
	var receipt := Rect2(0.0, audit_top, primary_width, audit_height)
	var digest := Rect2(
		primary_width + gap,
		audit_top,
		primary_width,
		audit_height
	)
	_place_card(&"OutcomeValue", hero)
	_place_card(&"RewardValue", reward)
	_place_card(&"ProfileValue", profile)
	_place_card(&"ReceiptValue", receipt)
	_place_card(&"DigestValue", digest)


func _configure_visuals() -> void:
	for value_name: StringName in VALUE_NAMES:
		var label := get_node_or_null(NodePath(String(value_name))) as Label
		if label == null:
			continue
		# Metrics below own the rect.  Scaled font minimums must grow toward the
		# authored card interior; bidirectional growth can pull a right-column
		# label back toward the left column at the 125% threshold.
		label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		label.grow_horizontal = Control.GROW_DIRECTION_END
		label.grow_vertical = Control.GROW_DIRECTION_END
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = (
			TextServer.AUTOWRAP_ARBITRARY
			if value_name in [&"ReceiptValue", &"DigestValue"]
			else TextServer.AUTOWRAP_WORD_SMART
		)
		label.theme_type_variation = (
			&"ExpeditionResultsOutcome"
			if value_name == &"OutcomeValue"
			else &"ExpeditionResultsAudit"
			if value_name in [&"ReceiptValue", &"DigestValue"]
			else &"ExpeditionResultsMetric"
		)
		_configure_metric_label(value_name)
		var panel_name := "%sCard" % String(value_name).trim_suffix("Value")
		if get_node_or_null(NodePath(panel_name)) != null:
			continue
		var panel := PanelContainer.new()
		panel.name = panel_name
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.grow_horizontal = Control.GROW_DIRECTION_END
		panel.grow_vertical = Control.GROW_DIRECTION_END
		panel.theme_type_variation = (
			&"ExpeditionResultsOutcomeCard"
			if value_name == &"OutcomeValue"
			else &"ExpeditionResultsAuditCard"
			if value_name in [&"ReceiptValue", &"DigestValue"]
			else &"ExpeditionResultsMetricCard"
		)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		move_child(panel, 0)


func _configure_metric_label(value_name: StringName) -> void:
	if not METRIC_LABEL_KEYS.has(value_name):
		return
	var metric_name := "%sLabel" % String(value_name).trim_suffix("Value")
	var metric_label := get_node_or_null(NodePath(metric_name)) as Label
	if metric_label == null:
		metric_label = Label.new()
		metric_label.name = metric_name
		metric_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		metric_label.grow_horizontal = Control.GROW_DIRECTION_END
		metric_label.grow_vertical = Control.GROW_DIRECTION_END
		metric_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		metric_label.theme_type_variation = &"ExpeditionResultsMetricLabel"
		add_child(metric_label)
	var localization_key: StringName = METRIC_LABEL_KEYS[value_name]
	metric_label.text = _text(localization_key)
	metric_label.set_meta(&"localization_key", localization_key)
	metric_label.set_meta(&"accessible_text", metric_label.text)


func _place_card(value_name: StringName, rect: Rect2) -> void:
	var panel_name := "%sCard" % String(value_name).trim_suffix("Value")
	var panel := get_node_or_null(NodePath(panel_name)) as PanelContainer
	var label := get_node_or_null(NodePath(String(value_name))) as Label
	if panel == null or label == null:
		return
	panel.position = rect.position
	panel.size = rect.size
	var inset := ExpeditionLayoutMetrics.RESULTS_CARD_INSET
	if value_name in [&"ReceiptValue", &"DigestValue"]:
		# Audit strings remain readable at 150% without restoring their old visual
		# weight; the smaller vertical inset gives wrapping text the card interior.
		inset.y = 12.0
	var inner_width := maxf(0.0, rect.size.x - inset.x * 2.0)
	var metric_name := "%sLabel" % String(value_name).trim_suffix("Value")
	var metric_label := get_node_or_null(NodePath(metric_name)) as Label
	if metric_label != null:
		metric_label.position = rect.position + inset
		metric_label.size = Vector2(
			inner_width,
			ExpeditionLayoutMetrics.RESULTS_METRIC_LABEL_HEIGHT
		)
		var value_top := (
			metric_label.position.y
			+ ExpeditionLayoutMetrics.RESULTS_METRIC_LABEL_HEIGHT
			+ ExpeditionLayoutMetrics.RESULTS_METRIC_LABEL_GAP
		)
		label.position = Vector2(rect.position.x + inset.x, value_top)
		label.size = Vector2(
			inner_width,
			maxf(0.0, rect.end.y - inset.y - value_top)
		)
		return
	label.position = rect.position + inset
	label.size = Vector2(
		inner_width,
		maxf(0.0, rect.size.y - inset.y * 2.0)
	)


func _set_value(path: NodePath, value: String, kind: StringName) -> void:
	var label := get_node_or_null(path) as Label
	if label == null:
		return
	label.text = value
	label.set_meta(&"typed_data_kind", kind)
	var value_name := StringName(String(path))
	if METRIC_LABEL_KEYS.has(value_name):
		label.set_meta(
			&"accessible_text",
			"%s：%s" % [_text(METRIC_LABEL_KEYS[value_name]), value]
		)
	else:
		label.set_meta(&"accessible_text", value)


func _outcome_text(outcome: SettlementReceiptState.Outcome) -> String:
	var token: StringName
	match outcome:
		SettlementReceiptState.Outcome.COMPLETED:
			token = &"completed"
		SettlementReceiptState.Outcome.FAILED:
			token = &"failed"
		SettlementReceiptState.Outcome.ABANDONED:
			token = &"abandoned"
		_:
			token = &"unknown"
	return _text(StringName("results.outcome.%s" % String(token)))


func _set_localized_text(values: Dictionary) -> void:
	_localized_text.clear()
	for key: Variant in values.keys():
		_localized_text[StringName(key)] = String(values[key])


func _text(key: StringName) -> String:
	return _localized_text.get(key, String(key))
