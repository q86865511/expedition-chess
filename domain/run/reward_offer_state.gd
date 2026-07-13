class_name RewardOfferState
extends RefCounted

enum RewardKind { UNIT, ITEM, RELIC, GOLD, EVENT }

var choice_id: String
var reward_kind: RewardKind
var content_id: OptionalStringNameValue
var amount: int
var reservation_owner_key: ReservationOwnerKeyState
var payload_digest: String

func _init(
	p_choice_id: String,
	p_reward_kind: RewardKind,
	p_content_id: OptionalStringNameValue,
	p_amount: int,
	p_reservation_owner_key: ReservationOwnerKeyState,
	p_payload_digest: String
) -> void:
	choice_id = p_choice_id
	reward_kind = p_reward_kind
	content_id = p_content_id.deep_clone() if p_content_id != null else null
	amount = p_amount
	reservation_owner_key = p_reservation_owner_key.deep_clone() if p_reservation_owner_key != null else null
	payload_digest = p_payload_digest

func deep_clone() -> RewardOfferState:
	return RewardOfferState.new(
		choice_id,
		reward_kind,
		content_id,
		amount,
		reservation_owner_key,
		payload_digest
	)
