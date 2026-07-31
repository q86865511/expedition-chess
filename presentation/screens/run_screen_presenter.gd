class_name RunScreenPresenter
extends RefCounted

const ACTION_NOT_AVAILABLE: StringName = &"ACTION_NOT_AVAILABLE"

const _ROUTE_INTENTS: Dictionary = {
	&"RUN_MAP": [
		RunPresentationIntent.Kind.GENERATE_MAP,
		RunPresentationIntent.Kind.ENTER_NODE,
	],
	&"RUN_PREPARE": [
		RunPresentationIntent.Kind.COMMIT_NODE_CHOICE,
		RunPresentationIntent.Kind.REFRESH_SHOP,
		RunPresentationIntent.Kind.BUY_UNIT,
		RunPresentationIntent.Kind.BUY_XP,
		RunPresentationIntent.Kind.SELL_UNIT,
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT,
		RunPresentationIntent.Kind.EQUIP_ITEM,
		RunPresentationIntent.Kind.DISMANTLE_EQUIPMENT,
		# node service（design :208-214）整段生命週期都在 RUN_PREPARE 內：
		# 服務內拆解不限次數，離場命令是唯一出口，ack 則負責關掉結果重播。
		RunPresentationIntent.Kind.DISMANTLE_WITH_NODE_SERVICE,
		RunPresentationIntent.Kind.EXIT_NODE_SERVICE,
		RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT,
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT,
	],
	&"RUN_COMBAT": [
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT,
		RunPresentationIntent.Kind.SETTLE_BATTLE,
	],
	&"RUN_REWARD": [
		RunPresentationIntent.Kind.RESOLVE_NON_COMBAT,
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD,
		RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD,
		RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD,
		RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD,
		RunPresentationIntent.Kind.ADVANCE_REWARD,
		RunPresentationIntent.Kind.RESOLVE_UNIT_OVERFLOW,
		RunPresentationIntent.Kind.RESOLVE_ITEM_OVERFLOW,
	],
}

const _CONFIRMATION_ROUTES: Dictionary = {
	RunPresentationIntent.Kind.FORGE_EQUIPMENT: &"RUN_PREPARE",
	RunPresentationIntent.Kind.REPLACE_RELIC: &"RUN_REWARD",
	RunPresentationIntent.Kind.ABANDON_RELIC: &"RUN_REWARD",
	RunPresentationIntent.Kind.ABANDON_BOSS_RETRY: &"RUN_REWARD",
	RunPresentationIntent.Kind.COMMIT_NODE_CHOICE: &"RUN_PREPARE",
}

var _route_kind: StringName
var _intent_port: LiveScreenIntentPort


func _init(
	p_route_kind: StringName = &"",
	p_intent_port: LiveScreenIntentPort = null
) -> void:
	_route_kind = p_route_kind
	_intent_port = p_intent_port


func request(intent: RunPresentationIntent) -> RunPresentationResult:
	if (
		_intent_port == null
		or intent == null
		or not _route_allows(intent.kind)
	):
		return RunPresentationResult.failure(_action_not_available_error())
	return _intent_port.dispatch(intent)


func begin_confirmation(
	intent: RunPresentationIntent
) -> ConfirmationDraftResult:
	if (
		_intent_port == null
		or intent == null
		or _CONFIRMATION_ROUTES.get(intent.kind, &"") != _route_kind
	):
		return ConfirmationDraftResult.failure(_action_not_available_error())
	return _intent_port.begin_confirmation(intent)


func cancel_confirmation(
	draft: ConfirmationDraft
) -> ConfirmationCancelResult:
	if _intent_port == null:
		return ConfirmationCancelResult.failure(_action_not_available_error())
	return _intent_port.cancel(draft)


func confirm_confirmation(
	draft: ConfirmationDraft
) -> RunPresentationResult:
	if _intent_port == null:
		return RunPresentationResult.failure(_action_not_available_error())
	return _intent_port.confirm(draft)


func _route_allows(kind: RunPresentationIntent.Kind) -> bool:
	var allowed: Array = _ROUTE_INTENTS.get(_route_kind, [])
	return allowed.has(kind)


func _action_not_available_error() -> DiagnosticError:
	return DiagnosticError.new(
		ACTION_NOT_AVAILABLE,
		&"error.presentation.action_not_available"
	)
