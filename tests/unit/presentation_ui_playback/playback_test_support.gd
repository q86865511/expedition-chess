extends RefCounted

const CONTROLLER_PATH := \
	"res://presentation/run/battle_playback_controller.gd"
const ACCUMULATOR_PATH := \
	"res://presentation/run/pending_battle_transcript_accumulator.gd"
const SESSION_PATH := \
	"res://presentation/run/run_presentation_session.gd"
const COORDINATOR_PATH := \
	"res://services/combat/combat_coordinator.gd"


static func load_script(test: GutTest, path: String) -> Script:
	var exists := FileAccess.file_exists(path)
	test.assert_true(exists, "T11 production contract missing: %s" % path)
	if not exists:
		return null
	var resource := load(path)
	test.assert_not_null(resource, "T11 script must load: %s" % path)
	return resource as Script


static func require_methods(
	test: GutTest,
	target: Variant,
	method_names: Array[StringName],
	owner: String
) -> bool:
	for method_name: StringName in method_names:
		var present: bool = target != null and target.has_method(method_name)
		test.assert_true(
			present,
			"%s must implement %s" % [owner, String(method_name)]
		)
		if not present:
			return false
	return true


static func identity(suffix: String = "a") -> BattleTranscriptIdentity:
	var value := BattleTranscriptIdentity.new()
	value.run_id = StringName("run.t11.%s" % suffix)
	value.battle_setup_hash = "setup-%s" % suffix
	value.committed_result_digest = "result-%s" % suffix
	value.resolution_identity = StringName("resolution.t11.%s" % suffix)
	return value


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


static func events(count: int) -> Array[BattleEvent]:
	var result: Array[BattleEvent] = []
	for index: int in range(count):
		var event := BattleEvent.new()
		event.tick = index / 3
		event.sequence = index
		event.type = &"move"
		event.target_instance_ids.assign([
			StringName("target.%05d" % index),
		])
		event.payload = BattleEventPayload.new()
		result.append(event)
	return result


static func event_signatures(source: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in source:
		var event := value as BattleEvent
		if event == null:
			result.append("<invalid>")
			continue
		result.append("%d:%d:%s" % [
			event.tick,
			event.sequence,
			String(event.type),
		])
	return result


static func error_code(result: Variant) -> StringName:
	if result == null:
		return &""
	var error: Variant = result.get("error")
	if error == null:
		return &""
	return StringName(error.get("source_code"))


static func warning_code(result: Variant) -> StringName:
	if result == null:
		return &""
	var warning: Variant = result.get("warning")
	if warning == null:
		return &""
	return StringName(warning.get("source_code"))


static func append_events(
	test: GutTest,
	accumulator: Variant,
	source: Array
) -> bool:
	if not require_methods(
		test,
		accumulator,
		[&"append_events", &"pending_count", &"public_event_count", &"is_revoked"],
		ACCUMULATOR_PATH
	):
		return false
	var appended: Variant = accumulator.call(&"append_events", source)
	test.assert_true(
		bool(appended),
		"precommit accumulator must accept events within canonical event_budget"
	)
	return bool(appended)


static func install_transcript(
	test: GutTest,
	session: RunPresentationSession,
	accumulator: Variant,
	transcript_identity: BattleTranscriptIdentity,
	encoded_byte_count: int
) -> Variant:
	if not require_methods(
		test,
		session,
		[
			&"_accept_committed_transcript",
			&"try_playback",
			&"drain_playback_window",
			&"release_playback",
			&"is_committed_summary_only",
			&"playback_warning",
		],
		SESSION_PATH
	):
		return null
	return session.call(
		&"_accept_committed_transcript",
		accumulator,
		transcript_identity,
		encoded_byte_count
	)
