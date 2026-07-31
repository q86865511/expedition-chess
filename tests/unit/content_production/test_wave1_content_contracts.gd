extends GutTest

const REQUIRED_SCRIPTS: Array[String] = [
	"res://content/definitions/unit_presentation_def.gd",
	"res://content/definitions/node_choice_def.gd",
	"res://content/definitions/node_choice_set_def.gd",
	"res://content/definitions/audio_cue_def.gd",
	"res://content/registry/content_canonical_codec_v3.gd",
	"res://content/registry/content_definition_compiler_v3.gd",
	"res://app/content/localization_catalog_load_request.gd",
	"res://app/content/localization_catalog_load_result.gd",
	"res://app/content/localization_catalog_load_error.gd",
	"res://app/content/localization_catalog_loader.gd",
	"res://presentation/accessibility/content_tooltip_snapshot.gd",
	"res://presentation/accessibility/content_tooltip_formatter.gd",
]


func test_wave1_public_types_exist_as_separate_scripts() -> void:
	for path: String in REQUIRED_SCRIPTS:
		assert_true(FileAccess.file_exists(path), "missing Wave 1 script: %s" % path)


func test_codec_v3_manifest_tuple_and_extended_payloads_round_trip() -> void:
	var codec_script := _required_script(
		"res://content/registry/content_canonical_codec_v3.gd"
	)
	var compiler_script := _required_script(
		"res://content/registry/content_definition_compiler_v3.gd"
	)
	if codec_script == null or compiler_script == null:
		return
	var codec: Variant = codec_script.new()
	var compiler: Variant = compiler_script.new()
	var unit := ContentGoldenFixture.unit_definition()
	unit.schema_version = 2
	unit.has_ability_ref = true
	unit.ability_ref = &"ability.unit_a"
	unit.effect_refs = [&"effect.unit_a.innate"]
	unit.set("presentation_ref", &"presentation.unit_a")
	var compiled_unit: Variant = compiler.call("compile", unit)
	assert_true(compiled_unit.ok, "V3 unit compile failed")
	if not compiled_unit.ok:
		return
	assert_eq(compiled_unit.entry.resource_schema_version, 2)
	assert_eq(compiled_unit.entry.payload.children.size(), 14)
	assert_eq(
		compiled_unit.entry.payload.children[13].string_value,
		"presentation.unit_a"
	)
	var encoded_unit: Variant = codec.call("encode_entry", compiled_unit.entry)
	assert_true(encoded_unit.ok)
	if encoded_unit.ok:
		var decoded_unit: Variant = codec.call(
			"decode_entry", encoded_unit.canonical_bytes
		)
		assert_true(decoded_unit.ok)
		assert_eq(
			codec.call("encode_entry", decoded_unit.entry).canonical_bytes,
			encoded_unit.canonical_bytes
		)

	var effect := EffectDef.new()
	effect.id = &"effect.unit_a.primary"
	effect.schema_version = 2
	effect.display_name_key = &"effect.unit_a.name"
	effect.trigger = &"on_cast"
	effect.stacking = &"replace"
	effect.set("description_key", &"effect.unit_a.description")
	var compiled_effect: Variant = compiler.call("compile", effect)
	assert_true(compiled_effect.ok, "V3 effect compile failed")
	if compiled_effect.ok:
		assert_eq(compiled_effect.entry.payload.children.size(), 13)
		assert_eq(
			compiled_effect.entry.payload.children[12].string_value,
			"effect.unit_a.description"
		)

	var manifest := ContentManifestValue.new()
	manifest.catalog_schema_version = 2
	manifest.content_version = "production.1"
	manifest.pack_ids = [&"pack.production"]
	var encoded_manifest: Variant = codec.call("encode_manifest", manifest)
	assert_true(encoded_manifest.ok)
	if encoded_manifest.ok:
		var decoded_manifest: Variant = codec.call(
			"decode_manifest", encoded_manifest.canonical_bytes
		)
		assert_true(decoded_manifest.ok)
		assert_eq(decoded_manifest.manifest.catalog_schema_version, 2)
		assert_eq(
			codec.call(
				"encode_manifest", decoded_manifest.manifest
			).canonical_bytes,
			encoded_manifest.canonical_bytes
		)
		assert_false(
			ContentCanonicalCodecV2.new().decode_manifest(
				encoded_manifest.canonical_bytes
			).ok,
			"V2 reader must reject a V3 manifest"
		)


func test_new_definition_categories_compile_with_exact_v3_shapes() -> void:
	var compiler_script := _required_script(
		"res://content/registry/content_definition_compiler_v3.gd"
	)
	if compiler_script == null:
		return
	var compiler: Variant = compiler_script.new()
	var presentation_script := _required_script(
		"res://content/definitions/unit_presentation_def.gd"
	)
	var audio_script := _required_script(
		"res://content/definitions/audio_cue_def.gd"
	)
	if presentation_script == null or audio_script == null:
		return
	var presentation: Variant = presentation_script.new()
	presentation.id = &"presentation.unit_a"
	presentation.schema_version = 1
	presentation.display_name_key = &"presentation.unit_a.name"
	presentation.portrait_path = "res://assets/production/portraits/unit_a.png"
	presentation.sprite_frames_path = "res://assets/production/units/unit_a.tres"
	presentation.board_icon_path = "res://assets/production/icons/unit_a.png"
	presentation.ability_icon_path = "res://assets/production/icons/ability_unit_a.png"
	var vfx_refs: Array[StringName] = [&"effect.unit_a.primary"]
	presentation.combat_vfx_refs = vfx_refs
	var cue_refs: Array[StringName] = [&"audio.combat_cast"]
	presentation.audio_cue_refs = cue_refs
	var compiled_presentation: Variant = compiler.call("compile", presentation)
	assert_true(compiled_presentation.ok)
	if compiled_presentation.ok:
		assert_eq(
			compiled_presentation.entry.payload.record_type,
			0x1011
		)
		assert_eq(compiled_presentation.entry.payload.children.size(), 9)

	var audio: Variant = audio_script.new()
	audio.id = &"audio.combat_cast"
	audio.schema_version = 1
	audio.display_name_key = &"audio.combat_cast.name"
	audio.bus = &"SFX"
	audio.stream_path = "res://assets/production/audio/combat_cast.ogg"
	audio.loop = false
	var compiled_audio: Variant = compiler.call("compile", audio)
	assert_true(compiled_audio.ok)
	if compiled_audio.ok:
		assert_eq(compiled_audio.entry.payload.record_type, 0x1013)
		assert_eq(compiled_audio.entry.payload.children.size(), 6)


func test_localization_loader_is_digest_bound_fail_closed_and_keeps_public_api() -> void:
	var request_script := _required_script(
		"res://app/content/localization_catalog_load_request.gd"
	)
	var loader_script := _required_script(
		"res://app/content/localization_catalog_loader.gd"
	)
	if request_script == null or loader_script == null:
		return
	var bytes := (
		"key,zh_TW,en\n"
		+ "screen.test.title,測試畫面,Test Screen\n"
		+ "tooltip.test,數值 %s,Value %s\n"
	).to_utf8_buffer()
	var digest := ContentCanonicalCodecV1.new().sha256_bytes(bytes).hex_encode()
	var request: Variant = request_script.new(
		&"res://localization/test.csv", bytes, digest
	)
	bytes[0] = 0
	var loaded: Variant = loader_script.new().call("load_catalog", request)
	assert_true(loaded.ok, "loader must parse its immutable request copy")
	if loaded.ok:
		var catalog: Variant = loaded.catalog
		assert_eq(catalog.default_locale(), &"zh_TW")
		assert_eq(catalog.supported_locales(), [&"zh_TW", &"en"])
		assert_eq(
			catalog.keys_for_locale(&"zh_TW"),
			catalog.keys_for_locale(&"en")
		)
		assert_eq(
			catalog.resolve(&"en", &"screen.test.title").value,
			"Test Screen"
		)
	var tampered_request: Variant = request_script.new(
		&"res://localization/test.csv",
		"key,zh_TW,en\nscreen.test.title,測試畫面,Tampered\n".to_utf8_buffer(),
		digest
	)
	var rejected_digest: Variant = loader_script.new().call(
		"load_catalog", tampered_request
	)
	assert_false(rejected_digest.ok)
	assert_eq(rejected_digest.error.code, &"DIGEST_MISMATCH")
	var duplicate_bytes := (
		"key,zh_TW,en\n"
		+ "screen.test.title,甲,A\n"
		+ "screen.test.title,乙,B\n"
	).to_utf8_buffer()
	var duplicate_request: Variant = request_script.new(
		&"res://localization/test.csv",
		duplicate_bytes,
		ContentCanonicalCodecV1.new().sha256_bytes(duplicate_bytes).hex_encode()
	)
	var rejected_duplicate: Variant = loader_script.new().call(
		"load_catalog", duplicate_request
	)
	assert_false(rejected_duplicate.ok)
	assert_eq(rejected_duplicate.error.code, &"DUPLICATE_KEY")


func test_tooltip_formatter_uses_catalog_value_and_enforces_depth_two() -> void:
	var snapshot_script := _required_script(
		"res://presentation/accessibility/content_tooltip_snapshot.gd"
	)
	var formatter_script := _required_script(
		"res://presentation/accessibility/content_tooltip_formatter.gd"
	)
	if snapshot_script == null or formatter_script == null:
		return
	var formatter: Variant = formatter_script.new()
	var ok: Variant = formatter.call(
		"format_value",
		&"tooltip.test",
		"Value 25",
		25,
		&"en",
		7,
		2
	)
	assert_true(ok.ok)
	if ok.ok:
		assert_eq(ok.snapshot.numeric_value, 25)
		assert_eq(ok.snapshot.locale_generation, 7)
		assert_eq(ok.snapshot.depth, 2)
	var too_deep: Variant = formatter.call(
		"format_value",
		&"tooltip.test",
		"Value 25",
		25,
		&"en",
		7,
		3
	)
	assert_false(too_deep.ok)
	assert_eq(too_deep.error_code, &"TOOLTIP_DEPTH_EXCEEDED")


func _required_script(path: String) -> Script:
	if not FileAccess.file_exists(path):
		fail_test("missing Wave 1 script: %s" % path)
		return null
	var script := load(path) as Script
	assert_not_null(script, "could not load Wave 1 script: %s" % path)
	return script
