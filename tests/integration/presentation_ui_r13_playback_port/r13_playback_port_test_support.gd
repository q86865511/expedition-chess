extends RefCounted

const PORT_SCRIPT_PATH := \
	"res://presentation/screens/live_screen_playback_port.gd"
const COMBAT_SCENE_PATH := \
	"res://scenes/production/run_combat.tscn"
const COMBAT_SCREEN_SCRIPT_PATH := \
	"res://presentation/screens/run_combat_screen.gd"


class SaveSpySession:
	extends RunPresentationSession

	var dispatch_count: int = 0
	var committed_snapshot := RunPresentationSnapshot.new()

	func _init() -> void:
		committed_snapshot.run_id = &"run.r13.live-playback"
		committed_snapshot.app_phase = &"COMBAT"
		committed_snapshot.manifest_digest = "save.digest.r13.live-playback"

	func dispatch(_intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		return RunPresentationResult.failure(
			DiagnosticError.new(
				&"UNEXPECTED_GAMEPLAY_DISPATCH",
				&"error.presentation.unexpected_gameplay_dispatch"
			)
		)

	func snapshot() -> RunPresentationSnapshot:
		return committed_snapshot.deep_clone()


static func identity() -> BattleTranscriptIdentity:
	var value := BattleTranscriptIdentity.new()
	value.run_id = &"run.r13.live-playback"
	value.battle_setup_hash = (
		"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
		+ "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	)
	value.committed_result_digest = "result.digest.r13.live-playback"
	value.resolution_identity = &"resolution.r13.live-playback"
	return value


static func events(count: int) -> Array[BattleEvent]:
	var result: Array[BattleEvent] = []
	for index: int in range(count):
		var event := BattleEvent.new()
		event.tick = index
		event.sequence = index
		event.type = &"damage"
		event.target_instance_ids.assign([&"u_0000000000000001"])
		var payload := DamageEventPayload.new()
		payload.damage_type = &"physical"
		payload.raw_amount = 20 + index
		payload.post_resistance_amount = 20 + index
		payload.health_damage = 20 + index
		payload.health_after = 200 - index
		event.payload = payload
		result.append(event)
	return result


static func install_transcript(
	test: GutTest,
	session: Variant,
	source: Array[BattleEvent],
	transcript_identity: BattleTranscriptIdentity
) -> void:
	var accumulator := PendingBattleTranscriptAccumulator.new(source.size())
	test.assert_true(accumulator.append_events(source))
	var installed: Variant = session.call(
		&"_accept_committed_transcript",
		accumulator,
		transcript_identity,
		accumulator.encoded_byte_count()
	)
	test.assert_not_null(installed)
	if installed != null:
		test.assert_true(bool(installed.get("ok")))
	test.assert_true(accumulator.is_revoked())
	test.assert_eq(accumulator.pending_count(), 0)


static func require_port_script(test: GutTest) -> Script:
	var exists := FileAccess.file_exists(PORT_SCRIPT_PATH)
	test.assert_true(
		exists,
		"R13-B01 requires a lease-bound LiveScreenPlaybackPort"
	)
	if not exists:
		return null
	var script := load(PORT_SCRIPT_PATH) as Script
	test.assert_not_null(script)
	return script


static func make_port(
	test: GutTest,
	script: Script,
	lease: LiveScreenLease,
	registry: LiveScreenLeaseRegistry,
	session: RunPresentationSession
) -> Variant:
	if script == null:
		return null
	var port: Variant = script.new(lease, registry, session)
	test.assert_not_null(port)
	for method_name: StringName in [
		&"try_playback",
		&"set_speed",
		&"set_paused",
		&"drain_window",
	]:
		test.assert_true(
			port != null and port.has_method(method_name),
			"live playback port requires typed method %s" % String(method_name)
		)
		if port == null or not port.has_method(method_name):
			return null
	return port


static func error_code(result: Variant) -> StringName:
	if result == null:
		return &""
	var error: Variant = result.get("error")
	return (
		StringName(error.get("source_code"))
		if error != null
		else &""
	)


static func state_fingerprint(state: BattlePlaybackState) -> String:
	if state == null:
		return ""
	var identity_value: BattleTranscriptIdentity = state.transcript_identity
	return "%d|%s|%s|%s|%s|%s" % [
		state.cursor,
		String(state.speed),
		str(state.paused),
		String(identity_value.run_id) if identity_value != null else "",
		identity_value.committed_result_digest if identity_value != null else "",
		String(identity_value.resolution_identity) if identity_value != null else "",
	]


static func snapshot_fingerprint(snapshot: RunPresentationSnapshot) -> String:
	if snapshot == null:
		return ""
	return "%s|%s|%s" % [
		String(snapshot.run_id),
		String(snapshot.app_phase),
		snapshot.manifest_digest,
	]


static func same_identity(
	left: BattleTranscriptIdentity,
	right: BattleTranscriptIdentity
) -> bool:
	return (
		left != null
		and right != null
		and left.run_id == right.run_id
		and left.battle_setup_hash == right.battle_setup_hash
		and left.committed_result_digest == right.committed_result_digest
		and left.resolution_identity == right.resolution_identity
	)


static func event_hash(source: Array) -> String:
	var typed_events: Array[BattleEvent] = []
	for value: Variant in source:
		var event := value as BattleEvent
		if event == null:
			return ""
		typed_events.append(event.deep_clone())
	var encoded := BattleEventStreamHasher.new().framed_bytes(typed_events)
	if not encoded.ok:
		return ""
	var context := HashingContext.new()
	if (
		context.start(HashingContext.HASH_SHA256) != OK
		or context.update(encoded.canonical_bytes) != OK
	):
		return ""
	return context.finish().hex_encode()


static func combat_composition(test: GutTest) -> Object:
	var packed := load(COMBAT_SCENE_PATH) as PackedScene
	test.assert_not_null(packed)
	if packed == null:
		return null
	var root := packed.instantiate()
	test.autofree(root)
	var composition := root.get_node_or_null("Composition")
	test.assert_not_null(composition)
	if composition == null:
		return null
	var script := composition.get_script() as Script
	test.assert_not_null(script)
	if script != null:
		test.assert_eq(script.resource_path, COMBAT_SCREEN_SCRIPT_PATH)
	return composition
