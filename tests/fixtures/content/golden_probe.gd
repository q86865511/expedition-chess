extends SceneTree

func _init() -> void:
	var codec := ContentCanonicalCodecV1.new()
	var compile_result := ContentDefinitionCompiler.new().compile(ContentGoldenFixture.unit_definition())
	if not compile_result.ok:
		push_error("compile failed")
		quit(2)
		return
	var entry_result := codec.encode_entry(compile_result.entry)
	var manifest_result := codec.encode_manifest(ContentGoldenFixture.manifest(codec.sha256_bytes(entry_result.canonical_bytes)))
	var entry_list: Array[PackedByteArray] = [entry_result.canonical_bytes]
	var catalog_result := codec.encode_catalog(codec.sha256_bytes(manifest_result.canonical_bytes), manifest_result.canonical_bytes, entry_list)
	print("ENTRY_LEN=", entry_result.canonical_bytes.size())
	print("ENTRY_SHA=", codec.sha256_bytes(entry_result.canonical_bytes).hex_encode())
	print("ENTRY_HEX=", entry_result.canonical_bytes.hex_encode())
	print("MANIFEST_LEN=", manifest_result.canonical_bytes.size())
	print("MANIFEST_SHA=", codec.sha256_bytes(manifest_result.canonical_bytes).hex_encode())
	print("MANIFEST_HEX=", manifest_result.canonical_bytes.hex_encode())
	print("CATALOG_LEN=", catalog_result.canonical_bytes.size())
	print("CATALOG_SHA=", codec.sha256_bytes(catalog_result.canonical_bytes).hex_encode())
	quit(0)
