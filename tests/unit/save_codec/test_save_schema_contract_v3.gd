extends GutTest

## T03 (specs/meta-progression/tasks.md): ProfileState/RunState gain three new
## fields (last_selection, commander_challenge_records, RunState.discovered_content_ids)
## G2 content-production adds codec/catalog identity and pending choice wire state,
## so the current schema advances once more to 4.

func test_current_schema_version_is_four() -> void:
	assert_eq(
		SaveSchemaContract.CURRENT, 4,
		"G2 content-production requires SaveSchemaContract.CURRENT=4"
	)
