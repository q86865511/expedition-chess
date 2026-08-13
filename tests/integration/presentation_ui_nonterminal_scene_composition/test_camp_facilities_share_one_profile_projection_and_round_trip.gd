extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)


func test_camp_facilities_share_one_profile_projection_and_round_trip() -> void:
	if Support.require_script(
		self,
		Support.CAMP_WORLD_SCREEN_PATH,
		"AC-044 CAMP world composition"
	) == null:
		return
	if Support.require_script(
		self,
		Support.CAMP_FACILITY_SCREEN_PATH,
		"AC-044 facility composition"
	) == null:
		return

	var roots: Dictionary = {}
	for route: StringName in Support.CAMP_SCENES:
		var expected_script: String = (
			Support.CAMP_WORLD_SCREEN_PATH
			if route == &"CAMP_WORLD"
			else (
				Support.COLLECTION_SCREEN_PATH
				if route == &"COLLECTION"
				else Support.CAMP_FACILITY_SCREEN_PATH
			)
		)
		var root: Object = Support.instantiate_scene(
			self,
			Support.CAMP_SCENES[route],
			expected_script
		)
		if root == null:
			return
		roots[route] = root

	var registry: LiveScreenLeaseRegistry = LiveScreenLeaseRegistry.new()
	var lease: LiveScreenLease = registry.activate(AppStateMachine.State.CAMP, 1)
	var navigated: Array[StringName] = []
	var navigate: Callable = func(route: StringName) -> AppActionResult:
		navigated.append(route)
		return AppActionResult.success(false)
	var port: LiveScreenNavigationPort = LiveScreenNavigationPort.new(
		lease,
		registry,
		navigate
	)
	var profile: ProfileState = Support.profile_fixture()
	var digests: Array[String] = []

	for route: StringName in Support.CAMP_SCENES:
		var root: Object = roots[route]
		if route == &"COLLECTION":
			assert_eq(
				root.call(&"compose_collection", profile, port, null, {}),
				&""
			)
			continue
		if not Support.require_methods(
			self,
			root,
			[&"compose", &"projection_digest"],
			"AC-044 %s screen" % route
		):
			return
		assert_eq(root.call(&"compose", profile, port), &"")
		var digest: String = String(root.call(&"projection_digest"))
		assert_false(digest.is_empty(), "%s requires a stable projection digest" % route)
		digests.append(digest)

	assert_eq(
		digests,
		[
			digests[0],
			digests[0],
			digests[0],
			digests[0],
			digests[0],
		],
		"all CAMP scenes must derive from the same ProfileState projection"
	)

	var camp: Object = roots[&"CAMP_WORLD"]
	if not Support.require_methods(
		self,
		camp,
		[&"facility_routes", &"open_facility"],
		"AC-044 CAMP hotspots"
	):
		return
	assert_eq(camp.call(&"facility_routes"), Support.EXPECTED_FACILITY_ROUTES)
	for route: StringName in Support.EXPECTED_FACILITY_ROUTES:
		var opened: Variant = camp.call(&"open_facility", route)
		assert_true(bool(opened.get("ok")), "%s hotspot must navigate" % route)
	assert_eq(navigated, Support.EXPECTED_FACILITY_ROUTES)

	var expedition: Object = roots[&"FACILITY_EXPEDITION_GATE"]
	var commander: Object = roots[&"FACILITY_COMMANDER_HALL"]
	var collection: Object = roots[&"COLLECTION"]
	var workshop: Object = roots[&"FACILITY_UNLOCK_WORKSHOP"]
	var challenge: Object = roots[&"FACILITY_CHALLENGE_MONUMENT"]
	var facility_contracts: Array = [
		[expedition, &"expedition_last_commander", &"commander.alpha"],
		[commander, &"commander_ids", [&"commander.alpha"]],
		[workshop, &"workshop_currency", 37],
		[challenge, &"highest_challenge_level", 6],
	]
	for contract: Array in facility_contracts:
		if not Support.require_methods(
			self,
			contract[0],
			[contract[1], &"return_to_camp"],
			"AC-044 facility projection"
		):
			return
		assert_eq(contract[0].call(contract[1]), contract[2])
	assert_true(collection.has_method(&"return_to_camp"))
	var collection_entries := collection.get_node_or_null(
		^"EntrySelector"
	) as ItemList
	assert_not_null(collection_entries)
	if collection_entries != null:
		assert_eq(
			collection_entries.item_count,
			3,
			"dedicated COLLECTION content category must clone discovered and unlocked ids"
		)

	profile.meta_currency = 999
	profile.unlocked_content_ids.append(&"commander.injected")
	assert_eq(workshop.call(&"workshop_currency"), 37)
	assert_eq(commander.call(&"commander_ids"), [&"commander.alpha"])

	var back: Variant = expedition.call(&"return_to_camp")
	assert_true(bool(back.get("ok")))
	assert_eq(navigated[-1], &"CAMP_WORLD")
	registry.activate(AppStateMachine.State.CAMP, 2)
	var before_stale: int = navigated.size()
	var stale: Variant = commander.call(&"return_to_camp")
	assert_false(bool(stale.get("ok")))
	assert_eq(Support.error_code(stale), &"SCREEN_NOT_ACTIVE")
	assert_eq(navigated.size(), before_stale)


func test_camp_unlocks_challenge_one_after_clearing_challenge_zero() -> void:
	var camp: Object = Support.instantiate_scene(
		self,
		Support.CAMP_SCENES[&"CAMP_WORLD"],
		Support.CAMP_WORLD_SCREEN_PATH
	)
	if camp == null:
		return
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.CAMP, 1)
	var port := LiveScreenNavigationPort.new(
		lease,
		registry,
		func(_route: StringName) -> AppActionResult:
			return AppActionResult.success(false)
	)
	var profile := Support.profile_fixture()
	profile.highest_challenge_level = 0
	var records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 0),
	]
	profile.commander_challenge_records = records

	assert_eq(camp.call(&"compose", profile, port), &"")
	var challenge := camp.find_child("ChallengeSelector", true, false) as SpinBox
	assert_not_null(challenge)
	if challenge == null:
		return
	assert_eq(
		challenge.max_value,
		1.0,
		"clearing challenge 0 must make challenge 1 selectable"
	)
	challenge.value = 1.0
	challenge.value_changed.emit(1.0)
	var request: StartExpeditionRequest = camp.call(
		&"selected_expedition_request"
	) as StartExpeditionRequest
	assert_not_null(request)
	if request != null:
		assert_eq(request.challenge_level, 1)
