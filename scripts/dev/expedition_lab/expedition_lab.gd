class_name ExpeditionLabScreen
extends Control

@onready var act_label: Label = %ActLabel
@onready var node_label: Label = %NodeLabel
@onready var hp_label: Label = %HpLabel
@onready var gold_label: Label = %GoldLabel
@onready var phase_label: Label = %PhaseLabel
@onready var reward_button: Button = %RewardButton
@onready var log_label: RichTextLabel = %LogLabel

var _session := ExpeditionLabSession.new()

func _ready() -> void:
	%EnterButton.pressed.connect(_enter_node)
	%WinButton.pressed.connect(func() -> void: _settle(true, false))
	%LossButton.pressed.connect(func() -> void: _settle(false, false))
	%BossLossButton.pressed.connect(func() -> void: _settle(false, true))
	reward_button.pressed.connect(_choose_reward)
	_render(_session.snapshot(), "Lab ready")

func _enter_node() -> void:
	_render(_session.enter_node(), "節點收入已提交")

func _settle(win: bool, boss: bool) -> void:
	var message := "勝利候選已提交" if win else (
		"Boss 戰敗：保留商店並重戰" if boss else "戰敗：無獎勵並離場"
	)
	_render(_session.settle_demo(win, boss), message)

func _choose_reward() -> void:
	_render(_session.choose_gold_reward(), "獎勵領取完成並離場")

func _render(snapshot: ExpeditionLabSnapshot, message: String) -> void:
	act_label.text = "幕 %d / 3" % snapshot.act_index
	node_label.text = "節點 %d / 7" % snapshot.node_index
	hp_label.text = "遠征 HP：%d" % snapshot.expedition_hp
	gold_label.text = "金幣：%d" % snapshot.gold
	phase_label.text = "Phase：%s" % String(snapshot.phase)
	reward_button.disabled = not snapshot.reward_ready
	log_label.append_text("%s｜%s\n" % [message, String(snapshot.phase)])
