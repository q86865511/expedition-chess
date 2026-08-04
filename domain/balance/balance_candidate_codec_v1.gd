class_name BalanceCandidateCodecV1
extends RefCounted


func encode(value: BalanceCandidateDescriptor) -> String:
	if value == null or not value.is_valid():
		return ""
	var ordered: Array[BalanceTuneEntry] = []
	for entry: BalanceTuneEntry in value.tune_entries:
		ordered.append(entry.deep_clone())
	ordered.sort_custom(func(left: BalanceTuneEntry, right: BalanceTuneEntry) -> bool:
		return String(left.field_path) < String(right.field_path)
	)
	var entries: Array[Dictionary] = []
	for entry: BalanceTuneEntry in ordered:
		entries.append({"path": String(entry.field_path), "value": entry.value_text})
	return JSON.stringify({
		"schema_version": BalanceCandidateDescriptor.SCHEMA_VERSION,
		"candidate_id": String(value.candidate_id),
		"content_version": value.content_version,
		"manifest_digest": value.manifest_digest,
		"rng_version": value.rng_version,
		"tune_entries": entries,
		"tune_digest": value.tune_digest,
	})


func try_decode(text: String) -> BalanceCandidateDescriptor:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return null
	var source := parsed as Dictionary
	if int(source.get("schema_version", 0)) != BalanceCandidateDescriptor.SCHEMA_VERSION \
		or not source.get("tune_entries", null) is Array:
		return null
	var entries: Array[BalanceTuneEntry] = []
	for raw: Variant in source["tune_entries"]:
		if not raw is Dictionary:
			return null
		var item := raw as Dictionary
		entries.append(BalanceTuneEntry.new(
			StringName(str(item.get("path", ""))), str(item.get("value", ""))
		))
	var result := BalanceCandidateDescriptor.new(
		StringName(str(source.get("candidate_id", ""))),
		str(source.get("content_version", "")),
		str(source.get("manifest_digest", "")),
		int(source.get("rng_version", 0)),
		entries,
		str(source.get("tune_digest", ""))
	)
	return result if result.is_valid() else null
