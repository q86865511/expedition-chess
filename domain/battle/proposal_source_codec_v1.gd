class_name ProposalSourceCodecV1
extends RefCounted

const VERSION: int = 1
const _UNIT_PATTERN: String = "^u_[0-9a-f]{16}$"

var _unit_regex := RegEx.new()
var _stable_ids := StableIdValidator.new()


func _init() -> void:
	_unit_regex.compile(_UNIT_PATTERN)


func player_unit(run_unit_instance_id: String) -> ProposalSourceResult:
	if not _unit_id(run_unit_instance_id):
		return _failure(ProposalSourceError.UNIT_ID_INVALID, &"run_unit_instance_id")
	return validate("u/%s" % run_unit_instance_id)


func commander(commander_id: StringName) -> ProposalSourceResult:
	if not _stable_ids.is_valid(commander_id):
		return _failure(ProposalSourceError.STABLE_ID_INVALID, &"commander_id")
	return validate("c/%s" % String(commander_id))


func relic(slot: int) -> ProposalSourceResult:
	if slot < 0 or slot > 4:
		return _failure(ProposalSourceError.SLOT_INVALID, &"relic_slot")
	return validate("r/%d" % slot)


func trait_source(trait_id: StringName) -> ProposalSourceResult:
	if not _stable_ids.is_valid(trait_id):
		return _failure(ProposalSourceError.STABLE_ID_INVALID, &"trait_id")
	return validate("t/%s" % String(trait_id))


func equipment(owner_run_unit_instance_id: String, slot: int) -> ProposalSourceResult:
	if not _unit_id(owner_run_unit_instance_id):
		return _failure(ProposalSourceError.UNIT_ID_INVALID, &"owner_run_unit_instance_id")
	if slot < 0 or slot > 2:
		return _failure(ProposalSourceError.SLOT_INVALID, &"equipment_slot")
	return validate("eq/%s/%d" % [owner_run_unit_instance_id, slot])


func validate(token: String) -> ProposalSourceResult:
	if not _strict_ascii(token):
		return _failure(ProposalSourceError.TOKEN_INVALID, &"source_instance_or_slot")
	var parts := token.split("/", false)
	if parts.size() == 2 and parts[0] == "u" and _unit_id(parts[1]):
		return ProposalSourceResult.success(token)
	if parts.size() == 2 and parts[0] in ["c", "t"] \
		and _stable_ids.is_valid(StringName(parts[1])):
		return ProposalSourceResult.success(token)
	if parts.size() == 2 and parts[0] == "r" and parts[1] in ["0", "1", "2", "3", "4"]:
		return ProposalSourceResult.success(token)
	if parts.size() == 3 and parts[0] == "eq" \
		and _unit_id(parts[1]) and parts[2] in ["0", "1", "2"]:
		return ProposalSourceResult.success(token)
	return _failure(ProposalSourceError.TOKEN_INVALID, &"source_instance_or_slot")


func _unit_id(value: String) -> bool:
	return _unit_regex.search(value) != null


func _strict_ascii(value: String) -> bool:
	if value.is_empty():
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 0x21 or byte > 0x7e:
			return false
	return true


func _failure(code: StringName, path: StringName) -> ProposalSourceResult:
	return ProposalSourceResult.failure(ProposalSourceError.new(code, path))
