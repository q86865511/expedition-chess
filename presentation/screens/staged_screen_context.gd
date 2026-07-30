class_name StagedScreenContext
extends RefCounted

var route_kind: StringName
var snapshot: RefCounted
var profile: ProfileState
var locale: StringName
var localized_text: Dictionary[StringName, String] = {}


func _init(
	p_route_kind: StringName = &"",
	p_snapshot: RefCounted = null,
	p_profile: ProfileState = null,
	p_locale: StringName = &"zh_TW",
	p_localized_text: Dictionary = {}
) -> void:
	route_kind = p_route_kind
	snapshot = _clone_snapshot(p_snapshot)
	profile = p_profile.deep_clone() if p_profile != null else null
	locale = p_locale
	for key: Variant in p_localized_text.keys():
		localized_text[StringName(key)] = String(p_localized_text[key])


func snapshot_clone() -> RefCounted:
	return _clone_snapshot(snapshot)


func profile_clone() -> ProfileState:
	return profile.deep_clone() if profile != null else null


func resolve_text(key: StringName) -> String:
	return localized_text.get(key, String(key))


func _clone_snapshot(source: RefCounted) -> RefCounted:
	if source is RunPresentationSnapshot:
		return (source as RunPresentationSnapshot).deep_clone()
	if source is ResultsPresentationSnapshot:
		return (source as ResultsPresentationSnapshot).deep_clone()
	if source is MainMenuSnapshot:
		return (source as MainMenuSnapshot).deep_clone()
	if source is SettingsSnapshot:
		return (source as SettingsSnapshot).deep_clone()
	return null
