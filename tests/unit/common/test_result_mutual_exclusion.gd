extends GutTest


func test_success_cannot_carry_an_error() -> void:
	var validation_error := DtoValidationError.new(&"run")
	var _illegal := DtoValidationResult.new(true, validation_error)
	assert_engine_error(ResultInvariant.ERROR_MESSAGE)


func test_success_cannot_omit_its_required_payload() -> void:
	var _illegal := ContentResolveResult.new(true, null, null)
	assert_engine_error(ResultInvariant.ERROR_MESSAGE)


func test_failure_cannot_carry_a_success_payload() -> void:
	var storage_error := StorageError.new(
		StorageError.READ_FAILED, &"read", &"main", 1
	)
	var bytes := OptionalBytesValue.new(PackedByteArray([1]))
	var _illegal := StorageReadResult.new(false, bytes, storage_error)
	assert_engine_error(ResultInvariant.ERROR_MESSAGE)


func test_failure_requires_an_error() -> void:
	var _illegal := StorageVoidResult.new(false, null)
	assert_engine_error(ResultInvariant.ERROR_MESSAGE)
