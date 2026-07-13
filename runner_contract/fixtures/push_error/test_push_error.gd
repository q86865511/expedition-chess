extends GutTest

func test_runner_contract_push_error() -> void:
	push_error("intentional runner-contract push_error")
	assert_true(true)
