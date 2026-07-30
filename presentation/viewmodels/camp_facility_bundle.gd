class_name CampFacilityBundle
extends RefCounted

## Clone-only projection shared by every formal CAMP scene.  Screens receive the
## same ProfileState value but never retain the caller's mutable domain object.

var _projection_digest: String
var _last_commander_id: StringName
var _commander_ids: Array[StringName] = []
var _discovered_ids: Array[StringName] = []
var _workshop_currency: int
var _highest_challenge_level: int


func _init(profile: ProfileState) -> void:
	if profile == null:
		_projection_digest = _digest_parts(["profile:null"])
		return
	var snapshot: ProfileState = profile.deep_clone()
	var view_model := CampViewModel.new(snapshot)
	var last_selection := view_model.expedition_gate_last_selection()
	_last_commander_id = (
		last_selection.commander_id
		if last_selection != null
		else &""
	)
	_commander_ids.assign(
		view_model.commander_hall_unlocked_commander_ids()
	)
	_discovered_ids.assign(snapshot.discovered_content_ids)
	_workshop_currency = view_model.unlock_workshop_currency()
	_highest_challenge_level = (
		view_model.challenge_monument_highest_challenge_level()
	)
	_projection_digest = _profile_digest(snapshot)


func projection_digest() -> String:
	return _projection_digest


func expedition_last_commander() -> StringName:
	return _last_commander_id


func commander_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_commander_ids)
	return result


func discovered_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_discovered_ids)
	return result


func workshop_currency() -> int:
	return _workshop_currency


func highest_challenge_level() -> int:
	return _highest_challenge_level


func _profile_digest(profile: ProfileState) -> String:
	var parts: Array[String] = [
		"profile=%s" % profile.profile_id,
		"serial=%s" % (
			profile.next_run_serial.to_hex()
			if profile.next_run_serial != null
			else ""
		),
		"currency=%d" % profile.meta_currency,
		"highest=%d" % profile.highest_challenge_level,
		"settings=%s" % String(profile.settings_ref),
	]
	for content_id: StringName in profile.unlocked_content_ids:
		parts.append("unlocked=%s" % String(content_id))
	for content_id: StringName in profile.discovered_content_ids:
		parts.append("discovered=%s" % String(content_id))
	if profile.last_selection != null:
		parts.append(
			"last=%s:%d" % [
				String(profile.last_selection.commander_id),
				profile.last_selection.challenge_level,
			]
		)
	for record: CommanderChallengeRecordState in (
		profile.commander_challenge_records
	):
		parts.append(
			"challenge=%s:%d" % [
				String(record.commander_id),
				record.highest_cleared_level,
			]
		)
	return _digest_parts(parts)


func _digest_parts(parts: Array[String]) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("\n".join(parts).to_utf8_buffer())
	return context.finish().hex_encode()
