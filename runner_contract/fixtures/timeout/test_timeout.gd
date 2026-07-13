extends GutTest

func test_runner_contract_timeout() -> void:
	await get_tree().create_timer(60.0).timeout
	assert_true(true)
