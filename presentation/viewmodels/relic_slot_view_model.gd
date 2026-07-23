class_name RelicSlotViewModel
extends RefCounted

## T10 / S4-AC-013 (specs/build-systems/design.md §8) -- 遺物槽序 ViewModel:
## 讀 active_relic_slots(槽序/內容)＋第六件替換候選,寫端一律經
## RunController.dispatch(ResolveRelicRewardCommand)(design §8 既有 command)。
## pending_replacement_candidate() 讀 RunController.pending_reward_snapshot()
## -- 非 REWARD/RELIC_RESOLUTION 階段、或沒有已選定的 RELIC 類 offer 時回傳
## null,讓 UI 知道目前沒有可預覽的替換候選。

var _controller: RunController

func _init(controller: RunController) -> void:
	_controller = controller

## 目前 5 個遺物槽的快照,原樣沿用 RosterState.active_relic_slots 的排列順序。
func active_slots() -> Array[RelicSlotState]:
	return _controller.roster_snapshot().active_relic_slots

## RELIC_RESOLUTION 階段中已選定的 RELIC 類 offer 之 content_id;非該階段、
## 或選定的 offer 不是 RELIC 類時回傳 null。
func pending_replacement_candidate() -> OptionalStringNameValue:
	var pending := _controller.pending_reward_snapshot()
	return _selected_relic_content_id(pending) if pending != null else null

## 分派真正的 ResolveRelicRewardCommand 經 RunController.dispatch()。
func choose_slot(slot_index: int, catalog: EconomyExpeditionCatalog) -> CommandResult:
	var command := ResolveRelicRewardCommand.new(slot_index, catalog)
	return _controller.dispatch(command)

func _selected_relic_content_id(pending: PendingRewardState) -> OptionalStringNameValue:
	if pending.phase != PendingRewardState.Phase.RELIC_RESOLUTION:
		return null
	if pending.selected_choice_id == null:
		return null
	var offer := _find_offer(pending, pending.selected_choice_id.value)
	if offer == null or offer.reward_kind != RewardOfferState.RewardKind.RELIC:
		return null
	return offer.content_id

func _find_offer(pending: PendingRewardState, choice_id: String) -> RewardOfferState:
	for offer: RewardOfferState in pending.offers:
		if offer.choice_id == choice_id:
			return offer
	return null
