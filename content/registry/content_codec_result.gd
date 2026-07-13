class_name ContentCodecResult
extends RefCounted

var ok: bool
var canonical_bytes: PackedByteArray
var entry: ContentEntryValue
var manifest: ContentManifestValue
var catalog: ContentCatalogSnapshot
var error: ContentCodecError

static func encoded(bytes: PackedByteArray) -> ContentCodecResult:
	return ContentCodecResult.new(true, bytes, null, null, null, null)

static func decoded_entry(value: ContentEntryValue, bytes: PackedByteArray) -> ContentCodecResult:
	return ContentCodecResult.new(true, bytes, value, null, null, null)

static func decoded_manifest(value: ContentManifestValue, bytes: PackedByteArray) -> ContentCodecResult:
	return ContentCodecResult.new(true, bytes, null, value, null, null)

static func decoded_catalog(value: ContentCatalogSnapshot, bytes: PackedByteArray) -> ContentCodecResult:
	return ContentCodecResult.new(true, bytes, null, null, value, null)

static func failed(path: StringName, source_id: StringName = &"") -> ContentCodecResult:
	return ContentCodecResult.new(false, PackedByteArray(), null, null, null, ContentCodecError.new(path, source_id))

func _init(
	p_ok: bool,
	p_canonical_bytes: PackedByteArray,
	p_entry: ContentEntryValue,
	p_manifest: ContentManifestValue,
	p_catalog: ContentCatalogSnapshot,
	p_error: ContentCodecError
) -> void:
	var success_payload_valid := (
		not p_canonical_bytes.is_empty()
		and not (p_entry != null and p_manifest != null)
		and not (p_entry != null and p_catalog != null)
		and not (p_manifest != null and p_catalog != null)
	)
	var failure_payload_clear := (
		p_canonical_bytes.is_empty()
		and p_entry == null
		and p_manifest == null
		and p_catalog == null
	)
	ResultInvariant.require(
		p_ok, p_error, success_payload_valid, failure_payload_clear
	)
	ok = p_ok
	canonical_bytes = p_canonical_bytes.duplicate() if p_ok else PackedByteArray()
	entry = p_entry.deep_clone() if p_ok and p_entry != null else null
	manifest = p_manifest.deep_clone() if p_ok and p_manifest != null else null
	catalog = p_catalog.deep_clone() if p_ok and p_catalog != null else null
	error = p_error if not p_ok else null
