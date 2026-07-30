class_name PendingBattleTranscriptAccumulator
extends RefCounted

var _event_budget: int
var _events: Array[BattleEvent] = []
var _revoked: bool = false


func _init(p_event_budget: int = 0) -> void:
	_event_budget = maxi(p_event_budget, 0)


func append_events(source: Array) -> bool:
	if _revoked or source.size() > _event_budget - _events.size():
		return false
	for value: Variant in source:
		if not value is BattleEvent:
			return false
	for value: Variant in source:
		var event := value as BattleEvent
		_events.append(event.deep_clone())
	return true


func pending_count() -> int:
	return _events.size()


## Precommit transcript data has no legal public consumer.
func public_event_count() -> int:
	return 0


func is_revoked() -> bool:
	return _revoked


func event_budget() -> int:
	return _event_budget


func encoded_byte_count() -> int:
	if _revoked:
		return -1
	var encoded := BattleEventStreamHasher.new().framed_bytes(_events)
	return encoded.canonical_bytes.size() if encoded.ok else -1


## Internal commit-boundary ownership transfer. The returned array is the exact
## storage previously owned here; this object clears and revokes itself first.
func _seal_and_transfer() -> Array[BattleEvent]:
	if _revoked:
		return []
	var transferred: Array[BattleEvent] = _events
	_events = []
	_revoked = true
	return transferred


func discard_on_save_failure() -> void:
	_events.clear()
	_revoked = true
