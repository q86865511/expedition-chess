class_name CampMutationExpectation
extends RefCounted

enum Kind { NONE, DECODED_RUN_ID, OPAQUE_FILE_DIGEST }

var kind: Kind
var expected_run_id: String
var expected_committed_file_digest: String


static func run_free() -> CampMutationExpectation:
	return CampMutationExpectation.new(Kind.NONE, "", "")


static func decoded_run(
	run_id: String,
	committed_file_digest: String = ""
) -> CampMutationExpectation:
	return CampMutationExpectation.new(
		Kind.DECODED_RUN_ID, run_id, committed_file_digest
	)


static func opaque_file(
	committed_file_digest: String
) -> CampMutationExpectation:
	return CampMutationExpectation.new(
		Kind.OPAQUE_FILE_DIGEST, "", committed_file_digest
	)


func _init(
	p_kind: Kind,
	p_expected_run_id: String,
	p_expected_committed_file_digest: String
) -> void:
	kind = p_kind
	expected_run_id = p_expected_run_id
	expected_committed_file_digest = p_expected_committed_file_digest
