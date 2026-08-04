class_name BalanceTuneInventory
extends RefCounted

const PINNED_PRODUCTION_CANDIDATE_PATH: String = (
	"res://application/balance/production_balance_candidate.json"
)
const PINNED_PRODUCTION_CANDIDATE_ID: StringName = &"balance.g2.7d47fada8091"
const PINNED_PRODUCTION_TUNE_DIGEST: String = (
	"7d47fada8091a79a68a2c50a4d63c5d57e0752d0bac7776b30230717a6f8dea4"
)


static func collect() -> Array[BalanceTuneEntry]:
	return BalanceTuneSourceScanner.collect()


static func production_candidate(
	manifest_digest: String,
	content_version: String
) -> BalanceCandidateDescriptor:
	# Imported PCK resources do not expose their original `.tres` source text.
	# Only the explicitly-featured provisional RC may use the sealed payload;
	# source/test builds must continue to fail closed through the scanner.
	if OS.has_feature("provisional_rc"):
		return _load_pinned_candidate(manifest_digest, content_version)
	var scan := BalanceTuneSourceScanner.scan()
	var tune_entries: Array[BalanceTuneEntry] = []
	if not scan.ok:
		return _invalid_candidate(content_version, manifest_digest)
	if not scan.entries.is_empty():
		tune_entries.assign(scan.entries)
		return BalanceCandidateDescriptor.new(
			&"", content_version, manifest_digest,
			BalanceCandidateDescriptor.RNG_VERSION,
			tune_entries
		)
	return _invalid_candidate(content_version, manifest_digest)


static func _load_pinned_candidate(
	manifest_digest: String,
	content_version: String
) -> BalanceCandidateDescriptor:
	if not FileAccess.file_exists(PINNED_PRODUCTION_CANDIDATE_PATH):
		return _invalid_candidate(content_version, manifest_digest)
	var candidate := BalanceCandidateCodecV1.new().try_decode(
		FileAccess.get_file_as_string(PINNED_PRODUCTION_CANDIDATE_PATH)
	)
	if candidate == null or candidate.manifest_digest != manifest_digest \
		or candidate.content_version != content_version \
		or candidate.candidate_id != PINNED_PRODUCTION_CANDIDATE_ID \
		or candidate.tune_digest != PINNED_PRODUCTION_TUNE_DIGEST:
		return _invalid_candidate(content_version, manifest_digest)
	return candidate


static func _invalid_candidate(
	content_version: String,
	manifest_digest: String
) -> BalanceCandidateDescriptor:
	return BalanceCandidateDescriptor.new(
		&"", content_version, manifest_digest,
		BalanceCandidateDescriptor.RNG_VERSION,
		[] as Array[BalanceTuneEntry]
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
