class_name BattleEventWindow
extends RefCounted

var identity: BattleTranscriptIdentity
var events: Array = []
var exhausted: bool


func deep_clone() -> BattleEventWindow:
	var clone := BattleEventWindow.new()
	clone.identity = identity.deep_clone() if identity != null else null
	clone.events = events.duplicate(true)
	clone.exhausted = exhausted
	return clone
