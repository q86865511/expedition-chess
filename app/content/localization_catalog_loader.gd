class_name LocalizationCatalogLoader
extends RefCounted

func load_catalog(
	request: LocalizationCatalogLoadRequest
) -> LocalizationCatalogLoadResult:
	if request == null or not String(request.source_id).begins_with("res://"):
		return _failure(LocalizationCatalogLoadError.IO)
	var bytes := request.source_bytes_copy()
	if not _is_digest(request.expected_sha256):
		return _failure(LocalizationCatalogLoadError.DIGEST_MISMATCH)
	# Decode PCK-backed buffers before handing them to HashingContext so UTF-8
	# validation does not depend on the post-update backing-view lifetime; the
	# subsequent digest still authenticates the original bytes.
	var text := bytes.get_string_from_utf8()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	if context.finish().hex_encode() != request.expected_sha256:
		return _failure(LocalizationCatalogLoadError.DIGEST_MISMATCH)
	var round_trip := text.to_utf8_buffer()
	if round_trip.size() != bytes.size() \
		or _sha256(round_trip) != request.expected_sha256 \
		or (not text.is_empty() and text.unicode_at(0) == 0xfeff):
		return _failure(LocalizationCatalogLoadError.MALFORMED_HEADER)
	var lines := text.replace("\r\n", "\n").split("\n")
	if lines.is_empty():
		return _failure(LocalizationCatalogLoadError.MALFORMED_HEADER, 1)
	var header := _parse_csv_line(lines[0])
	if header.size() != 3 \
		or header[0] != "key" \
		or header[1] != "zh_TW" \
		or header[2] != "en":
		return _failure(LocalizationCatalogLoadError.MALFORMED_HEADER, 1)
	var values: Dictionary = {&"zh_TW": {}, &"en": {}}
	var seen: Dictionary = {}
	for index: int in range(1, lines.size()):
		if lines[index].is_empty() and index == lines.size() - 1:
			continue
		var fields := _parse_csv_line(lines[index])
		if fields.size() != 3:
			return _failure(LocalizationCatalogLoadError.MALFORMED_ROW, index + 1)
		var key := StringName(fields[0])
		if String(key).is_empty():
			return _failure(LocalizationCatalogLoadError.MALFORMED_ROW, index + 1)
		if seen.has(key):
			return _failure(
				LocalizationCatalogLoadError.DUPLICATE_KEY, index + 1, key
			)
		if fields[1].is_empty() or fields[2].is_empty():
			return _failure(
				LocalizationCatalogLoadError.BLANK_VALUE, index + 1, key
			)
		seen[key] = true
		(values[&"zh_TW"] as Dictionary)[key] = fields[1]
		(values[&"en"] as Dictionary)[key] = fields[2]
	return LocalizationCatalogLoadResult.success(
		LocalizationCatalog._from_validated_values(values)
	)

func _parse_csv_line(line: String) -> PackedStringArray:
	var fields := PackedStringArray()
	var current := ""
	var quoted := false
	var index := 0
	while index < line.length():
		var code := line.unicode_at(index)
		if code == 34:
			if quoted and index + 1 < line.length() \
				and line.unicode_at(index + 1) == 34:
				current += "\""
				index += 2
				continue
			quoted = not quoted
		elif code == 44 and not quoted:
			fields.append(current)
			current = ""
		else:
			current += line.substr(index, 1)
		index += 1
	if quoted:
		return PackedStringArray()
	fields.append(current)
	return fields

func _failure(
	code: StringName,
	row: int = 0,
	key: StringName = &""
) -> LocalizationCatalogLoadResult:
	return LocalizationCatalogLoadResult.failure(
		LocalizationCatalogLoadError.new(code, row, key)
	)

func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) \
			and not (code >= 97 and code <= 102):
			return false
	return true


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
