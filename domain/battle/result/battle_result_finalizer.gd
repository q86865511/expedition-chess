class_name BattleResultFinalizer
extends RefCounted

var _hash_regex := RegEx.new()
var _stream_hasher := BattleEventStreamHasher.new()
var _result_codec := BattleResultCodecV1.new()

func _init() -> void:
	_hash_regex.compile("^[0-9a-f]{64}$")

func finalize(
	draft: BattleResultRecord,
	events: Array[BattleEvent],
	battle_setup_envelope_digest: StringName
) -> BattleResultFinalizeResult:
	if draft == null:
		return BattleResultFinalizeResult.failure(BattleResultCodecError.INVALID, &"result")
	if _hash_regex.search(String(battle_setup_envelope_digest)) == null:
		return BattleResultFinalizeResult.failure(
			BattleResultCodecError.INVALID, &"battle_setup_envelope_digest"
		)
	var framed := _stream_hasher.framed_bytes(events)
	if not framed.ok:
		return BattleResultFinalizeResult.failure(
			BattleResultCodecError.TRANSCRIPT_INVALID, framed.error.field_path
		)
	if not _terminal_matches(draft, events):
		return BattleResultFinalizeResult.failure(
			BattleResultCodecError.TERMINAL_EVENT_INVALID, &"events"
		)
	var summary := _stream_hasher.summary_hash(draft.battle_setup_hash, events)
	if summary.is_empty():
		return BattleResultFinalizeResult.failure(
			BattleResultCodecError.TRANSCRIPT_INVALID, &"summary_hash"
		)
	var candidate := draft.deep_clone()
	candidate.summary_hash = StringName(summary)
	candidate.result_hash = &""
	var sealed := _result_codec.seal(candidate)
	if not sealed.ok:
		return BattleResultFinalizeResult.new(false, null, null, sealed.error)
	var receipt := BattleResultValidationReceipt.new(
		sealed.record.battle_setup_hash,
		battle_setup_envelope_digest,
		sealed.record.result_hash
	)
	return BattleResultFinalizeResult.success(sealed.record, receipt)

func _terminal_matches(draft: BattleResultRecord, events: Array[BattleEvent]) -> bool:
	if events.is_empty():
		return false
	var finished_count := 0
	for event: BattleEvent in events:
		if event != null and event.type == &"battle_finished":
			finished_count += 1
	if finished_count != 1:
		return false
	var terminal := events.back() as BattleEvent
	if terminal == null or terminal.type != &"battle_finished" \
		or terminal.tick != draft.final_tick \
		or terminal.target_instance_ids != draft.survivor_instance_ids \
		or not terminal.payload is BattleFinishedEventPayload:
		return false
	var payload := terminal.payload as BattleFinishedEventPayload
	return payload.outcome == draft.outcome \
		and payload.expedition_damage == draft.expedition_damage
