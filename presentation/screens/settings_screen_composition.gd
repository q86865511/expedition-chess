class_name SettingsScreenComposition
extends Control

const DRAFT_INVALID: StringName = &"SETTINGS_DRAFT_INVALID"
const DEFAULT_MESSAGE_KEY: StringName = &"error.settings.apply_failed"
const SETTING_ORDER: Array[StringName] = [
	&"locale",
	&"ui_scale_percent",
	&"color_vision_mode",
	&"reduced_motion",
	&"reduced_flash",
	&"reduced_particles",
	&"damage_number_density",
	&"master.volume",
	&"master.mute",
	&"music.volume",
	&"music.mute",
	&"sfx.volume",
	&"sfx.mute",
	&"ui.volume",
	&"ui.mute",
]

var _draft: SettingsSnapshot
var _committed: SettingsSnapshot
var _control_status_code: StringName = &""
## G2 H3：設定畫面自己的錯誤呈現面。draft 驗證失敗不會經過 action port，
## 只靠 ProductionScreen 層的狀態列看不到，必須由 composition 自己顯示。
var _status_view := PresentationStatusView.new()
var _visible_error_key: StringName = &""
var _editors: Dictionary[StringName, Control] = {}
var _labels: Dictionary[StringName, Label] = {}
var _value_labels: Dictionary[StringName, Label] = {}
var _localized_text: Dictionary[StringName, String] = {}
var _status_rect := Rect2()


## SETTINGS 版面權威（ProductionScreen._apply_settings_layout）指定 draft
## 驗證狀態列在 Composition 內的 rect；同步把捲動區的底部讓出來，
## 確保訊息不被 clip_contents 剪掉、也不與內容疊字。
func apply_status_rect(rect: Rect2) -> void:
	_status_rect = rect
	_status_view.attach(self, 1, rect)
	var scroll := get_node_or_null(^"SettingsScroll") as ScrollContainer
	if scroll != null and rect.size.y > 0.0:
		scroll.offset_bottom = -rect.size.y


func stage(
	snapshot: SettingsSnapshot,
	localized_text: Dictionary = {}
) -> StringName:
	if snapshot == null:
		return DRAFT_INVALID
	_set_localized_text(localized_text)
	_draft = snapshot.deep_clone()
	_committed = snapshot.deep_clone()
	_build_editors()
	_apply_control_status(&"")
	return &""


## 局內系統選單與獨立 SETTINGS route 共用同一個 editor 組裝入口。
## 這個入口只 stage clone，不做 route transition，也不持有 application service。
func compose_embedded(
	snapshot: SettingsSnapshot,
	localized_text: Dictionary = {}
) -> StringName:
	return stage(snapshot, localized_text)


## 內嵌宿主以既有 typed application port 提交目前 draft；成功或 post-commit
## presentation failure 都以 application 回傳的 committed snapshot 回填 editor。
func submit_through(
	port: SettingsApplicationPort
) -> SettingsApplicationResult:
	if port == null or _draft == null:
		_apply_control_status(SettingsScreenPresenter.SETTINGS_PORT_INVALID)
		return SettingsApplicationResult.failure(DiagnosticError.new(
			SettingsScreenPresenter.SETTINGS_PORT_INVALID,
			&"error.settings.port_invalid"
		))
	var validation := _validate_draft(_draft)
	if not validation.is_empty():
		_apply_control_status(validation)
		return SettingsApplicationResult.failure(DiagnosticError.new(
			validation,
			DEFAULT_MESSAGE_KEY
		))
	var result := port.apply(_draft.deep_clone())
	if result == null:
		_apply_control_status(SettingsScreenPresenter.SETTINGS_PORT_INVALID)
		return SettingsApplicationResult.failure(DiagnosticError.new(
			SettingsScreenPresenter.SETTINGS_PORT_INVALID,
			&"error.settings.application_invalid_result"
		))
	if result.snapshot != null and (result.ok or result.committed):
		mark_committed(result.snapshot)
	_apply_control_status(
		&""
		if result.ok
		else (
			result.error.source_code
			if result.error != null
			else DEFAULT_MESSAGE_KEY
		)
	)
	return result


func settings_draft() -> SettingsSnapshot:
	return _draft.deep_clone() if _draft != null else null


func replace_settings_draft(candidate: SettingsSnapshot) -> StringName:
	var validation := _validate_draft(candidate)
	if not validation.is_empty():
		_apply_control_status(validation)
		return validation
	_draft = candidate.deep_clone()
	_apply_control_status(&"")
	_sync_editors()
	return &""


func committed_settings_snapshot() -> SettingsSnapshot:
	return _committed.deep_clone() if _committed != null else null


func mark_committed(snapshot: SettingsSnapshot) -> void:
	if snapshot != null:
		_committed = snapshot.deep_clone()
		_draft = snapshot.deep_clone()
	_apply_control_status(&"")
	_sync_editors()


func set_control_status_code(code: StringName) -> void:
	_apply_control_status(code)


func control_status_code() -> StringName:
	return _control_status_code


## `SettingsScreenPresenter.visible_error_key()` 的同名生產端消費者：
## 玩家看得到的錯誤訊息鍵（沒有錯誤時為 &""）。
func visible_error_key() -> StringName:
	return _visible_error_key


func status_message_text() -> String:
	return _status_view.message_text()


func _apply_control_status(code: StringName) -> void:
	_control_status_code = code
	if code.is_empty():
		_visible_error_key = &""
		_status_view.clear(_text_resolver())
		return
	# 設定套用是 pre-commit 語意：驗證/重建失敗時 repository 沒有被寫入。
	_status_view.show_failure(code, false, DEFAULT_MESSAGE_KEY, _text_resolver())
	_visible_error_key = StringName(
		_status_view.report().get("message_key", DEFAULT_MESSAGE_KEY)
	)


func _text_resolver() -> Callable:
	return func(key: StringName) -> String:
		return _text(key)


func focus_controls() -> Array[Control]:
	var result: Array[Control] = []
	for setting_id: StringName in SETTING_ORDER:
		var editor := _editors.get(setting_id) as Control
		if (
			editor == null
			or not editor.visible
			or editor.focus_mode == Control.FOCUS_NONE
		):
			continue
		if editor is BaseButton and (editor as BaseButton).disabled:
			continue
		result.append(editor)
	return result


func relocalize(localized_text: Dictionary) -> void:
	_set_localized_text(localized_text)
	_status_view.relocalize(_text_resolver())
	for setting_id: StringName in _labels:
		var label := _labels[setting_id]
		label.text = _text(_label_key(setting_id))
		var editor := _editors.get(setting_id) as Control
		if editor != null:
			editor.set_meta(&"accessible_text", label.text)
		if editor is CheckButton:
			(editor as CheckButton).text = ""
		elif editor is OptionButton:
			var options := editor as OptionButton
			for index: int in options.item_count:
				var wire_value := String(options.get_item_metadata(index))
				options.set_item_text(
					index,
					_option_text(setting_id, wire_value)
				)


func _build_editors() -> void:
	for child: Node in get_children():
		# 先讓出節點名稱再排隊釋放：只 queue_free 的話舊節點在本影格仍佔著名字，
		# 重建出來的 SettingEditors／StatusMessage 會被 Godot 自動改名。
		child.name = "%sRetired" % child.name
		child.queue_free()
	_editors.clear()
	_labels.clear()
	_value_labels.clear()
	# row 1：SETTINGS 的 ProductionScreen 自己已經在 row 0 掛了一條狀態列
	# （動作失敗用），draft 驗證訊息獨立一列；實際 rect 由
	# `apply_status_rect()`（ProductionScreen 的設定版面權威）指定，
	# 確保它落在 Composition 可見高度內、不被 clip_contents 剪掉（P4）。
	_status_view.attach(self, 1, _status_rect)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	if _status_rect.size.y > 0.0:
		scroll.offset_bottom = -_status_rect.size.y
	add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "SettingEditors"
	rows.theme_type_variation = &"ExpeditionSettingsRows"
	ExpeditionLayoutMetrics.set_min(rows, 1674.0, 0.0)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	_add_option(rows, &"locale", ["zh_TW", "en"], String(_draft.locale))
	_add_option(rows, &"ui_scale_percent", ["100", "125", "150"], str(_draft.ui_scale_percent))
	_add_option(
		rows,
		&"color_vision_mode",
		["default", "protanopia", "deuteranopia", "tritanopia"],
		String(_draft.color_vision_mode)
	)
	_add_toggle(rows, &"reduced_motion", _draft.reduced_motion)
	_add_toggle(rows, &"reduced_flash", _draft.reduced_flash)
	_add_toggle(rows, &"reduced_particles", _draft.reduced_particles)
	_add_option(
		rows,
		&"damage_number_density",
		["off", "reduced", "full"],
		String(_draft.damage_number_density)
	)
	_add_volume(rows, &"master.volume", _draft.master_volume_bps)
	_add_toggle(rows, &"master.mute", _draft.master_muted)
	_add_volume(rows, &"music.volume", _draft.music_volume_bps)
	_add_toggle(rows, &"music.mute", _draft.music_muted)
	_add_volume(rows, &"sfx.volume", _draft.sfx_volume_bps)
	_add_toggle(rows, &"sfx.mute", _draft.sfx_muted)
	_add_volume(rows, &"ui.volume", _draft.ui_volume_bps)
	_add_toggle(rows, &"ui.mute", _draft.ui_muted)


func _add_option(
	parent: Control,
	setting_id: StringName,
	values: Array,
	current: String
) -> void:
	var row := _add_labeled_row(parent, setting_id)
	var editor := OptionButton.new()
	editor.theme_type_variation = &"ExpeditionSettingsOption"
	_prepare_editor(editor, setting_id)
	for value: String in values:
		editor.add_item(_option_text(setting_id, value))
		editor.set_item_metadata(editor.item_count - 1, value)
	editor.select(maxi(values.find(current), 0))
	editor.item_selected.connect(_on_option_selected.bind(setting_id, values))
	editor.gui_input.connect(_on_option_gui_input.bind(editor, setting_id, values))
	row.add_child(editor)


func _add_toggle(
	parent: Control,
	setting_id: StringName,
	current: bool
) -> void:
	var row := _add_labeled_row(parent, setting_id)
	var editor := CheckButton.new()
	editor.theme_type_variation = &"ExpeditionSettingsToggle"
	_prepare_editor(editor, setting_id)
	editor.text = ""
	editor.button_pressed = current
	editor.toggled.connect(_on_toggle_changed.bind(setting_id))
	row.add_child(editor)


func _add_volume(
	parent: Control,
	setting_id: StringName,
	current: int
) -> void:
	var row := _add_labeled_row(parent, setting_id)
	var editor := HSlider.new()
	_prepare_editor(editor, setting_id)
	ExpeditionLayoutMetrics.set_min(editor, 270.0, 0.0)
	editor.min_value = 0
	editor.max_value = 10000
	editor.step = 100
	editor.value = current
	editor.value_changed.connect(_on_volume_changed.bind(setting_id))
	row.add_child(editor)
	var value_label := Label.new()
	value_label.text = "%d%%" % int(roundi(float(current) / 100.0))
	row.add_child(value_label)
	_value_labels[setting_id] = value_label


func _prepare_editor(editor: Control, setting_id: StringName) -> void:
	editor.name = String(setting_id).replace(".", "_").to_pascal_case()
	editor.focus_mode = Control.FOCUS_ALL
	editor.set_meta(&"setting_id", setting_id)
	if editor is BaseButton:
		editor.set_meta(&"expedition_theme_fixed_minimum", true)
	editor.set_meta(&"accessible_text", _text(_label_key(setting_id)))
	editor.tooltip_text = ""
	_editors[setting_id] = editor


func _add_labeled_row(
	parent: Control,
	setting_id: StringName
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "%sRow" % String(setting_id).replace(".", "_").to_pascal_case()
	parent.add_child(row)
	var label := Label.new()
	label.text = _text(_label_key(setting_id))
	label.theme_type_variation = &"ExpeditionSettingsLabel"
	ExpeditionLayoutMetrics.set_min(label, 285.0, 0.0)
	row.add_child(label)
	_labels[setting_id] = label
	return row


func _on_option_gui_input(
	event: InputEvent,
	editor: OptionButton,
	setting_id: StringName,
	values: Array
) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var direction := 0
	if key.keycode == KEY_RIGHT:
		direction = 1
	elif key.keycode == KEY_LEFT:
		direction = -1
	if direction == 0:
		return
	var next := posmod(editor.selected + direction, values.size())
	editor.select(next)
	_on_option_selected(next, setting_id, values)
	editor.accept_event()


func _on_option_selected(
	index: int,
	setting_id: StringName,
	values: Array
) -> void:
	if _draft == null or index < 0 or index >= values.size():
		return
	var value: String = String(values[index])
	match setting_id:
		&"locale":
			_draft.locale = StringName(value)
		&"ui_scale_percent":
			_draft.ui_scale_percent = int(value)
		&"color_vision_mode":
			_draft.color_vision_mode = StringName(value)
		&"damage_number_density":
			_draft.damage_number_density = StringName(value)


func _on_toggle_changed(pressed: bool, setting_id: StringName) -> void:
	if _draft == null:
		return
	match setting_id:
		&"reduced_motion":
			_draft.reduced_motion = pressed
		&"reduced_flash":
			_draft.reduced_flash = pressed
		&"reduced_particles":
			_draft.reduced_particles = pressed
		&"master.mute":
			_draft.master_muted = pressed
		&"music.mute":
			_draft.music_muted = pressed
		&"sfx.mute":
			_draft.sfx_muted = pressed
		&"ui.mute":
			_draft.ui_muted = pressed


func _on_volume_changed(value: float, setting_id: StringName) -> void:
	if _draft == null:
		return
	match setting_id:
		&"master.volume":
			_draft.master_volume_bps = int(value)
		&"music.volume":
			_draft.music_volume_bps = int(value)
		&"sfx.volume":
			_draft.sfx_volume_bps = int(value)
		&"ui.volume":
			_draft.ui_volume_bps = int(value)
	var value_label := _value_labels.get(setting_id) as Label
	if value_label != null:
		value_label.text = "%d%%" % int(roundi(value / 100.0))


func _sync_editors() -> void:
	if _draft == null or _editors.is_empty():
		return
	_sync_option(&"locale", String(_draft.locale))
	_sync_option(&"ui_scale_percent", str(_draft.ui_scale_percent))
	_sync_option(&"color_vision_mode", String(_draft.color_vision_mode))
	_sync_option(&"damage_number_density", String(_draft.damage_number_density))
	_sync_toggle(&"reduced_motion", _draft.reduced_motion)
	_sync_toggle(&"reduced_flash", _draft.reduced_flash)
	_sync_toggle(&"reduced_particles", _draft.reduced_particles)
	_sync_toggle(&"master.mute", _draft.master_muted)
	_sync_toggle(&"music.mute", _draft.music_muted)
	_sync_toggle(&"sfx.mute", _draft.sfx_muted)
	_sync_toggle(&"ui.mute", _draft.ui_muted)
	_sync_volume(&"master.volume", _draft.master_volume_bps)
	_sync_volume(&"music.volume", _draft.music_volume_bps)
	_sync_volume(&"sfx.volume", _draft.sfx_volume_bps)
	_sync_volume(&"ui.volume", _draft.ui_volume_bps)


func _sync_option(setting_id: StringName, value: String) -> void:
	var editor := _editors.get(setting_id) as OptionButton
	if editor == null:
		return
	for index: int in editor.item_count:
		if String(editor.get_item_metadata(index)) == value:
			editor.select(index)
			return


func _sync_toggle(setting_id: StringName, value: bool) -> void:
	var editor := _editors.get(setting_id) as CheckButton
	if editor != null:
		editor.set_pressed_no_signal(value)


func _sync_volume(setting_id: StringName, value: int) -> void:
	var editor := _editors.get(setting_id) as HSlider
	if editor != null:
		editor.set_value_no_signal(value)
	var value_label := _value_labels.get(setting_id) as Label
	if value_label != null:
		value_label.text = "%d%%" % int(roundi(float(value) / 100.0))


func _set_localized_text(values: Dictionary) -> void:
	_localized_text.clear()
	for key: Variant in values.keys():
		_localized_text[StringName(key)] = String(values[key])


func _text(key: StringName) -> String:
	return _localized_text.get(key, String(key))


func _label_key(setting_id: StringName) -> StringName:
	return StringName("settings.field.%s" % String(setting_id).replace(".", "_"))


func _option_text(setting_id: StringName, wire_value: String) -> String:
	var key := StringName(
		"settings.value.%s.%s" % [
			String(setting_id).replace(".", "_"),
			wire_value,
		]
	)
	return _text(key)


func _validate_draft(candidate: SettingsSnapshot) -> StringName:
	if candidate == null or candidate.schema_version != 1:
		return DRAFT_INVALID
	if candidate.locale not in [&"zh_TW", &"en"]:
		return SettingsScreenPresenter.SETTINGS_INVALID_ENUM
	if candidate.ui_scale_percent not in [100, 125, 150]:
		return SettingsScreenPresenter.SETTINGS_FIELD_OUT_OF_RANGE
	if candidate.color_vision_mode not in [
		&"default",
		&"protanopia",
		&"deuteranopia",
		&"tritanopia",
	]:
		return SettingsScreenPresenter.SETTINGS_INVALID_ENUM
	if candidate.damage_number_density not in [&"off", &"reduced", &"full"]:
		return SettingsScreenPresenter.SETTINGS_INVALID_ENUM
	for volume: int in [
		candidate.master_volume_bps,
		candidate.music_volume_bps,
		candidate.sfx_volume_bps,
		candidate.ui_volume_bps,
	]:
		if volume < 0 or volume > 10000:
			return SettingsScreenPresenter.SETTINGS_FIELD_OUT_OF_RANGE
	return &""
