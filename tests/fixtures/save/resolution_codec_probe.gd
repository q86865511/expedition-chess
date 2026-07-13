extends SceneTree

func _init() -> void:
	var codec := SaveRootFixture.create_codec()
	for kind: int in [
		ResolutionState.Kind.IDLE,
		ResolutionState.Kind.COMBAT_PENDING,
		ResolutionState.Kind.BATTLE_RESULT_PENDING,
		ResolutionState.Kind.REWARD_PENDING,
	]:
		var candidate := ResolutionFixtureFactory.create_root(kind)
		var encoded := codec.encode(candidate)
		if not encoded.ok:
			push_error("ENCODE_KIND_%d:%s" % [kind, encoded.error.field_path])
			quit(2)
			return
		var decoded := codec.decode_text(encoded.json_text.value)
		if not decoded.ok:
			push_error("DECODE_KIND_%d:%s" % [kind, decoded.error.field_path])
			quit(2)
			return
	print("RESOLUTION_CODEC_PROBE_OK")
	quit(0)
