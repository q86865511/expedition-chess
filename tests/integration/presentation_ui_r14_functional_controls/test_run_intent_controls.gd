extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)


func test_map_buttons_generate_select_and_confirm_through_typed_intents() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	session.current_snapshot = RunPresentationSnapshot.new()
	session.current_snapshot.run_id = &"run.r14.functional.map"
	session.current_snapshot.app_phase = &"MAP"
	session.current_snapshot.manifest_digest = "manifest.r14.functional.map"
	var screen := Support.live_run_screen(
		self,
		&"RUN_MAP",
		session.current_snapshot,
		session
	)
	if screen == null:
		return

	assert_true(Support.press(self, screen, &"map.select"))
	assert_eq(
		session.dispatched_kinds,
		[RunPresentationIntent.Kind.GENERATE_MAP],
		"select node without a generated map must dispatch GENERATE_MAP"
	)
	var composition := Support.composition(screen)
	var selected := (
		String(composition.call(&"selected_node_id"))
		if composition != null and composition.has_method(&"selected_node_id")
		else ""
	)
	assert_false(
		selected.is_empty(),
		"map.select must expose a visible consumer selection after generation"
	)
	assert_true(Support.press(self, screen, &"map.confirm"))
	var map_last_kind: int = (
		-1
		if session.dispatched_kinds.is_empty()
		else int(session.dispatched_kinds.back())
	)
	assert_eq(
		map_last_kind,
		RunPresentationIntent.Kind.ENTER_NODE,
		"confirm with a selection must dispatch ENTER_NODE"
	)


func test_prepare_and_reward_controls_dispatch_route_specific_intents() -> void:
	var prepare_session := Support.CompositionSupport.SpyRunPresentationSession.new()
	prepare_session.current_snapshot = Support.CompositionSupport.prepare_snapshot()
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		prepare_session.current_snapshot,
		prepare_session
	)
	if prepare == null:
		return
	assert_true(Support.press(self, prepare, &"prepare.unit"))
	assert_true(
		prepare_session.dispatched_kinds.has(
			RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT
		),
		"prepare.unit must dispatch a typed board draft, not a generic app action"
	)
	assert_true(Support.press(self, prepare, &"prepare.start"))
	var prepare_last_kind: int = (
		-1
		if prepare_session.dispatched_kinds.is_empty()
		else int(prepare_session.dispatched_kinds.back())
	)
	assert_eq(
		prepare_last_kind,
		RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
	)

	var reward_session := Support.CompositionSupport.SpyRunPresentationSession.new()
	reward_session.current_snapshot = Support.CompositionSupport.reward_snapshot(
		PendingRewardState.Phase.CHOOSING
	)
	var reward := Support.live_run_screen(
		self,
		&"RUN_REWARD",
		reward_session.current_snapshot,
		reward_session
	)
	if reward == null:
		return
	assert_true(Support.press(self, reward, &"reward.select"))
	var reward_composition := Support.composition(reward)
	assert_false(
		String(
			reward_composition.call(&"selected_reward_id")
			if (
				reward_composition != null
				and reward_composition.has_method(&"selected_reward_id")
			)
			else ""
		).is_empty()
	)
	assert_true(Support.press(self, reward, &"reward.confirm"))
	var reward_last_kind: int = (
		-1
		if reward_session.dispatched_kinds.is_empty()
		else int(reward_session.dispatched_kinds.back())
	)
	assert_eq(
		reward_last_kind,
		RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD
	)


func test_prepare_inventory_is_visible_focusable_and_shop_dispatches_once() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	session.current_snapshot = _prepare_snapshot_with_shop()
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return
	await wait_process_frames(2)
	var inventory := prepare.find_child(
		"InventorySelector", true, false
	) as ItemList
	assert_not_null(inventory)
	if inventory != null:
		assert_true(inventory.is_visible_in_tree())
		assert_eq(inventory.focus_mode, Control.FOCUS_ALL)
		assert_true(
			(prepare.call(&"_ordered_focus_controls") as Array).has(inventory),
			"the central inventory must be keyboard reachable"
		)
	var cards := prepare.find_children("ShopCard*", "Button", true, false)
	assert_eq(cards.size(), 5)
	if cards.is_empty():
		return
	var before := session.dispatched_kinds.size()
	(cards[0] as Button).pressed.emit()
	assert_eq(
		session.dispatched_kinds.size(),
		before + 1,
		"one shop-card click must dispatch BUY_UNIT exactly once"
	)
	assert_eq(
		int(session.dispatched_kinds.back()),
		RunPresentationIntent.Kind.BUY_UNIT
	)


func test_shop_cards_relocalize_without_shadowing_exact_buy_action() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := _prepare_snapshot_with_shop(1)
	var preview := snapshot.shop_offer_previews[0]
	preview.cost = 3
	preview.cost_tier = 2
	preview.trait_ids.assign([&"trait.fire"])
	preview.owned_unit_count = 3
	preview.star_up_after_purchase = true
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return
	await wait_process_frames(2)
	var cards := prepare.find_children("ShopCard*", "Button", true, false)
	assert_eq(cards.size(), 5)
	if cards.size() != 5:
		return
	var offer_card: Button
	var empty_cards: Array[Button] = []
	for node: Node in cards:
		var card := node as Button
		assert_not_null(card)
		if card == null:
			continue
		assert_false(
			card.has_meta(&"action_id"),
			"shop cards are exact-offer controls, never generic actions"
		)
		assert_true(card.has_meta(&"shop_offer_id"))
		assert_true(card.has_meta(&"direct_action_owned"))
		if String(card.get_meta(&"shop_offer_id")) == "offer.0":
			offer_card = card
		else:
			empty_cards.append(card)
	assert_not_null(offer_card)
	assert_eq(empty_cards.size(), 4)
	if offer_card == null:
		return

	assert_null(
		prepare.call(&"_action_button", &"prepare.buy"),
		"exact-offer cards must not masquerade as an action-band Buy button"
	)
	var focus_before := _focus_control_names(prepare)
	assert_eq(focus_before.count(offer_card.name), 1)
	assert_eq(offer_card.theme_type_variation, &"ExpeditionShopCardTier2")
	# The caller keeps its own preview and trait array. Mutating either after the
	# screen has composed must not alter the card's cloned presentation metadata.
	preview.cost = 99
	preview.cost_tier = 5
	preview.trait_ids[0] = &"trait.changed_after_compose"
	preview.star_up_after_purchase = false

	prepare.relocalize(&"en", {
		&"prepare.buy": "Buy",
		&"combat.inspection.none": "None",
		&"error.presentation.action_not_available": (
			"That action is not available right now"
		),
		&"loc.unit_shop_0": "Scout",
		&"loc.trait_fire": "Fire",
		&"tooltip.cost": "Cost",
		&"tooltip.star": "Star",
		&"prepare.panel.units": "Units",
	})
	assert_null(
		prepare.call(&"_action_button", &"prepare.buy"),
		"relocalization must not turn a shop card into a generic Buy action"
	)
	assert_eq(
		(offer_card.get_node(
			"CardContent/IdentityRow/IdentityText/UnitName"
		) as Label).text,
		"Scout"
	)
	assert_eq(
		(offer_card.get_node(
			"CardContent/IdentityRow/IdentityText/PriceTier"
		) as Label).text,
		"Cost 3"
	)
	var price_label := offer_card.get_node(
		"CardContent/IdentityRow/IdentityText/PriceTier"
	) as Label
	assert_eq(price_label.get_meta(&"localization_key"), &"tooltip.cost")
	assert_eq(String(price_label.get_meta(&"accessible_text")), price_label.text)
	assert_eq(
		(offer_card.get_node("CardContent/Traits") as Label).text,
		"Fire"
	)
	assert_eq(
		(offer_card.get_node("CardContent/OwnedAndStarUp") as Label).text,
		"Units 3 · Star"
	)
	var ownership_label := offer_card.get_node(
		"CardContent/OwnedAndStarUp"
	) as Label
	assert_eq(
		int(ownership_label.get_meta(&"star_up_after_purchase_value")),
		1
	)
	assert_eq(
		String(ownership_label.get_meta(&"accessible_text")),
		ownership_label.text
	)
	var en_detail := "Scout\nCost 3\nUnits 3\nFire\nStar"
	assert_eq(offer_card.tooltip_text, en_detail)
	assert_eq(String(offer_card.get_meta(&"accessible_text")), en_detail)
	for empty_card: Button in empty_cards:
		assert_eq(empty_card.text, "None")
		assert_eq(
			StringName(empty_card.get_meta(&"localization_key")),
			&"combat.inspection.none"
		)
		assert_eq(
			String(empty_card.get_meta(&"accessible_text")),
			"None"
		)
		assert_true(empty_card.disabled)
		assert_eq(empty_card.focus_mode, Control.FOCUS_NONE)

	prepare.relocalize(&"zh_TW", {
		&"prepare.buy": "購買",
		&"combat.inspection.none": "無",
		&"error.presentation.action_not_available": "目前無法執行這個操作",
		&"loc.unit_shop_0": "斥候",
		&"loc.trait_fire": "烈焰",
		&"tooltip.cost": "花費",
		&"tooltip.star": "星級",
		&"prepare.panel.units": "單位",
	})
	assert_eq(
		(offer_card.get_node(
			"CardContent/IdentityRow/IdentityText/UnitName"
		) as Label).text,
		"斥候"
	)
	assert_eq(
		(offer_card.get_node(
			"CardContent/IdentityRow/IdentityText/PriceTier"
		) as Label).text,
		"花費 3"
	)
	var zh_detail := "斥候\n花費 3\n單位 3\n烈焰\n星級"
	assert_eq(offer_card.tooltip_text, zh_detail)
	assert_eq(String(offer_card.get_meta(&"accessible_text")), zh_detail)
	assert_eq(
		_focus_control_names(prepare),
		focus_before,
		"locale changes must preserve the authored focus graph order"
	)
	var before_dispatch := session.dispatched_kinds.size()
	offer_card.pressed.emit()
	assert_eq(session.dispatched_kinds.size(), before_dispatch + 1)
	assert_eq(
		int(session.dispatched_kinds.back()),
		RunPresentationIntent.Kind.BUY_UNIT,
		"the direct exact-offer Buy path remains functional after relocalization"
	)
	prepare.refresh_interaction_state()
	for empty_card: Button in empty_cards:
		assert_true(
			empty_card.disabled,
			"refresh must never enable an empty shop placeholder"
		)
		assert_eq(empty_card.focus_mode, Control.FOCUS_NONE)
	var after_offer_dispatch := session.dispatched_kinds.size()
	for empty_card: Button in empty_cards:
		empty_card.pressed.emit()
	assert_eq(
		session.dispatched_kinds.size(),
		after_offer_dispatch,
		"empty placeholders must not dispatch through the exact-offer Buy path"
	)


func test_shop_offer_preview_must_match_canonical_offer_or_fail_closed() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := _prepare_snapshot_with_shop()
	# Each invalid slot exercises a different missing/mismatch dimension. The
	# fifth slot remains valid so exact Buy is proven to survive fail-closed peers.
	snapshot.shop_offer_previews.remove_at(0)
	snapshot.shop_offer_previews[0].offer_id = &"offer.mismatch"
	snapshot.shop_offer_previews[1].unit_def_id = &"unit.mismatch"
	snapshot.shop_offer_previews[2].cost = 999
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self, &"RUN_PREPARE", snapshot, session
	)
	if prepare == null:
		return
	prepare.relocalize(&"en", {
		&"combat.inspection.none": "None",
		&"error.presentation.action_not_available": (
			"That action is not available right now"
		),
	})
	var cards := prepare.find_children("ShopCard*", "Button", true, false)
	assert_eq(cards.size(), 5)
	if cards.size() != 5:
		return
	var valid_count := 0
	var dispatch_before := session.dispatched_kinds.size()
	for node: Node in cards:
		var card := node as Button
		var slot := int(card.get_meta(&"shop_slot_index", -1))
		assert_false(card.has_meta(&"action_id"))
		if slot == 4:
			valid_count += 1
			assert_eq(String(card.get_meta(&"shop_offer_id")), "offer.4")
			assert_false(card.disabled)
			assert_eq(card.focus_mode, Control.FOCUS_ALL)
			card.pressed.emit()
			continue
		assert_eq(card.text, "That action is not available right now")
		assert_eq(
			StringName(card.get_meta(&"localization_key")),
			&"error.presentation.action_not_available"
		)
		assert_eq(String(card.get_meta(&"shop_offer_id")), "")
		assert_eq(
			StringName(card.get_meta(&"typed_data_kind")),
			&"shop_offer_unavailable"
		)
		assert_true(card.disabled)
		assert_eq(card.focus_mode, Control.FOCUS_NONE)
		card.pressed.emit()
	assert_eq(valid_count, 1)
	assert_eq(session.dispatched_kinds.size(), dispatch_before + 1)
	assert_eq(
		int(session.dispatched_kinds.back()),
		RunPresentationIntent.Kind.BUY_UNIT
	)


func test_prepare_shop_five_tiers_and_both_star_results_are_explicit() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := _prepare_snapshot_with_shop()
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self, &"RUN_PREPARE", snapshot, session
	)
	if prepare == null:
		return
	var localized := _shop_test_localized_text(&"en")
	prepare.relocalize(&"en", localized)
	var cards := prepare.find_children("ShopCard*", "Button", true, false)
	assert_eq(cards.size(), 5)
	if cards.size() != 5:
		return
	var saw_true := false
	var saw_false := false
	for node: Node in cards:
		var card := node as Button
		var tier := int(card.get_meta(&"shop_cost_tier", 0))
		assert_true(tier >= 1 and tier <= 5)
		assert_eq(
			card.theme_type_variation,
			StringName("ExpeditionShopCardTier%d" % tier)
		)
		var price := card.get_node(
			"CardContent/IdentityRow/IdentityText/PriceTier"
		) as Label
		assert_eq(
			price.text,
			"Cost 3",
			"authoritative cost tier must be explicit without its border color"
		)
		assert_eq(price.get_meta(&"localization_key"), &"tooltip.cost")
		assert_eq(int(price.get_meta(&"authoritative_cost")), 3)
		assert_eq(int(price.get_meta(&"authoritative_cost_tier")), tier)
		var tier_cues := price.get_node("TierCueShapes") as HBoxContainer
		assert_eq(tier_cues.get_child_count(), tier)
		assert_eq(tier_cues.get_meta(&"non_color_cue"), &"tier-pips")
		var star_up := bool(
			card.get_meta(&"shop_star_up_after_purchase", false)
		)
		var ownership := (
			card.get_node("CardContent/OwnedAndStarUp") as Label
		).text
		var star_cue := (
			card.get_node("CardContent/OwnedAndStarUp/StarUpCueShape")
			as HBoxContainer
		)
		if star_up:
			saw_true = true
			assert_true(ownership.contains("Star"))
			assert_eq(star_cue.get_meta(&"non_color_cue"), &"star-rise")
		else:
			saw_false = true
			assert_false(ownership.contains("Star"))
			assert_eq(star_cue.get_meta(&"non_color_cue"), &"star-flat")
	assert_true(saw_true)
	assert_true(saw_false)


func test_combat_shop_active_and_empty_cards_relocalize_read_only() -> void:
	var playback := Support.playback_fixture(self)
	var session := playback.get("session") as RunPresentationSession
	var snapshot := _snapshot_with_shop(
		Support.CompositionSupport.combat_snapshot(), 1
	)
	snapshot.run_id = &"run.r13.live-playback"
	snapshot.shop_offer_previews[0].cost_tier = 4
	snapshot.shop_offer_previews[0].star_up_after_purchase = false
	var combat := Support.live_run_screen(
		self,
		&"RUN_COMBAT",
		snapshot,
		session,
		playback.get("port") as LiveScreenPlaybackPort
	)
	if combat == null:
		return
	var cards := combat.find_children(
		"CombatShopCardSlot*", "Button", true, false
	)
	assert_eq(cards.size(), 5)
	if cards.size() != 5:
		return
	var active := cards[0] as Button
	assert_eq(active.theme_type_variation, &"ExpeditionShopCardTier4")
	assert_true(active.disabled)
	assert_eq(active.focus_mode, Control.FOCUS_NONE)
	combat.relocalize(&"en", _shop_test_localized_text(&"en"))
	assert_eq(
		(active.get_node(
			"CardContent/IdentityRow/IdentityText/PriceTier"
		) as Label).text,
		"Cost 3"
	)
	assert_false(active.tooltip_text.contains("Star"))
	assert_eq(
		active.get_node(
			"CardContent/OwnedAndStarUp/StarUpCueShape"
		).get_meta(&"non_color_cue"),
		&"star-flat"
	)
	assert_eq(
		String(active.get_meta(&"accessible_text")), active.tooltip_text
	)
	for index: int in range(1, 5):
		var empty := cards[index] as Button
		assert_eq(empty.text, "None")
		assert_eq(
			StringName(empty.get_meta(&"localization_key")),
			&"combat.inspection.none"
		)
		assert_eq(
			String(empty.get_meta(&"accessible_text")),
			"None"
		)
		assert_true(empty.disabled)
		assert_eq(empty.focus_mode, Control.FOCUS_NONE)
	combat.relocalize(&"zh_TW", _shop_test_localized_text(&"zh_TW"))
	assert_eq(
		(active.get_node(
			"CardContent/IdentityRow/IdentityText/PriceTier"
		) as Label).text,
		"花費 3"
	)
	assert_false(active.tooltip_text.contains("星級"))
	for index: int in range(1, 5):
		var empty := cards[index] as Button
		assert_eq(empty.text, "無")
		assert_eq(
			String(empty.get_meta(&"accessible_text")),
			"無"
		)


func test_node_choice_disables_every_shop_card() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := _prepare_snapshot_with_shop()
	var overlay := NodeChoiceOverlaySnapshot.new()
	overlay.choice_set_id = &"choice_set.r14.shop_lock"
	overlay.display_name_key = &"prepare.panel.expedition"
	snapshot.node_choice_overlay = overlay
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self, &"RUN_PREPARE", snapshot, session
	)
	if prepare == null:
		return
	var cards := prepare.find_children("ShopCard*", "Button", true, false)
	assert_eq(cards.size(), 5)
	for node: Node in cards:
		assert_true(
			(node as Button).disabled,
			"node-choice must disable every shop card, not only the first"
		)


func _prepare_snapshot_with_shop(offer_count: int = 5) -> RunPresentationSnapshot:
	return _snapshot_with_shop(
		Support.CompositionSupport.prepare_snapshot(), offer_count
	)


func _snapshot_with_shop(
	snapshot: RunPresentationSnapshot,
	offer_count: int
) -> RunPresentationSnapshot:
	var owner := ReservationOwnerKeyState.create(
		&"run.r14.functional.shop",
		&"node.prepare",
		&"shop",
		&"refresh.1",
		0,
		&"owner.shop"
	)
	var offers: Array[ShopOffer] = []
	for index: int in offer_count:
		offers.append(ShopOffer.new(
			index,
			"offer.%d" % index,
			StringName("unit.shop.%d" % index),
			3,
			1,
			owner
		))
		var preview := ShopOfferPreviewSnapshot.new()
		preview.offer_id = StringName("offer.%d" % index)
		preview.slot_index = index
		preview.unit_def_id = StringName("unit.shop.%d" % index)
		preview.cost = 3
		preview.cost_tier = index + 1
		preview.trait_ids.assign([&"trait.fire"])
		preview.owned_unit_count = index
		preview.star_up_after_purchase = index % 2 == 0
		snapshot.shop_offer_previews.append(preview)
	snapshot.economy = EconomyState.new(10, 9, 0, 0, 0, 1, offers)
	return snapshot


func _shop_test_localized_text(locale: StringName) -> Dictionary:
	if locale == &"zh_TW":
		return {
			&"combat.inspection.none": "無",
			&"error.presentation.action_not_available": "目前無法執行這個操作",
			&"loc.unit_shop_0": "斥候",
			&"loc.trait_fire": "烈焰",
			&"tooltip.cost": "花費",
			&"tooltip.star": "星級",
			&"prepare.panel.units": "單位",
		}
	return {
		&"combat.inspection.none": "None",
		&"error.presentation.action_not_available": (
			"That action is not available right now"
		),
		&"loc.unit_shop_0": "Scout",
		&"loc.trait_fire": "Fire",
		&"tooltip.cost": "Cost",
		&"tooltip.star": "Star",
		&"prepare.panel.units": "Units",
	}


func _focus_control_names(screen: ProductionScreen) -> PackedStringArray:
	var result := PackedStringArray()
	for control: Control in screen.call(&"_ordered_focus_controls"):
		result.append(control.name)
	return result


func _label_texts(root: Control) -> PackedStringArray:
	var result := PackedStringArray()
	for node: Node in root.find_children("*", "Label", true, false):
		result.append((node as Label).text)
	return result


func test_route_preconditions_never_collapse_to_generic_action_not_available() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	session.current_snapshot = Support.CompositionSupport.prepare_snapshot()
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return
	assert_true(Support.press(self, prepare, &"prepare.start"))
	var result: Variant = Support.last_control_result(self, prepare)
	if result == null:
		return
	assert_ne(
		Support.error_code(result),
		ApplicationRoot.ERROR_ACTION_NOT_AVAILABLE,
		"route controls require an exact domain/precondition error"
	)


func test_service_dismantle_and_exit_dispatch_node_service_intents() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := Support.CompositionSupport.prepare_snapshot()
	var service_item_id := "inventory.service.dismantle"
	var service_item := ItemInstanceState.new(
		service_item_id,
		&"equipment.test",
		null,
		U64Bits.one()
	)
	var service_items: Array[ItemInstanceState] = [service_item]
	var inventory_ids: Array[String] = [service_item_id]
	var no_overflow: Array[String] = []
	var roster := snapshot.roster
	snapshot.roster = RosterState.new(
		roster.board,
		roster.bench_unit_instance_ids,
		roster.unit_instances,
		service_items,
		inventory_ids,
		no_overflow,
		roster.active_relic_slots
	)
	var overlay := NodeServiceOverlaySnapshot.new()
	overlay.service_kind = &"dismantle"
	overlay.node_id = &"node.service.r14"
	overlay.choice_receipt_digest = "receipt.digest.r14"
	snapshot.node_service_overlay = overlay
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return

	var composition := Support.composition(prepare)
	var inventory := composition.find_child("InventorySelector", true, false) as ItemList
	assert_not_null(inventory)
	if inventory == null:
		return
	assert_eq(
		inventory.item_count,
		1,
		"dismantle fixture must expose its canonical inventory member"
	)
	if inventory.item_count != 1:
		return
	inventory.select(0)

	assert_true(Support.press(self, prepare, &"service.dismantle"))
	assert_true(
		session.dispatched_kinds.has(
			RunPresentationIntent.Kind.DISMANTLE_WITH_NODE_SERVICE
		),
		"service.dismantle must dispatch DISMANTLE_WITH_NODE_SERVICE"
	)

	assert_true(Support.press(self, prepare, &"service.exit"))
	var last_kind: int = (
		-1
		if session.dispatched_kinds.is_empty()
		else int(session.dispatched_kinds.back())
	)
	assert_eq(
		last_kind,
		RunPresentationIntent.Kind.EXIT_NODE_SERVICE,
		"service.exit must dispatch EXIT_NODE_SERVICE"
	)


func test_choice_ack_dispatches_acknowledge_node_choice_result_intent() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := Support.CompositionSupport.prepare_snapshot()
	var pending_result := NodeChoiceResultSnapshot.new()
	pending_result.node_id = &"node.choice.r14"
	pending_result.choice_set_id = &"choice_set.r14"
	pending_result.choice_id = &"choice.r14.option"
	pending_result.result_key = &"result.r14"
	pending_result.outcome_kind = 0
	pending_result.receipt_digest = "receipt.digest.ack.r14"
	snapshot.pending_node_choice_results.append(pending_result)
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return

	assert_true(Support.press(self, prepare, &"choice.ack"))
	var last_kind: int = (
		-1
		if session.dispatched_kinds.is_empty()
		else int(session.dispatched_kinds.back())
	)
	assert_eq(
		last_kind,
		RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT,
		"choice.ack must dispatch ACKNOWLEDGE_NODE_CHOICE_RESULT"
	)


## T25 review N1：三種 outcome 的落點不同（design :206-209）——APPLY 完成節點後停在
## MAP、REWARD 出口停在 REWARD、DISMANTLE 留在 PREPARE。ack 只由 unacknowledged
## ledger 驅動（design :201-204），因此三個 route 都要能送出它，否則 3 種 outcome
## 有 2 種的 receipt 永遠翻不成 true。
func test_choice_ack_is_reachable_on_the_map_and_reward_routes() -> void:
	var map_session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var map_snapshot := RunPresentationSnapshot.new()
	map_snapshot.run_id = &"run.r14.functional.map.ack"
	map_snapshot.app_phase = &"MAP"
	map_snapshot.manifest_digest = "manifest.r14.functional.map.ack"
	map_snapshot.pending_node_choice_results.append(
		_pending_result("receipt.digest.map.ack", &"result.map.ack")
	)
	map_session.current_snapshot = map_snapshot
	var map_screen := Support.live_run_screen(
		self,
		&"RUN_MAP",
		map_session.current_snapshot,
		map_session
	)
	if map_screen == null:
		return
	assert_true(Support.press(self, map_screen, &"choice.ack"))
	assert_eq(
		_last_ack_digest(map_session),
		"receipt.digest.map.ack",
		"RUN_MAP must acknowledge the receipt it is replaying"
	)

	var reward_session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var reward_snapshot := Support.CompositionSupport.reward_snapshot(
		PendingRewardState.Phase.CHOOSING
	)
	reward_snapshot.pending_node_choice_results.append(
		_pending_result("receipt.digest.reward.ack", &"result.reward.ack")
	)
	reward_session.current_snapshot = reward_snapshot
	var reward_screen := Support.live_run_screen(
		self,
		&"RUN_REWARD",
		reward_session.current_snapshot,
		reward_session
	)
	if reward_screen == null:
		return
	assert_true(Support.press(self, reward_screen, &"choice.ack"))
	assert_eq(
		_last_ack_digest(reward_session),
		"receipt.digest.reward.ack",
		"RUN_REWARD must acknowledge the receipt it is replaying"
	)


## T25 review N2：ledger 有多筆未確認結果時，畫面顯示的文字與 ack 掉的 receipt
## 必須是同一筆（升冪 ledger 的最舊一筆），否則玩家確認的是別的節點的結果。
func test_choice_ack_targets_the_result_that_is_displayed() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	var snapshot := Support.CompositionSupport.prepare_snapshot()
	snapshot.pending_node_choice_results.append(
		_pending_result("receipt.digest.older", &"result.older")
	)
	snapshot.pending_node_choice_results.append(
		_pending_result("receipt.digest.newer", &"result.newer")
	)
	session.current_snapshot = snapshot
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return
	prepare.relocalize(&"zh_TW", {
		&"result.older": "較舊的事件結果",
		&"result.newer": "較新的事件結果",
	})
	var label := prepare.get_node_or_null(
		ProductionScreen.NODE_CHOICE_RESULT_NODE
	) as Label
	assert_not_null(label, "unacknowledged result must have a render surface")
	if label == null:
		return
	assert_true(label.visible)
	assert_eq(label.text, "較舊的事件結果")
	assert_true(Support.press(self, prepare, &"choice.ack"))
	assert_eq(_last_ack_digest(session), "receipt.digest.older")


## 沒有未確認結果時：ack 停用、顯示面收起（design :201「只由 unacknowledged
## committed receipt 顯示 result」）。缺文案的 key 則 fail-soft 顯示鍵名本身。
func test_result_surface_is_hidden_without_a_receipt_and_fails_soft_on_missing_text() -> void:
	var session := Support.CompositionSupport.SpyRunPresentationSession.new()
	session.current_snapshot = Support.CompositionSupport.prepare_snapshot()
	var prepare := Support.live_run_screen(
		self,
		&"RUN_PREPARE",
		session.current_snapshot,
		session
	)
	if prepare == null:
		return
	var label := prepare.get_node_or_null(
		ProductionScreen.NODE_CHOICE_RESULT_NODE
	) as Label
	assert_not_null(label)
	if label == null:
		return
	assert_false(label.visible)
	var ack := Support.button(self, prepare, &"choice.ack")
	assert_not_null(ack)
	if ack != null:
		assert_true(ack.disabled, "ack must be unavailable without a receipt")

	var replayed := Support.CompositionSupport.prepare_snapshot()
	replayed.pending_node_choice_results.append(
		_pending_result("receipt.digest.unlocalized", &"result.without.text")
	)
	session.current_snapshot = replayed
	# 任何一次成功的 dispatch 都會換掉畫面持有的 snapshot，結果面隨之出現。
	assert_true(Support.press(self, prepare, &"prepare.refresh"))
	assert_true(label.visible)
	assert_eq(
		label.text,
		"result.without.text",
		"missing localization must surface the key instead of a blank line"
	)


func _pending_result(
	receipt_digest: String,
	result_key: StringName
) -> NodeChoiceResultSnapshot:
	var pending_result := NodeChoiceResultSnapshot.new()
	pending_result.node_id = &"node.choice.r14"
	pending_result.choice_set_id = &"choice_set.r14"
	pending_result.choice_id = &"choice.r14.option"
	pending_result.result_key = result_key
	pending_result.outcome_kind = 1
	pending_result.receipt_digest = receipt_digest
	return pending_result


func _last_ack_digest(session: Variant) -> String:
	var ack_kind := RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT
	var intents: Array = session.dispatched_intents
	for index: int in range(intents.size() - 1, -1, -1):
		var intent := intents[index] as RunPresentationIntent
		if intent != null and intent.kind == ack_kind:
			return intent.receipt_digest
	return ""
