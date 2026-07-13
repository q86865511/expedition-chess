extends SceneTree

func _init() -> void:
	var root := SaveRootFixture.create_valid_root()
	var validation := RunStateValidator.new().validate_root(root)
	if not validation.ok:
		push_error("fixture validation failed: %s" % validation.error.field_path)
		quit(2)
		return
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	if not encoded.ok:
		push_error("encode failed: %s" % encoded.error.field_path)
		quit(2)
		return
	var decoded := codec.decode_text(encoded.json_text.value)
	if not decoded.ok or decoded.root == null:
		push_error("decode failed")
		quit(2)
		return
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	var saved := repository.save(root)
	if not saved.ok:
		push_error("save failed: %s" % saved.error.code)
		quit(2)
		return
	var loaded := repository.load()
	if not loaded.ok or loaded.run_status != LoadResult.RunStatus.LOADED:
		push_error("load failed")
		quit(2)
		return
	print("SAVE_FOUNDATION_PROBE_OK")
	quit(0)
