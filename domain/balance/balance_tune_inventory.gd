class_name BalanceTuneInventory
extends RefCounted


static func collect() -> Array[BalanceTuneEntry]:
	return BalanceTuneSourceScanner.collect()


static func production_candidate(
	manifest_digest: String,
	content_version: String
) -> BalanceCandidateDescriptor:
	var scan := BalanceTuneSourceScanner.scan()
	return BalanceCandidateDescriptor.new(
		&"", content_version, manifest_digest,
		BalanceCandidateDescriptor.RNG_VERSION,
		scan.entries if scan.ok else [] as Array[BalanceTuneEntry]
	)


static func archive_candidate(
	candidate: BalanceCandidateDescriptor,
	root: String = "res://specs/balance-playtest/candidates"
) -> StringName:
	if candidate == null or not candidate.is_valid():
		return &"BALANCE_CANDIDATE_INVALID"
	var absolute_root := ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
		return &"BALANCE_CANDIDATE_ARCHIVE_DIRECTORY_FAILED"
	var path := root.path_join("%s.json" % String(candidate.candidate_id))
	var codec := BalanceCandidateCodecV1.new()
	var encoded := codec.encode(candidate)
	if encoded.is_empty():
		return &"BALANCE_CANDIDATE_ENCODE_FAILED"
	if FileAccess.file_exists(path):
		var existing_text := FileAccess.get_file_as_string(path)
		if existing_text == encoded:
			return &""
		var parser := JSON.new()
		if parser.parse(existing_text) != OK:
			return &"BALANCE_CANDIDATE_ARCHIVE_CONFLICT"
		var existing := codec.try_decode(existing_text)
		if existing == null or existing.candidate_id != candidate.candidate_id \
			or existing.tune_digest != candidate.tune_digest \
			or existing.manifest_digest == candidate.manifest_digest:
			return &"BALANCE_CANDIDATE_ARCHIVE_CONFLICT"
		return _archive_manifest_revision(candidate, root, encoded)
	return _write_new_archive(path, encoded)


static func _archive_manifest_revision(
	candidate: BalanceCandidateDescriptor, root: String, encoded: String
) -> StringName:
	var revision_root := root.path_join("revisions").path_join(
		String(candidate.candidate_id)
	)
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(revision_root)
	) != OK:
		return &"BALANCE_CANDIDATE_ARCHIVE_DIRECTORY_FAILED"
	var revision_path := revision_root.path_join(
		"%s.json" % candidate.manifest_digest
	)
	if FileAccess.file_exists(revision_path):
		return &"" if FileAccess.get_file_as_string(revision_path) == encoded \
			else &"BALANCE_CANDIDATE_ARCHIVE_CONFLICT"
	return _write_new_archive(revision_path, encoded)


static func _write_new_archive(path: String, encoded: String) -> StringName:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return &"BALANCE_CANDIDATE_ARCHIVE_WRITE_FAILED"
	file.store_string(encoded)
	file.close()
	return &""
