extends GutTest

func test_runner_contract_assertion_failure() -> void:
	assert_true(false, "intentional runner-contract assertion failure")
