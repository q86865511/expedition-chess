class_name EconomyState
extends RefCounted

var gold: int
var level: int
var xp: int
var win_streak: int
var loss_streak: int
var shop_refresh_index: int
var shop_offers: Array[ShopOffer] = []

func _init(
	p_gold: int,
	p_level: int,
	p_xp: int,
	p_win_streak: int,
	p_loss_streak: int,
	p_shop_refresh_index: int,
	p_shop_offers: Array[ShopOffer]
) -> void:
	gold = p_gold
	level = p_level
	xp = p_xp
	win_streak = p_win_streak
	loss_streak = p_loss_streak
	shop_refresh_index = p_shop_refresh_index
	for offer: ShopOffer in p_shop_offers:
		shop_offers.append(offer.deep_clone())

func deep_clone() -> EconomyState:
	return EconomyState.new(gold, level, xp, win_streak, loss_streak, shop_refresh_index, shop_offers)
