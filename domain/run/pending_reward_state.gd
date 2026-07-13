class_name PendingRewardState
extends RefCounted

enum StageId { STANDARD, RELIC, EVENT_GRANT }
enum Phase { CHOOSING, UNIT_RESOLUTION, ITEM_RESOLUTION, RELIC_RESOLUTION, READY_TO_ADVANCE }

var node_id: String
var stage_id: StageId
var phase: Phase
var offers: Array[RewardOfferState] = []
var reserved_copies: Array[ReservedCopyState] = []
var selected_choice_id: OptionalStringValue
var selected_unit_reservation: ReservationOwnerKeyState
var transaction_id: TransactionKeyState

func _init(
	p_node_id: String,
	p_stage_id: StageId,
	p_phase: Phase,
	p_offers: Array[RewardOfferState],
	p_reserved_copies: Array[ReservedCopyState],
	p_selected_choice_id: OptionalStringValue,
	p_selected_unit_reservation: ReservationOwnerKeyState,
	p_transaction_id: TransactionKeyState
) -> void:
	node_id = p_node_id
	stage_id = p_stage_id
	phase = p_phase
	for offer: RewardOfferState in p_offers:
		offers.append(offer.deep_clone())
	for reserved: ReservedCopyState in p_reserved_copies:
		reserved_copies.append(reserved.deep_clone())
	selected_choice_id = p_selected_choice_id.deep_clone() if p_selected_choice_id != null else null
	selected_unit_reservation = p_selected_unit_reservation.deep_clone() if p_selected_unit_reservation != null else null
	transaction_id = p_transaction_id.deep_clone()

func deep_clone() -> PendingRewardState:
	return PendingRewardState.new(
		node_id,
		stage_id,
		phase,
		offers,
		reserved_copies,
		selected_choice_id,
		selected_unit_reservation,
		transaction_id
	)
