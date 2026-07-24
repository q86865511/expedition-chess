extends GutTest

## T03 (specs/meta-progression/tasks.md): ProfileState/RunState gain three new
## fields (last_selection, commander_challenge_records, RunState.discovered_content_ids)
## which are new wire fields -- design.md SS2 requires SaveSchemaContract.CURRENT to
## bump from 2 to 3 to mark the wire format change.

func test_current_schema_version_is_three() -> void:
	assert_eq(
		SaveSchemaContract.CURRENT, 3,
		"S5 meta-progression adds new ProfileState/RunState wire fields; " +
		"design.md SS2 requires SaveSchemaContract.CURRENT to bump 2->3"
	)
