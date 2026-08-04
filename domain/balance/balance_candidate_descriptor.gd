class_name BalanceCandidateDescriptor
extends RefCounted

const SCHEMA_VERSION: int = 1
const RNG_VERSION: int = 1
const FIXED_RULE_FIELDS: Array[String] = BalanceTuneFieldPolicy.QUALIFIED_FIXED_RULE_FIELDS

var candidate_id: StringName
var content_version: String
var manifest_digest: String
var rng_version: int
var tune_entries: Array[BalanceTuneEntry] = []
var tune_digest: String


func _init(
	p_candidate_id: StringName,
	p_content_version: String,
	p_manifest_digest: String,
	p_rng_version: int,
	p_tune_entries: Array[BalanceTuneEntry],
	p_tune_digest: String = ""
) -> void:
	content_version = p_content_version
	manifest_digest = p_manifest_digest
	rng_version = p_rng_version
	for entry: BalanceTuneEntry in p_tune_entries:
		tune_entries.append(entry.deep_clone() if entry != null else null)
	tune_digest = p_tune_digest if not p_tune_digest.is_empty() else compute_tune_digest()
	candidate_id = p_candidate_id if not p_candidate_id.is_empty() \
		else candidate_id_for_digest(tune_digest)


func deep_clone() -> BalanceCandidateDescriptor:
	return BalanceCandidateDescriptor.new(
		candidate_id, content_version, manifest_digest, rng_version,
		tune_entries, tune_digest
	)


func is_valid() -> bool:
	if candidate_id.is_empty() or content_version.is_empty() \
		or manifest_digest.length() != 64 or rng_version != RNG_VERSION \
		or tune_entries.is_empty() or tune_digest.length() != 64:
		return false
	var paths: Dictionary = {}
	for entry: BalanceTuneEntry in tune_entries:
		if entry == null or not entry.is_valid():
			return false
		var path := String(entry.field_path)
		if paths.has(path) or _is_fixed_rule_path(path):
			return false
		paths[path] = true
	return tune_digest == compute_tune_digest() \
		and candidate_id == candidate_id_for_digest(tune_digest)


func _is_fixed_rule_path(path: String) -> bool:
	return BalanceTuneFieldPolicy.is_fixed_path(path)


static func candidate_id_for_digest(digest: String) -> StringName:
	if digest.length() != 64 or not digest.is_valid_hex_number(false):
		return &""
	return StringName("balance.g2.%s" % digest.left(12).to_lower())


func compute_tune_digest() -> String:
	var ordered: Array[BalanceTuneEntry] = []
	for entry: BalanceTuneEntry in tune_entries:
		if entry != null:
			ordered.append(entry.deep_clone())
	ordered.sort_custom(func(left: BalanceTuneEntry, right: BalanceTuneEntry) -> bool:
		return String(left.field_path) < String(right.field_path)
	)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for entry: BalanceTuneEntry in ordered:
		var bytes := entry.canonical_fragment().to_utf8_buffer()
		if context.update(bytes) != OK:
			return ""
	return context.finish().hex_encode()
