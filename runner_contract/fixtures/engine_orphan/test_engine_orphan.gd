extends GutTest

func test_runner_contract_engine_orphan() -> void:
	var intentionally_leaked_node := Node.new()
	assert_not_null(intentionally_leaked_node)
