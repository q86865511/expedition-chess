class_name SaveRoot
extends RefCounted

var schema_version: int
var content_version: String
var app_version: String
var rng_version: int
var hash_version: int
var saved_at_utc: String
var profile: ProfileState
var run: RunState

func _init(
	p_schema_version: int,
	p_content_version: String,
	p_app_version: String,
	p_rng_version: int,
	p_hash_version: int,
	p_saved_at_utc: String,
	p_profile: ProfileState,
	p_run: RunState
) -> void:
	schema_version = p_schema_version
	content_version = p_content_version
	app_version = p_app_version
	rng_version = p_rng_version
	hash_version = p_hash_version
	saved_at_utc = p_saved_at_utc
	profile = p_profile.deep_clone()
	run = p_run.deep_clone() if p_run != null else null

func deep_clone() -> SaveRoot:
	return SaveRoot.new(
		schema_version, content_version, app_version, rng_version, hash_version,
		saved_at_utc, profile, run
	)
