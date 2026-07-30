extends GutTest

const Support = preload("res://tests/unit/presentation_ui_app_lifecycle/lifecycle_test_support.gd")
const TRANSACTION_PATH := "res://domain/run/camp/camp_mutation_transaction.gd"
const CONTROLLER_PATH := "res://domain/run/camp/camp_controller.gd"
const REPOSITORY_PATH := "res://services/save/save_repository.gd"


func test_all_camp_writers_share_atomic_repository_transaction() -> void:
	var transaction_source := Support.source(TRANSACTION_PATH)
	var controller_source := Support.source(CONTROLLER_PATH)
	var repository_source := Support.source(REPOSITORY_PATH)

	assert_false(
		transaction_source.is_empty(),
		"all Camp writers require one repository-owned CampMutationTransaction"
	)
	assert_true(
		transaction_source.contains("class_name CampMutationTransaction")
			and transaction_source.contains("func execute("),
		"CampMutationTransaction must expose one typed execute boundary"
	)
	for marker: String in [
		"_claim_operation_if_epoch",
		"_load_while_owned",
		"_save_while_owned",
		"_committed_file_digest",
		"repository_identity",
		"operation_epoch",
	]:
		assert_true(
			transaction_source.contains(marker)
				or repository_source.contains(marker),
			"ownership/CAS sequence must include %s" % marker
		)
	assert_false(
		transaction_source.contains("await "),
		"Camp mutation ownership may not yield between fresh-read and save"
	)

	assert_true(
		controller_source.contains("CampMutationTransaction"),
		"CampController must delegate every writer to the shared transaction"
	)
	for writer_name: String in [
		"dispatch(",
		"dispatch_start_expedition(",
		"dispatch_discard_active_run(",
	]:
		var body := _function_body(controller_source, writer_name)
		assert_false(body.is_empty(), "missing Camp writer: %s" % writer_name)
		assert_true(
			body.contains("CampMutationTransaction") or body.contains("_mutation_transaction"),
			"%s must consume the shared transaction" % writer_name
		)
		assert_false(
			body.contains("_save_repository.load(")
				or body.contains("_save_repository.save("),
			"%s must not split freshness across public load/save calls" % writer_name
		)

	assert_true(
		transaction_source.contains("TRANSACTION_BUSY")
			or transaction_source.contains("OPERATION_BUSY"),
		"a competing Camp writer must receive a named busy/stale rejection"
	)


func _function_body(source_text: String, signature_fragment: String) -> String:
	var start := source_text.find("func %s" % signature_fragment)
	if start < 0:
		return ""
	var next := source_text.find("\nfunc ", start + 1)
	return source_text.substr(start) if next < 0 else source_text.substr(start, next - start)
