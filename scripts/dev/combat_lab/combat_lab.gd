class_name CombatLabScreen
extends Control

@onready var board_grid: GridContainer = %BoardGrid
@onready var bench_row: HBoxContainer = %BenchRow
@onready var preview_label: RichTextLabel = %PreviewLabel
@onready var detail_label: Label = %DetailLabel
@onready var event_log: RichTextLabel = %EventLog
@onready var start_button: Button = %StartButton
@onready var pause_button: Button = %PauseButton
@onready var encounter_button: Button = %EncounterButton

var _presenter := CombatLabPresenter.new()
var _session := CombatLabSession.new()
var _running: bool = false
var _paused: bool = false
var _speed: int = 1
var _boss_mode: bool = false
var _selected_proxy_index: int = -1
var _player_cells: Array[Vector2i] = []
var _board_buttons: Array[Button] = []

func _ready() -> void:
	for index: int in range(8):
		_player_cells.append(Vector2i(index % 4 + 2, index / 4))
	_build_board()
	_build_bench()
	start_button.pressed.connect(_start)
	pause_button.pressed.connect(_toggle_pause)
	encounter_button.pressed.connect(_toggle_encounter)
	%Speed1.pressed.connect(func() -> void: _speed = 1)
	%Speed2.pressed.connect(func() -> void: _speed = 2)
	%Speed4.pressed.connect(func() -> void: _speed = 4)
	_update_preview()
	detail_label.text = "點選任意格查看座標；開始後完全自動。"

func _process(_delta: float) -> void:
	if not _running or _paused:
		return
	for _index: int in range(_speed):
		var stepped := _session.step()
		if not stepped.ok:
			event_log.append_text("\nERROR %s" % String(stepped.error.code))
			_running = false
			return
		_presenter.present_events(stepped.events)
		_render_events(stepped.events)
		if stepped.finished:
			var queried := _session.result()
			if queried.ok:
				_presenter.present_result(queried.result)
				detail_label.text = "戰鬥完成：%s｜遠征傷害 %d" % [
					String(queried.result.outcome), queried.result.expedition_damage
				]
			_running = false
			return

func _start() -> void:
	var setup := CombatLabProxySetupFactory.new().build(
		_boss_mode, _player_cells
	)
	if setup == null:
		detail_label.text = "代理 BattleSetup 建立失敗"
		return
	var initialized := _session.start(setup)
	if not initialized.ok:
		detail_label.text = "模擬初始化失敗：%s" % String(initialized.error.code)
		return
	_presenter.present_setup(setup)
	event_log.text = ""
	_paused = false
	pause_button.text = "暫停"
	_running = true
	detail_label.text = "戰鬥進行中（%d×）" % _speed

func _toggle_encounter() -> void:
	if _running:
		return
	_boss_mode = not _boss_mode
	encounter_button.text = "Boss" if _boss_mode else "普通"
	_update_preview()

func _update_preview() -> void:
	if _boss_mode:
		preview_label.text = "[b]敵方預覽｜兩階段 Boss[/b]\n代理巨像｜1200 HP｜38 ATK｜28 ARM\n站位 (5,3)｜階段：75%／35%｜目標：frontline"
	else:
		preview_label.text = "[b]敵方預覽｜普通遭遇[/b]\n掠奪者／弓手／守衛／咒術師\n完整站位與有效數值來自同一 BattleSetup snapshot"

func _toggle_pause() -> void:
	_paused = not _paused
	pause_button.text = "繼續" if _paused else "暫停"

func _build_board() -> void:
	for y: int in range(8):
		for x: int in range(8):
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(48, 48)
			cell.text = "%d,%d" % [y, x]
			cell.modulate = Color("6a7f96") if y < 4 else Color("9a675f")
			cell.pressed.connect(func() -> void:
				_on_board_cell_pressed(y, x)
			)
			board_grid.add_child(cell)
			_board_buttons.append(cell)
	_refresh_board_labels()

func _build_bench() -> void:
	var proxy_ids := CombatLabProxySetupFactory.new().proxy_unit_ids()
	for index: int in range(9):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(48, 36)
		slot.text = str(index + 1) if index >= proxy_ids.size() else String(proxy_ids[index]).trim_prefix("unit.proxy_").left(3)
		slot.tooltip_text = "板凳槽 %d（左至右緊縮）" % (index + 1)
		if index < proxy_ids.size():
			slot.tooltip_text += "｜%s" % String(proxy_ids[index])
			slot.pressed.connect(func() -> void:
				_selected_proxy_index = index
				detail_label.text = "已選擇 %s；點玩家半場格位部署。" % String(proxy_ids[index])
			)
		bench_row.add_child(slot)

func _on_board_cell_pressed(y: int, x: int) -> void:
	if _running or y >= 4 or _selected_proxy_index < 0:
		detail_label.text = "格位 (%d,%d)｜%s半場" % [
			y, x, "玩家" if y < 4 else "敵方"
		]
		return
	var destination := Vector2i(x, y)
	var occupied_index := _player_cells.find(destination)
	if occupied_index >= 0 and occupied_index != _selected_proxy_index:
		var previous := _player_cells[_selected_proxy_index]
		_player_cells[occupied_index] = previous
	_player_cells[_selected_proxy_index] = destination
	_refresh_board_labels()
	detail_label.text = "%s → (%d,%d)" % [
		String(CombatLabProxySetupFactory.PROXY_UNIT_IDS[_selected_proxy_index]), y, x
	]

func _refresh_board_labels() -> void:
	for index: int in range(_board_buttons.size()):
		var y := index / 8
		var x := index % 8
		_board_buttons[index].text = "%d,%d" % [y, x]
	for proxy_index: int in range(_player_cells.size()):
		var cell := _player_cells[proxy_index]
		var button_index := cell.y * 8 + cell.x
		if button_index >= 0 and button_index < _board_buttons.size():
			_board_buttons[button_index].text = String(
				CombatLabProxySetupFactory.PROXY_UNIT_IDS[proxy_index]
			).trim_prefix("unit.proxy_").left(3)

func _render_events(events: Array[BattleEvent]) -> void:
	for event: BattleEvent in events:
		event_log.append_text("[%04d:%04d] %s\n" % [
			event.tick, event.sequence, String(event.type)
		])
