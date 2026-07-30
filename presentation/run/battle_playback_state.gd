class_name BattlePlaybackState
extends RefCounted

var cursor: int
var speed: StringName = &"x1"
var paused: bool
var transcript_identity: BattleTranscriptIdentity


func deep_clone() -> BattlePlaybackState:
	var clone := BattlePlaybackState.new()
	clone.cursor = cursor
	clone.speed = speed
	clone.paused = paused
	clone.transcript_identity = (
		transcript_identity.deep_clone() if transcript_identity != null else null
	)
	return clone
