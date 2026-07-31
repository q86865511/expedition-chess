class_name ContentVerificationSuite
extends RefCounted

const MUTATION_NAMES: Array[StringName] = [
	&"stable_id", &"reference", &"asset", &"localization", &"unit_count", &"cost_distribution",
	&"trait_kind_count", &"three_tag_count", &"trait_threshold", &"component_count", &"recipe_coverage",
	&"minimum_counts", &"node_coverage", &"challenge_chain", &"shop_probability", &"pool_copies",
	&"reward_weight", &"unlock_cycle", &"base_build", &"effect_trigger", &"effect_condition",
	&"operation", &"consumable_operation", &"map_enter_operation", &"map_exit_operation",
	&"run_intent", &"summon_bound", &"summon_chain", &"summon_cycle"
]

var _case_count: int
var _failures: Array[Dictionary] = []

func run(case_filter: String = "") -> Dictionary:
	_case_count = 0
	_failures.clear()
	_run_if_selected(&"golden", case_filter, _case_golden)
	_run_if_selected(&"payload_roundtrip", case_filter, _case_payload_roundtrip)
	_run_if_selected(&"valid_slice", case_filter, _case_valid_slice)
	_run_if_selected(&"population_recompute", case_filter, _case_population_recompute)
	_run_if_selected(&"registry_pinning", case_filter, _case_registry_pinning)
	_run_if_selected(&"registry_transaction_rollback", case_filter, _case_registry_transaction_rollback)
	_run_if_selected(&"alias_receipt_migration", case_filter, _case_alias_receipt_migration)
	_run_if_selected(&"required_tombstone_incompatible", case_filter, _case_required_tombstone_incompatible)
	_run_if_selected(&"codec_negative", case_filter, _case_codec_negative)
	_run_if_selected(&"unknown_operation_compile", case_filter, _case_unknown_operation_compile)
	for mutation_name in MUTATION_NAMES:
		_run_mutation_if_selected(mutation_name, case_filter)
	return {
		"ok": _failures.is_empty(),
		"case_count": _case_count,
		"failures": _failures.duplicate(true),
		"completed_scopes": _completed_scopes_for_filter(case_filter),
		"deferred_scopes": [
			"canonical_battle_result",
			"entity_soak_execution",
			"content_codec_property_fuzz",
			"catalog_64_mib_physical_allocation_boundary",
		]
	}

func _completed_scopes_for_filter(case_filter: String) -> Array[String]:
	var scopes: Array[String] = []
	var named_scopes: Dictionary = {
		"golden": "content_codec_golden_fixture",
		"payload_roundtrip": "content_payload_roundtrip_schema_matrix",
		"valid_slice": "content_validation_valid_fixture",
		"population_recompute": "content_validation_population_recompute",
		"registry_pinning": "content_registry_generation_pinning",
		"registry_transaction_rollback": "content_registry_transaction_rollback",
		"alias_receipt_migration": "content_registry_alias_receipt_migration",
		"required_tombstone_incompatible": "content_registry_required_tombstone_preservation",
		"codec_negative": "content_codec_negative_contract_matrix",
		"unknown_operation_compile": "content_unknown_operation_rejection",
	}
	if case_filter.is_empty():
		for scope in named_scopes.values(): scopes.append(String(scope))
		for mutation_name in MUTATION_NAMES:
			scopes.append("content_validation_mutation.%s" % String(mutation_name))
	elif named_scopes.has(case_filter):
		scopes.append(String(named_scopes[case_filter]))
	else:
		var normalized := case_filter.trim_prefix("mutation.")
		if MUTATION_NAMES.has(StringName(normalized)):
			scopes.append("content_validation_mutation.%s" % normalized)
	scopes.sort()
	return scopes

func _run_if_selected(case_name: StringName, filter: String, callback: Callable) -> void:
	if not filter.is_empty() and filter != String(case_name): return
	_case_count += 1
	var message: String = callback.call()
	if not message.is_empty(): _fail(case_name, message)

func _run_mutation_if_selected(mutation_name: StringName, filter: String) -> void:
	var case_name := StringName("mutation.%s" % String(mutation_name))
	if not filter.is_empty() and filter != String(case_name) and filter != String(mutation_name): return
	_case_count += 1
	var report := ContentValidator.new().validate(SyntheticContentFixture.mutate(mutation_name))
	var expected_code := _expected_mutation_code(mutation_name)
	if report.valid:
		_fail(case_name, "mutation unexpectedly valid")
		return
	for issue in report.issues:
		if issue.code == expected_code: return
	_fail(case_name, "missing expected error %s" % String(expected_code))

func _case_golden() -> String:
	var codec := ContentCanonicalCodecV1.new()
	var compiled := ContentDefinitionCompiler.new().compile(ContentGoldenFixture.unit_definition())
	if not compiled.ok: return "entry compile failed"
	var entry := codec.encode_entry(compiled.entry)
	if not entry.ok: return "entry encode failed"
	if entry.canonical_bytes.size() != 453 or codec.sha256_bytes(entry.canonical_bytes).hex_encode() != "45473b5eb454fec56059d5c3cdda26787d799d3eba2a9ba2a70c185834af5f65": return "entry golden mismatch"
	var manifest := codec.encode_manifest(ContentGoldenFixture.manifest(codec.sha256_bytes(entry.canonical_bytes)))
	if not manifest.ok or manifest.canonical_bytes.size() != 254 or codec.sha256_bytes(manifest.canonical_bytes).hex_encode() != "a6b93f2a867be5898f8a366f0a0ce9d936106dea5aa575b46b907ddfdad2f90c": return "manifest golden mismatch"
	var entries: Array[PackedByteArray] = [entry.canonical_bytes]
	var catalog := codec.encode_catalog(codec.sha256_bytes(manifest.canonical_bytes), manifest.canonical_bytes, entries)
	if not catalog.ok or catalog.canonical_bytes.size() != 770 or codec.sha256_bytes(catalog.canonical_bytes).hex_encode() != "27f39e48aefa8fd81862f3a146666f7c344ab0f6c2a24e6fd79ab3340599bdf3": return "catalog golden mismatch"
	var decoded_entry := codec.decode_entry(entry.canonical_bytes)
	var decoded_manifest := codec.decode_manifest(manifest.canonical_bytes)
	var decoded_catalog := codec.decode_catalog(catalog.canonical_bytes)
	if not decoded_entry.ok or not decoded_manifest.ok or not decoded_catalog.ok: return "golden decode failed"
	if codec.encode_entry(decoded_entry.entry).canonical_bytes != entry.canonical_bytes: return "entry roundtrip mismatch"
	if codec.encode_manifest(decoded_manifest.manifest).canonical_bytes != manifest.canonical_bytes: return "manifest roundtrip mismatch"
	return ""

func _case_payload_roundtrip() -> String:
	var codec := ContentCanonicalCodecV3.new()
	var compiler := ContentDefinitionCompilerV3.new()
	var categories: Dictionary = {}
	var record_types: Dictionary = {}
	for definition in SyntheticContentFixture.build_valid().definitions:
		var compiled := compiler.compile(definition)
		if not compiled.ok: return "compile failed: %s/%s" % [String(definition.id), String(compiled.error.field_path)]
		var encoded := codec.encode_entry(compiled.entry)
		if not encoded.ok: return "encode failed: %s" % String(definition.id)
		var decoded := codec.decode_entry(encoded.canonical_bytes)
		if not decoded.ok: return "decode failed: %s" % String(definition.id)
		var reencoded := codec.encode_entry(decoded.entry)
		if not reencoded.ok or reencoded.canonical_bytes != encoded.canonical_bytes: return "roundtrip failed: %s" % String(definition.id)
		categories[compiled.entry.category] = true
		_collect_record_types(compiled.entry.payload, record_types)
	if categories.size() != 17: return "expected 17 payload categories, got %d" % categories.size()
	var int_pair := ContentValue.record(0x2009, PackedInt32Array([1, 2]), [ContentValue.i32(-1), ContentValue.i32(2)])
	var stable_pair := ContentValue.record(0x200d, PackedInt32Array([1, 2]), [ContentValue.stable_id(&"unit.test"), ContentValue.i32(1)])
	if not codec.validate_typed_value(int_pair).ok or not codec.validate_typed_value(stable_pair).ok: return "standalone nested record validation failed"
	record_types[0x2009] = true
	record_types[0x200d] = true
	for type_id in range(0x2000, 0x2010):
		if not record_types.has(type_id): return "missing nested record %x" % type_id
	for type_id in range(0x3001, 0x300a):
		if not record_types.has(type_id): return "missing battle operation %x" % type_id
	for type_id in range(0x3101, 0x3108):
		if not record_types.has(type_id): return "missing run operation %x" % type_id
	return ""

func _case_valid_slice() -> String:
	var report := ContentValidator.new().validate(SyntheticContentFixture.build_valid())
	if not report.valid:
		return "valid fixture rejected: %s/%s" % [String(report.issues[0].code), String(report.issues[0].source_id)]
	if report.version_maximum_population != 12 or report.per_side_stress_minimum != 16: return "baseline population mismatch"
	if report.entity_stress_minimum != maxi(64, report.maximum_simultaneous_entities): return "entity stress mismatch"
	return ""

func _case_population_recompute() -> String:
	var report := ContentValidator.new().validate(SyntheticContentFixture.build_valid(true))
	if not report.valid: return "fourth source fixture rejected"
	if report.version_maximum_population != 13 or report.per_side_stress_minimum != 17: return "fourth source did not recompute 13/17"
	return ""

func _case_registry_pinning() -> String:
	var fixture_a := SyntheticContentFixture.build_valid()
	var registry := ContentRegistryService.new()
	var full_a := registry.install_validated(fixture_a, "fixture.1", [&"pack.core"])
	if not full_a.ok: return "full A compile failed: %s/%s" % [String(full_a.error.code), String(full_a.error.field_path)]
	var selection := _selection()
	var pinned_a := registry.compile_pinned_generation(selection)
	if not pinned_a.ok or pinned_a.receipt == null: return "pinned A compile failed"
	if pinned_a.handle.manifest_digest == full_a.handle.manifest_digest: return "full and filtered digests must differ"
	if pinned_a.receipt.active_entry_ids.is_empty(): return "empty active entry index"
	var lease_result := registry.acquire_catalog_lease(pinned_a.handle)
	if not lease_result.ok: return "lease failed"
	var a_ref := ContentRef.new(pinned_a.handle.manifest_digest, &"unit.player_00")
	var a_view_result := registry.resolve(a_ref)
	if not a_view_result.ok or _view_health(a_view_result.value) != 100: return "pinned A resolve failed"
	a_view_result.value.payload.children[5].children[0].int_value = 777
	if _view_health(registry.resolve(a_ref).value) != 100: return "view mutation leaked into catalog"
	var fresh := ContentRegistryService.new()
	if not fresh.install_validated(fixture_a, "fixture.1", [&"pack.core"]).ok: return "fresh full compile failed"
	var probe := ContentSnapshotProbe.new("fixture.1", pinned_a.receipt.active_entry_ids, pinned_a.receipt.economy_config_id,
		pinned_a.receipt.combat_config_id,
		pinned_a.receipt.reward_table_ids, pinned_a.receipt.map_node_def_ids, pinned_a.receipt.challenge_unlock_def_ids,
		pinned_a.receipt.meta_reward_table_id, pinned_a.receipt.manifest_digest)
	var rebuilt := fresh.rebuild_from_probe(probe)
	if not rebuilt.ok or rebuilt.handle.manifest_digest != pinned_a.handle.manifest_digest: return "fresh persisted selection rebuild failed"
	var fixture_b := SyntheticContentFixture.build_valid()
	(_find_definition(fixture_b, &"unit.player_00") as UnitDef).base_stats.health = 999
	var full_b := registry.install_validated(fixture_b, "fixture.2", [&"pack.core"])
	if not full_b.ok: return "full B compile failed"
	if _view_health(registry.resolve(a_ref).value) != 100: return "A pin fell through to B"
	var latest := registry.latest_catalog_handle()
	if not latest.ok or latest.value.manifest_digest != full_b.handle.manifest_digest: return "latest B handle mismatch"
	if _view_health(registry.resolve(ContentRef.new(latest.value.manifest_digest, &"unit.player_00")).value) != 999: return "latest B resolve mismatch"
	if registry._remove_unleased_generation(pinned_a.handle.manifest_digest): return "leased A was removed"
	lease_result.lease.release()
	if not registry._remove_unleased_generation(pinned_a.handle.manifest_digest): return "released A was retained"
	if registry.resolve(a_ref).error.code != &"CONTENT_CATALOG_MISSING": return "removed A silently fell back"
	registry.free()
	fresh.free()
	return ""

func _case_registry_transaction_rollback() -> String:
	var registry := ContentRegistryService.new()
	var fixture := SyntheticContentFixture.build_valid()
	var full := registry.install_validated(fixture, "fixture.1", [&"pack.core"])
	if not full.ok:
		registry.free()
		return "transaction baseline full install failed"
	var pinned := registry.compile_pinned_generation(_selection())
	if not pinned.ok or pinned.receipt == null:
		registry.free()
		return "transaction baseline pin failed"
	var before_fingerprint := registry._state_fingerprint()
	var before_generations := registry._generation_count()
	var before_receipts := registry._receipt_count()
	var before_latest := full.handle.manifest_digest
	var before_receipt := registry._receipt_for_digest(pinned.handle.manifest_digest)
	if before_receipt == null:
		registry.free()
		return "transaction baseline receipt missing"
	var validation_failure := registry.install_validated(
		SyntheticContentFixture.mutate(&"stable_id"),
		"fixture.invalid.validation",
		[&"pack.core"]
	)
	if validation_failure.ok:
		registry.free()
		return "invalid authoring was published"
	var state_error := _registry_state_mismatch(
		registry,
		before_fingerprint,
		before_generations,
		before_receipts,
		before_latest,
		pinned.handle.manifest_digest,
		before_receipt.selection_digest
	)
	if not state_error.is_empty():
		registry.free()
		return "validation rollback: %s" % state_error
	var compile_failure := registry.install_validated(
		SyntheticContentFixture.build_valid(),
		"fixture.invalid.compile",
		[&"Invalid"]
	)
	if compile_failure.ok:
		registry.free()
		return "invalid manifest pack ID was published"
	state_error = _registry_state_mismatch(
		registry,
		before_fingerprint,
		before_generations,
		before_receipts,
		before_latest,
		pinned.handle.manifest_digest,
		before_receipt.selection_digest
	)
	if not state_error.is_empty():
		registry.free()
		return "compile rollback: %s" % state_error
	var expanded_ids: Array[StringName] = pinned.receipt.active_entry_ids.duplicate()
	if not expanded_ids.has(&"unit.player_03"): expanded_ids.append(&"unit.player_03")
	var mismatched_probe := ContentSnapshotProbe.new(
		"fixture.1",
		expanded_ids,
		pinned.receipt.economy_config_id,
		pinned.receipt.combat_config_id,
		pinned.receipt.reward_table_ids,
		pinned.receipt.map_node_def_ids,
		pinned.receipt.challenge_unlock_def_ids,
		pinned.receipt.meta_reward_table_id,
		"0000000000000000000000000000000000000000000000000000000000000000"
	)
	var probe_failure := registry.rebuild_from_probe(mismatched_probe)
	if probe_failure.ok or probe_failure.error.code != &"PINNED_CATALOG_MANIFEST_MISMATCH":
		registry.free()
		return "probe manifest mismatch was not rejected"
	state_error = _registry_state_mismatch(
		registry,
		before_fingerprint,
		before_generations,
		before_receipts,
		before_latest,
		pinned.handle.manifest_digest,
		before_receipt.selection_digest
	)
	if not state_error.is_empty():
		registry.free()
		return "probe rollback: %s" % state_error
	var missing_selection := _selection()
	missing_selection.root_enabled_content_ids.append(&"unit.missing")
	var selection_failure := registry.compile_pinned_generation(missing_selection)
	if selection_failure.ok or selection_failure.error.code != &"PINNED_CATALOG_REFERENCE_MISSING":
		registry.free()
		return "missing selection reference was not rejected"
	state_error = _registry_state_mismatch(
		registry,
		before_fingerprint,
		before_generations,
		before_receipts,
		before_latest,
		pinned.handle.manifest_digest,
		before_receipt.selection_digest
	)
	registry.free()
	return "selection rollback: %s" % state_error if not state_error.is_empty() else ""

func _registry_state_mismatch(
	registry: ContentRegistryService,
	expected_fingerprint: String,
	expected_generations: int,
	expected_receipts: int,
	expected_latest: String,
	pinned_digest: String,
	expected_selection_digest: String
) -> String:
	if registry._state_fingerprint() != expected_fingerprint: return "fingerprint changed"
	if registry._generation_count() != expected_generations: return "generation count changed"
	if registry._receipt_count() != expected_receipts: return "receipt count changed"
	var latest := registry.latest_catalog_handle()
	if not latest.ok or latest.value.manifest_digest != expected_latest: return "latest handle changed"
	var pinned_receipt := registry._receipt_for_digest(pinned_digest)
	if pinned_receipt == null or pinned_receipt.selection_digest != expected_selection_digest: return "pinned receipt changed"
	var resolved := registry.resolve(ContentRef.new(pinned_digest, &"unit.player_00"))
	if not resolved.ok or _view_health(resolved.value) != 100: return "pinned catalog changed"
	return ""

func _case_codec_negative() -> String:
	var codec := ContentCanonicalCodecV1.new()
	var compiled := ContentDefinitionCompiler.new().compile(ContentGoldenFixture.unit_definition())
	if not compiled.ok: return "negative baseline compile failed"
	var encoded := codec.encode_entry(compiled.entry)
	if not encoded.ok: return "negative baseline encode failed"
	var corrupt_magic := encoded.canonical_bytes.duplicate()
	corrupt_magic[0] = 0
	if codec.decode_entry(corrupt_magic).ok: return "bad magic accepted"
	var corrupt_type := encoded.canonical_bytes.duplicate()
	corrupt_type[6] = 0x03
	if codec.decode_entry(corrupt_type).ok: return "unknown envelope type accepted"
	var duplicate_field := encoded.canonical_bytes.duplicate()
	duplicate_field[20] = 0
	duplicate_field[21] = 1
	if codec.decode_entry(duplicate_field).ok: return "duplicate/non-increasing field accepted"
	var trailing := encoded.canonical_bytes.duplicate()
	trailing.append(0)
	if codec.decode_entry(trailing).ok: return "trailing bytes accepted"
	if codec.decode_entry(encoded.canonical_bytes.slice(0, encoded.canonical_bytes.size() - 1)).ok: return "truncation accepted"
	var oversized_text := "x".repeat(ContentCanonicalCodecV1.MAX_SCALAR_BYTES + 1)
	if codec.encode_value_for_sort(ContentValue.text(oversized_text)).ok: return "oversized scalar accepted"
	var wrong_tag_entry := compiled.entry.deep_clone()
	wrong_tag_entry.payload.children[3] = ContentValue.i32(1)
	if codec.encode_entry(wrong_tag_entry).ok: return "wrong field tag accepted"
	var wrong_collection_entry := compiled.entry.deep_clone()
	wrong_collection_entry.payload.children[4] = ContentValue.canonical_set([ContentValue.text("trait.bad")])
	if codec.encode_entry(wrong_collection_entry).ok: return "wrong collection element tag accepted"
	var unsupported_entry := compiled.entry.deep_clone()
	unsupported_entry.resource_schema_version = 2
	var unsupported_entry_encode := codec.encode_entry(unsupported_entry)
	if unsupported_entry_encode.ok \
		or unsupported_entry_encode.error.field_path != &"entry.resource_schema_version":
		return "unsupported entry schema encoded"
	var schema_two_entry_bytes := encoded.canonical_bytes.duplicate()
	if schema_two_entry_bytes.size() <= 39 or schema_two_entry_bytes[35] != 0x03:
		return "entry schema mutation fixture layout changed"
	schema_two_entry_bytes[39] = 2
	var unsupported_entry_decode := codec.decode_entry(schema_two_entry_bytes)
	if unsupported_entry_decode.ok \
		or unsupported_entry_decode.error.field_path != &"entry.resource_schema_version":
		return "unsupported entry schema decoded"
	var manifest_a := ContentGoldenFixture.manifest(codec.sha256_bytes(encoded.canonical_bytes))
	var encoded_manifest_a := codec.encode_manifest(manifest_a)
	if not encoded_manifest_a.ok: return "negative baseline manifest encode failed"
	var corrupt_version := encoded_manifest_a.canonical_bytes.duplicate()
	corrupt_version[15] = 2
	if codec.decode_manifest(corrupt_version).ok: return "unsupported content codec version accepted"
	var unsupported_manifest := manifest_a.deep_clone()
	unsupported_manifest.catalog_schema_version = 2
	var unsupported_manifest_encode := codec.encode_manifest(unsupported_manifest)
	if unsupported_manifest_encode.ok \
		or unsupported_manifest_encode.error.field_path != &"manifest.catalog_schema_version":
		return "unsupported catalog schema encoded"
	var schema_two_manifest_bytes := encoded_manifest_a.canonical_bytes.duplicate()
	if schema_two_manifest_bytes.size() <= 22 or schema_two_manifest_bytes[18] != 0x03:
		return "manifest schema mutation fixture layout changed"
	schema_two_manifest_bytes[22] = 2
	var unsupported_manifest_decode := codec.decode_manifest(schema_two_manifest_bytes)
	if unsupported_manifest_decode.ok \
		or unsupported_manifest_decode.error.field_path != &"manifest.catalog_schema_version":
		return "unsupported catalog schema decoded"
	var baseline_entries: Array[PackedByteArray] = [encoded.canonical_bytes]
	var encoded_catalog_a := codec.encode_catalog(
		codec.sha256_bytes(encoded_manifest_a.canonical_bytes),
		encoded_manifest_a.canonical_bytes,
		baseline_entries
	)
	if not encoded_catalog_a.ok: return "negative baseline catalog encode failed"
	var corrupt_manifest_digest := encoded_catalog_a.canonical_bytes.duplicate()
	corrupt_manifest_digest[12] = corrupt_manifest_digest[12] ^ 0xff
	var digest_result := codec.decode_catalog(corrupt_manifest_digest)
	if digest_result.ok or digest_result.error.field_path != &"catalog.manifest_digest":
		return "catalog manifest digest mismatch accepted"
	var empty_entries: Array[PackedByteArray] = []
	var count_result := _decode_catalog_fixture(codec, manifest_a, empty_entries)
	if count_result.ok or count_result.error.field_path != &"catalog.entry_count":
		return "catalog entry count mismatch accepted"
	var unit_b := ContentGoldenFixture.unit_definition()
	unit_b.id = &"unit.b"
	unit_b.display_name_key = &"unit.b.name"
	var compiled_b := ContentDefinitionCompiler.new().compile(unit_b)
	if not compiled_b.ok: return "unit B compile failed"
	var encoded_b := codec.encode_entry(compiled_b.entry)
	if not encoded_b.ok: return "unit B encode failed"
	var manifest_b := ContentGoldenFixture.manifest(codec.sha256_bytes(encoded_b.canonical_bytes))
	manifest_b.aliases.clear()
	manifest_b.tombstones.clear()
	manifest_b.entry_indexes = [ContentEntryIndexValue.new(&"unit", &"unit.b", 1, codec.sha256_bytes(encoded_b.canonical_bytes))]
	var identity_result := _decode_catalog_fixture(codec, manifest_b, baseline_entries)
	if identity_result.ok or identity_result.error.field_path != &"catalog.entry_identity":
		return "manifest B with entry A accepted"
	var category_manifest := manifest_a.deep_clone()
	category_manifest.entry_indexes[0].category = &"trait"
	var category_result := _decode_catalog_fixture(codec, category_manifest, baseline_entries)
	if category_result.ok or category_result.error.field_path != &"catalog.entry_identity":
		return "catalog category mismatch accepted"
	var schema_manifest := manifest_a.deep_clone()
	schema_manifest.entry_indexes[0].resource_schema_version = 2
	var schema_result := _decode_catalog_fixture(codec, schema_manifest, baseline_entries)
	if schema_result.ok or schema_result.error.field_path != &"catalog.entry_identity":
		return "catalog schema mismatch accepted"
	var matching_schema_two_manifest := manifest_a.deep_clone()
	matching_schema_two_manifest.entry_indexes[0].resource_schema_version = 2
	matching_schema_two_manifest.entry_indexes[0].entry_digest = codec.sha256_bytes(
		schema_two_entry_bytes
	)
	var schema_two_entries: Array[PackedByteArray] = [schema_two_entry_bytes]
	var matching_schema_two_result := _decode_catalog_fixture(
		codec,
		matching_schema_two_manifest,
		schema_two_entries
	)
	if matching_schema_two_result.ok \
		or matching_schema_two_result.error.field_path != &"entry.resource_schema_version":
		return "matching unsupported entry/index schema accepted"
	var entry_digest_manifest := manifest_a.deep_clone()
	entry_digest_manifest.entry_indexes[0].entry_digest = codec.sha256_bytes(encoded_b.canonical_bytes)
	var entry_digest_result := _decode_catalog_fixture(codec, entry_digest_manifest, baseline_entries)
	if entry_digest_result.ok or entry_digest_result.error.field_path != &"catalog.entry_digest":
		return "catalog entry digest mismatch accepted"
	var ordered_manifest := ContentManifestValue.new()
	ordered_manifest.catalog_schema_version = 1
	ordered_manifest.content_version = "fixture.1"
	ordered_manifest.pack_ids = [&"pack.core"]
	ordered_manifest.entry_indexes = [
		ContentEntryIndexValue.new(&"unit", &"unit.a", 1, codec.sha256_bytes(encoded.canonical_bytes)),
		ContentEntryIndexValue.new(&"unit", &"unit.b", 1, codec.sha256_bytes(encoded_b.canonical_bytes)),
	]
	var reversed_entries: Array[PackedByteArray] = [encoded_b.canonical_bytes, encoded.canonical_bytes]
	var entry_order_result := _decode_catalog_fixture(codec, ordered_manifest, reversed_entries)
	if entry_order_result.ok or entry_order_result.error.field_path != &"catalog.entry_order":
		return "catalog entry order mismatch accepted"
	var reversed_manifest := ordered_manifest.deep_clone()
	reversed_manifest.entry_indexes.reverse()
	var manifest_order_result := _decode_catalog_fixture(codec, reversed_manifest, reversed_entries)
	if manifest_order_result.ok or manifest_order_result.error.field_path != &"catalog.entry_order":
		return "manifest index order mismatch accepted"
	var invalid_registry := ContentRegistryService.new()
	var invalid_ref := invalid_registry.resolve(ContentRef.new("bad", &"unit.a"))
	if invalid_ref.ok or invalid_ref.error.code != &"CONTENT_REF_INVALID":
		invalid_registry.free()
		return "invalid content ref accepted"
	if invalid_registry.acquire_catalog_lease(CatalogHandle.new("missing", "", false)).ok:
		invalid_registry.free()
		return "missing catalog lease accepted"
	invalid_registry.free()
	return ""

func _decode_catalog_fixture(
	codec: ContentCanonicalCodecV1,
	manifest: ContentManifestValue,
	entry_bytes: Array[PackedByteArray]
) -> ContentCodecResult:
	var encoded_manifest := codec.encode_manifest(manifest)
	if not encoded_manifest.ok: return encoded_manifest
	var encoded_catalog := codec.encode_catalog(
		codec.sha256_bytes(encoded_manifest.canonical_bytes),
		encoded_manifest.canonical_bytes,
		entry_bytes
	)
	if not encoded_catalog.ok: return encoded_catalog
	return codec.decode_catalog(encoded_catalog.canonical_bytes)

func _case_unknown_operation_compile() -> String:
	var compiler := ContentDefinitionCompilerV3.new()
	var fixture := SyntheticContentFixture.build_valid()
	var effect_battle := _find_definition(fixture, &"effect.general") as EffectDef
	var unknown_battle := BattleOperationDef.new()
	unknown_battle.operation_index = 0
	effect_battle.battle_operations = [unknown_battle]
	var battle_result := compiler.compile(effect_battle)
	if battle_result.ok or battle_result.error.field_path != &"battle_operations.unknown_type":
		return "unknown battle operation was silently omitted"
	fixture = SyntheticContentFixture.build_valid()
	var effect_run := _find_definition(fixture, &"effect.general") as EffectDef
	var unknown_run := RunOperationDef.new()
	unknown_run.operation_index = 0
	effect_run.run_operations = [unknown_run]
	var run_result := compiler.compile(effect_run)
	if run_result.ok or run_result.error.field_path != &"run_operations.unknown_type":
		return "unknown effect run operation was silently omitted"
	var operation_mutations: Array[StringName] = [&"consumable_operation", &"map_enter_operation", &"map_exit_operation"]
	for mutation_name in operation_mutations:
		fixture = SyntheticContentFixture.mutate(mutation_name)
		var content_id: StringName = &"consumable.test" if mutation_name == &"consumable_operation" else (&"map_node.normal" if mutation_name == &"map_enter_operation" else &"map_node.event_0")
		var expected_path: StringName = &"run_operations.unknown_type" if mutation_name == &"consumable_operation" else (&"enter_operations.unknown_type" if mutation_name == &"map_enter_operation" else &"exit_operations.unknown_type")
		var compiled_unknown := compiler.compile(_find_definition(fixture, content_id))
		if compiled_unknown.ok or compiled_unknown.error.field_path != expected_path:
			return "%s was silently omitted" % String(mutation_name)
	return ""

func _case_alias_receipt_migration() -> String:
	var fixture_a := SyntheticContentFixture.build_valid()
	var registry_a := ContentRegistryService.new()
	if not registry_a.install_validated(fixture_a, "fixture.1", [&"pack.core"]).ok:
		registry_a.free()
		return "source catalog compile failed"
	var pinned_a := registry_a.compile_pinned_generation(_selection())
	if not pinned_a.ok:
		registry_a.free()
		return "source pinned catalog compile failed"
	var probe := ContentSnapshotProbe.new("fixture.1", pinned_a.receipt.active_entry_ids, pinned_a.receipt.economy_config_id,
		pinned_a.receipt.combat_config_id,
		pinned_a.receipt.reward_table_ids, pinned_a.receipt.map_node_def_ids, pinned_a.receipt.challenge_unlock_def_ids,
		pinned_a.receipt.meta_reward_table_id, pinned_a.receipt.manifest_digest)
	var fixture_b := SyntheticContentFixture.build_valid()
	(_find_definition(fixture_b, &"unit.player_00") as UnitDef).id = &"unit.player_00_new"
	_replace_content_id_references(fixture_b, &"unit.player_00", &"unit.player_00_new")
	var registry_b := ContentRegistryService.new()
	var aliases: Array[ContentAliasValue] = [ContentAliasValue.new(&"unit.player_00", &"unit.player_00_new")]
	fixture_b.aliases = aliases
	var alias_install := registry_b.install_validated(fixture_b, "fixture.2", [&"pack.core"])
	if not alias_install.ok:
		registry_a.free()
		registry_b.free()
		return "alias target catalog compile failed: %s/%s/%s" % [
			String(alias_install.error.code),
			String(alias_install.error.field_path),
			String(alias_install.error.source_id.value) if alias_install.error.source_id != null else "",
		]
	var migrated := ContentRegistryReceiptAdapter.new(registry_b).compile_or_lookup(probe)
	if not migrated.ok or migrated.receipt == null:
		registry_a.free()
		registry_b.free()
		return "alias probe did not compile a migrated receipt"
	if migrated.receipt.active_entry_ids.has(&"unit.player_00") or not migrated.receipt.active_entry_ids.has(&"unit.player_00_new"):
		registry_a.free()
		registry_b.free()
		return "alias receipt active IDs were not remapped"
	if migrated.receipt.manifest_digest == pinned_a.receipt.manifest_digest:
		registry_a.free()
		registry_b.free()
		return "alias migration reused the persisted digest"
	var migration_adapter := ContentRegistryMigrationAdapter.new(registry_b)
	var request := ContentIdMigrationRequest.new(&"unit.player_00", &"unit", true, &"run.roster")
	var mapped := migration_adapter.resolve(request)
	if not mapped.ok or mapped.disposition != ContentIdMigrationResult.Disposition.ALIAS or mapped.resolved_id.value != &"unit.player_00_new":
		registry_a.free()
		registry_b.free()
		return "typed alias migration adapter mismatch"
	registry_a.free()
	registry_b.free()
	return ""

func _case_required_tombstone_incompatible() -> String:
	var fixture_a := SyntheticContentFixture.build_valid()
	var registry_a := ContentRegistryService.new()
	if not registry_a.install_validated(fixture_a, "fixture.1", [&"pack.core"]).ok:
		registry_a.free()
		return "required tombstone source catalog compile failed"
	var pinned_a := registry_a.compile_pinned_generation(_selection())
	if not pinned_a.ok:
		registry_a.free()
		return "required tombstone source pin failed"
	var probe := ContentSnapshotProbe.new(
		"fixture.1",
		pinned_a.receipt.active_entry_ids,
		pinned_a.receipt.economy_config_id,
		pinned_a.receipt.combat_config_id,
		pinned_a.receipt.reward_table_ids,
		pinned_a.receipt.map_node_def_ids,
		pinned_a.receipt.challenge_unlock_def_ids,
		pinned_a.receipt.meta_reward_table_id,
		pinned_a.receipt.manifest_digest
	)
	var fixture_b := SyntheticContentFixture.build_valid()
	(_find_definition(fixture_b, &"unit.player_00") as UnitDef).id = &"unit.player_00_new"
	_replace_content_id_references(fixture_b, &"unit.player_00", &"unit.player_00_new")
	var tombstones: Array[ContentTombstoneValue] = [
		ContentTombstoneValue.new(
			&"unit.player_00", &"unit", &"safe_replace",
			&"unit.player_00_new", true, &"removed"
		),
	]
	fixture_b.tombstones = tombstones
	var registry_b := ContentRegistryService.new()
	var tombstone_install := registry_b.install_validated(fixture_b, "fixture.2", [&"pack.core"])
	if not tombstone_install.ok:
		registry_a.free()
		registry_b.free()
		return "required tombstone target catalog compile failed: %s/%s/%s" % [
			String(tombstone_install.error.code),
			String(tombstone_install.error.field_path),
			String(tombstone_install.error.source_id.value) if tombstone_install.error.source_id != null else "",
		]
	var receipt_result := ContentRegistryReceiptAdapter.new(registry_b).compile_or_lookup(probe)
	if receipt_result.ok or receipt_result.error.code != PinnedCatalogReceiptError.REFERENCE_MISSING:
		registry_a.free()
		registry_b.free()
		return "required tombstone receipt did not preserve incompatible run"
	var request := ContentIdMigrationRequest.new(
		&"unit.player_00", &"unit", true, &"run.roster.unit_instances"
	)
	var mapped := ContentRegistryMigrationAdapter.new(registry_b).resolve(request)
	if mapped.ok or mapped.disposition != ContentIdMigrationResult.Disposition.INCOMPATIBLE_REQUIRED:
		registry_a.free()
		registry_b.free()
		return "required tombstone migration guessed a replacement"
	registry_a.free()
	registry_b.free()
	return ""

func _collect_record_types(value: ContentValue, result: Dictionary) -> void:
	if value.kind == ContentValue.Kind.RECORD: result[value.record_type] = true
	for child in value.children: _collect_record_types(child, result)

func _view_health(view: ContentDefinitionView) -> int:
	return view.payload.children[5].children[0].int_value

func _selection() -> CatalogSelection:
	return CatalogSelection.new("fixture.1", [&"unit.player_00", &"unit.player_01", &"unit.player_02"], &"economy.default", &"config.combat_default",
		[&"reward_table.default"], [&"map_node.normal"], [&"unlock.challenge_0", &"unlock.challenge_1", &"unlock.challenge_2", &"unlock.challenge_3", &"unlock.challenge_4", &"unlock.challenge_5"], &"meta_reward.default")

func _find_definition(input: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition in input.definitions:
		if definition.id == content_id: return definition
	return null

func _replace_content_id_references(input: ContentValidationInput, old_id: StringName, new_id: StringName) -> void:
	for definition in input.definitions:
		_replace_in_array(definition.unlock_refs, old_id, new_id)
		if definition is CommanderDef:
			for amount in (definition as CommanderDef).starting_pack:
				if amount.content_id == old_id: amount.content_id = new_id
		elif definition is UnlockDef:
			var unlock := definition as UnlockDef
			_replace_in_array(unlock.prerequisite_refs, old_id, new_id)
			_replace_in_array(unlock.unlocked_content_refs, old_id, new_id)
			_replace_in_array(unlock.modifier_refs, old_id, new_id)
		elif definition is EffectDef:
			_replace_run_operation_references((definition as EffectDef).run_operations, old_id, new_id)
		elif definition is ConsumableDef:
			_replace_run_operation_references((definition as ConsumableDef).run_operations, old_id, new_id)
		elif definition is MapNodeDef:
			var map_node := definition as MapNodeDef
			_replace_run_operation_references(map_node.enter_operations, old_id, new_id)
			_replace_run_operation_references(map_node.exit_operations, old_id, new_id)

func _replace_run_operation_references(
	operations: Array[RunOperationDef],
	old_id: StringName,
	new_id: StringName
) -> void:
	for operation in operations:
		if operation is ModifyUnitPoolOperationDef and operation.unit_ref == old_id:
			operation.unit_ref = new_id
		elif operation is GrantItemOperationDef and operation.content_ref == old_id:
			operation.content_ref = new_id
		elif operation is GrantRelicOperationDef and operation.relic_ref == old_id:
			operation.relic_ref = new_id

func _replace_in_array(values: Array[StringName], old_id: StringName, new_id: StringName) -> void:
	for index in values.size():
		if values[index] == old_id: values[index] = new_id

func _expected_mutation_code(name: StringName) -> StringName:
	match name:
		&"stable_id": return &"CONTENT_STABLE_ID"
		&"reference": return &"CONTENT_REFERENCE_MISSING"
		&"asset": return &"CONTENT_ASSET_MISSING"
		&"localization": return &"CONTENT_LOCALIZATION_MISSING"
		&"unit_count": return &"CONTENT_UNIT_COUNT"
		&"cost_distribution": return &"CONTENT_COST_DISTRIBUTION"
		&"trait_kind_count": return &"CONTENT_TRAIT_KIND_COUNT"
		&"three_tag_count": return &"CONTENT_THREE_TAG_COUNT"
		&"trait_threshold": return &"CONTENT_TRAIT_THRESHOLD_UNREACHABLE"
		&"component_count": return &"CONTENT_COMPONENT_COUNT"
		&"recipe_coverage": return &"CONTENT_RECIPE_COVERAGE"
		&"minimum_counts": return &"CONTENT_MINIMUM_COUNTS"
		&"node_coverage": return &"CONTENT_NODE_KIND_COVERAGE"
		&"challenge_chain": return &"CONTENT_CHALLENGE_CHAIN"
		&"shop_probability": return &"CONTENT_SHOP_PROBABILITY"
		&"pool_copies": return &"CONTENT_POOL_COPIES"
		&"reward_weight": return &"CONTENT_REWARD_WEIGHT"
		&"unlock_cycle": return &"CONTENT_UNLOCK_CYCLE"
		&"base_build": return &"CONTENT_BASE_BUILD_MISSING"
		&"effect_trigger": return &"CONTENT_EFFECT_TRIGGER"
		&"effect_condition": return &"CONTENT_EFFECT_CONDITION"
		&"operation", &"consumable_operation", &"map_enter_operation", &"map_exit_operation": return &"CONTENT_OPERATION_INVALID"
		&"run_intent": return &"CONTENT_RUN_INTENT_FORBIDDEN"
		&"summon_bound", &"summon_chain", &"summon_cycle": return &"CONTENT_ENTITY_BOUND"
	return &"CONTENT_VALIDATION_FAILED"

func _fail(case_name: StringName, message: String) -> void:
	_failures.append({"case": String(case_name), "message": message})
