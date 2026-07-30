class_name ProductionLiveScreenContext
extends RefCounted

var route_kind: StringName
var snapshot: RefCounted
var profile: ProfileState
var action_port: ProductionScreenActionPort
var navigation_port: LiveScreenNavigationPort
var intent_port: LiveScreenIntentPort
var playback_port: LiveScreenPlaybackPort
var inspection_port: LiveScreenInspectionPort
var collection_projection: CollectionBrowserSnapshot
## Fail-closed diagnostic: set when the constructor received a non-null
## snapshot of a type _clone_snapshot() does not recognize, so a newly added
## snapshot type surfaces as a queryable failure instead of silently
## collapsing to the same null as "no snapshot was needed".
var snapshot_type_error: StringName = &""


func _init(
	p_route_kind: StringName = &"",
	p_snapshot: RefCounted = null,
	p_profile: ProfileState = null,
	p_action_port: ProductionScreenActionPort = null,
	p_navigation_port: LiveScreenNavigationPort = null,
	p_intent_port: LiveScreenIntentPort = null,
	p_playback_port: LiveScreenPlaybackPort = null,
	p_inspection_port: LiveScreenInspectionPort = null,
	p_collection_projection: CollectionBrowserSnapshot = null
) -> void:
	route_kind = p_route_kind
	snapshot = _clone_snapshot(p_snapshot)
	profile = p_profile.deep_clone() if p_profile != null else null
	action_port = p_action_port
	navigation_port = p_navigation_port
	intent_port = p_intent_port
	playback_port = p_playback_port
	inspection_port = p_inspection_port
	collection_projection = (
		p_collection_projection.deep_clone()
		if p_collection_projection != null
		else null
	)


func snapshot_clone() -> RefCounted:
	return _clone_snapshot(snapshot)


func profile_clone() -> ProfileState:
	return profile.deep_clone() if profile != null else null


func collection_projection_clone() -> CollectionBrowserSnapshot:
	return (
		collection_projection.deep_clone()
		if collection_projection != null
		else null
	)


func _clone_snapshot(source: RefCounted) -> RefCounted:
	if source == null:
		return null
	if source is RunPresentationSnapshot:
		return (source as RunPresentationSnapshot).deep_clone()
	if source is ResultsPresentationSnapshot:
		return (source as ResultsPresentationSnapshot).deep_clone()
	if source is MainMenuSnapshot:
		return (source as MainMenuSnapshot).deep_clone()
	if source is SettingsSnapshot:
		return (source as SettingsSnapshot).deep_clone()
	snapshot_type_error = StringName(
		"PRODUCTION_LIVE_SCREEN_CONTEXT_SNAPSHOT_TYPE_UNKNOWN:%s" % source.get_class()
	)
	return null
