extends RefCounted

const SESSION_SPEED_METHOD: StringName = &"set_playback_speed"


class SaveSpySession:
	extends RunPresentationSession

	var dispatch_count: int = 0
	var committed_snapshot := RunPresentationSnapshot.new()

	func _init() -> void:
		committed_snapshot.run_id = &"run.r12.playback"
		committed_snapshot.app_phase = &"COMBAT"
		committed_snapshot.manifest_digest = "save.digest.before.invalid.speed"

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
	value.run_id = &"run.r12.playback"
	value.battle_setup_hash = (
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
		+ "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	)
	value.committed_result_digest = "result.digest.r12.playback"
	value.resolution_identity = &"resolution.r12.playback"
	return value


static func events(count: int) -> Array[BattleEvent]:
	var result: Array[BattleEvent] = []
	for index: int in range(count):
		var event := BattleEvent.new()
		event.tick = index
		event.sequence = index
		event.type = &"damage"
		event.target_instance_ids.assign([
			&"u_0000000000000001",
		])
		var payload := DamageEventPayload.new()
		payload.damage_type = &"physical"
		payload.raw_amount = 10 + index
		payload.post_resistance_amount = 10 + index
		payload.health_damage = 10 + index
		payload.health_after = 100 - index
		event.payload = payload
		result.append(event)
	return result


static func install_transcript(
	test: GutTest,
	session: Variant,
	source: Array[BattleEvent],
	transcript_identity: BattleTranscriptIdentity
) -> PendingBattleTranscriptAccumulator:
	var accumulator := PendingBattleTranscriptAccumulator.new(source.size())
	test.assert_true(
		accumulator.append_events(source),
		"R12 fixture must remain inside the canonical event budget"
	)
	var encoded_byte_count: int = accumulator.encoded_byte_count()
	test.assert_gt(encoded_byte_count, 0)
	var installed: Variant = session.call(
		&"_accept_committed_transcript",
		accumulator,
		transcript_identity,
		encoded_byte_count
	)
	test.assert_not_null(installed)
	if installed != null:
		test.assert_true(bool(installed.get("ok")))
	return accumulator


static func require_session_speed_api(
	test: GutTest,
	session: Variant
) -> bool:
	var present: bool = (
		session != null
		and session.has_method(SESSION_SPEED_METHOD)
	)
	test.assert_true(
		present,
		(
			"R12-B01 requires a session-mediated typed playback speed API; "
			+ "UI must not receive the private BattlePlaybackController"
		)
	)
	return present


static func error_code(result: Variant) -> StringName:
	if result == null:
		return &""
	var error: Variant = result.get("error")
	if error == null:
		return &""
	return StringName(error.get("source_code"))


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


static func snapshot_fingerprint(snapshot: RunPresentationSnapshot) -> String:
	if snapshot == null:
		return ""
	return "%s|%s|%s" % [
		String(snapshot.run_id),
		String(snapshot.app_phase),
		snapshot.manifest_digest,
	]
