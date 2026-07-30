extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_route_security/"
	+ "r14_route_security_test_support.gd"
)


func test_manual_and_foreign_draft_copies_are_rejected() -> void:
	var manual_fixture := Support.intent_fixture()
	var manual_port := manual_fixture.get("port") as LiveScreenIntentPort
	assert_eq(
		Support.run_error_code(manual_port.confirm(ConfirmationDraft.new())),
		LiveScreenIntentPort.CONFIRMATION_DRAFT_INVALID
	)

	var copy_fixture := Support.intent_fixture()
	var copy_port := copy_fixture.get("port") as LiveScreenIntentPort
	var issued := copy_port.begin_confirmation(Support.enter_node_intent())
	assert_true(issued.ok)
	var foreign_copy := issued.draft.deep_clone()
	assert_eq(
		Support.run_error_code(copy_port.confirm(foreign_copy)),
		LiveScreenIntentPort.CONFIRMATION_DRAFT_INVALID,
		"only the exact issuer-recorded draft object may resolve"
	)


func test_payload_and_digest_tampering_are_rejected() -> void:
	var payload_fixture := Support.intent_fixture()
	var payload_port := payload_fixture.get("port") as LiveScreenIntentPort
	var payload_result := payload_port.begin_confirmation(
		Support.enter_node_intent("elite.node")
	)
	var exposed_intent := payload_result.draft.get("_intent") as RunPresentationIntent
	if exposed_intent != null:
		exposed_intent.target_node_id = "forged.node"
	assert_eq(
		Support.run_error_code(payload_port.confirm(payload_result.draft)),
		LiveScreenIntentPort.CONFIRMATION_DRAFT_INVALID
	)

	var digest_fixture := Support.intent_fixture()
	var digest_port := digest_fixture.get("port") as LiveScreenIntentPort
	var digest_result := digest_port.begin_confirmation(
		Support.enter_node_intent("elite.node")
	)
	digest_result.draft.payload_digest = "forged.digest"
	assert_eq(
		Support.run_error_code(digest_port.confirm(digest_result.draft)),
		LiveScreenIntentPort.CONFIRMATION_DRAFT_INVALID
	)


func test_confirm_dispatches_authoritative_issued_clone_and_replay_is_rejected() -> void:
	var fixture := Support.intent_fixture()
	var port := fixture.get("port") as LiveScreenIntentPort
	var session := fixture.get("session") as Support.RecordingSession
	var issued := port.begin_confirmation(
		Support.enter_node_intent("authoritative.node")
	)
	assert_true(issued.ok)
	var result := port.confirm(issued.draft)
	assert_true(result.ok)
	assert_eq(session.dispatched.size(), 1)
	if session.dispatched.size() == 1:
		assert_eq(session.dispatched[0].target_node_id, "authoritative.node")
	assert_eq(
		Support.run_error_code(port.confirm(issued.draft)),
		LiveScreenIntentPort.CONFIRMATION_ALREADY_RESOLVED
	)
