class_name LocalizedTypographyPolicy
extends RefCounted

const UNSUPPORTED_LOCALE: StringName = &"UNSUPPORTED_LOCALE"
const FONT_UNAVAILABLE: StringName = &"ACCESSIBILITY_FONT_UNAVAILABLE"
const GLYPH_MISSING: StringName = &"ACCESSIBILITY_REQUIRED_GLYPH_MISSING"
const FONT_SOURCE_THEME: StringName = &"godot.theme_db.fallback_font"
const FONT_SOURCE_SYSTEM: StringName = &"godot.system_font.cjk_fallback"
const PROBE_FONT_SIZE: int = 24
const SYSTEM_FONT_NAMES: Array[String] = [
	"Microsoft JhengHei UI",
	"Microsoft JhengHei",
	"Noto Sans CJK TC",
	"Noto Sans TC",
	"PingFang TC",
	"Arial Unicode MS",
	"sans-serif",
]
const _FALLBACKS: Array[StringName] = [
	&"font.symbols",
	&"font.fallback",
]
const _PRIMARY_BY_LOCALE: Dictionary = {
	&"zh_TW": &"font.cjk",
	&"en": &"font.latin",
}


func font_tokens_for(locale: StringName) -> Dictionary:
	var primary: Variant = _PRIMARY_BY_LOCALE.get(locale)
	if primary == null:
		return {
			"ok": false,
			"primary_font_token": &"",
			"fallback_font_tokens": [],
			"error_code": UNSUPPORTED_LOCALE,
			"message_key": &"error.localization.unsupported_locale",
		}
	return {
		"ok": true,
		"primary_font_token": StringName(primary),
		"fallback_font_tokens": _FALLBACKS.duplicate(),
		"error_code": &"",
		"message_key": &"",
	}


func readability_report(
	locale: StringName,
	required_text: String
) -> Dictionary:
	var tokens := font_tokens_for(locale)
	if not bool(tokens.get("ok", false)):
		return tokens
	var selection := _font_selection(required_text)
	var font_value: Variant = selection.get("font")
	if not font_value is Font:
		return _readability_failure(
			locale,
			StringName(tokens.get("primary_font_token", &"")),
			FONT_UNAVAILABLE,
			[],
			Vector2.ZERO
		)
	var font := font_value as Font
	var font_source := StringName(
		selection.get("source", FONT_SOURCE_THEME)
	)

	var required_codepoints: Dictionary = {}
	var missing_glyphs: Array[int] = []
	for index: int in required_text.length():
		var codepoint := required_text.unicode_at(index)
		if _is_required_glyph(codepoint):
			required_codepoints[codepoint] = true
	for value: Variant in required_codepoints.keys():
		var codepoint := int(value)
		if not font.has_char(codepoint):
			missing_glyphs.append(codepoint)
	missing_glyphs.sort()
	var measured_size := font.get_string_size(
		required_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		PROBE_FONT_SIZE
	)
	var readable := (
		not required_codepoints.is_empty()
		and missing_glyphs.is_empty()
		and measured_size.x > 0.0
		and measured_size.y > 0.0
	)
	if not readable:
		return _readability_failure(
			locale,
			StringName(tokens.get("primary_font_token", &"")),
			GLYPH_MISSING,
			missing_glyphs,
			measured_size,
			required_codepoints.size(),
			font_source
		)
	return {
		"ok": true,
		"error_code": &"",
		"locale": locale,
		"primary_font_token": StringName(
			tokens.get("primary_font_token", &"")
		),
		"fallback_font_tokens": (
			tokens.get("fallback_font_tokens", []) as Array
		).duplicate(),
		"font_source": font_source,
		"font_available": true,
		"readable": true,
		"required_glyph_count": required_codepoints.size(),
		"missing_glyphs": missing_glyphs,
		"measured_size": measured_size,
	}


func apply_to(
	label: Label,
	locale: StringName,
	required_text: String
) -> Dictionary:
	if label == null:
		return _readability_failure(
			locale,
			&"",
			FONT_UNAVAILABLE,
			[],
			Vector2.ZERO
		)
	var report := readability_report(locale, required_text)
	if not bool(report.get("ok", false)):
		return report
	var selection := _font_selection(required_text)
	var font_value: Variant = selection.get("font")
	if not font_value is Font:
		return _readability_failure(
			locale,
			StringName(report.get("primary_font_token", &"")),
			FONT_UNAVAILABLE,
			[],
			Vector2.ZERO
		)
	var font := font_value as Font
	label.add_theme_font_override(&"font", font)
	label.text = required_text
	return report.duplicate(true)


func _font_selection(required_text: String) -> Dictionary:
	var system_font := SystemFont.new()
	var names := PackedStringArray()
	for font_name: String in SYSTEM_FONT_NAMES:
		names.append(font_name)
	system_font.font_names = names
	system_font.allow_system_fallback = true
	if _font_covers(system_font, required_text):
		return {
			"font": system_font,
			"source": FONT_SOURCE_SYSTEM,
		}
	var theme_font := ThemeDB.fallback_font
	if theme_font != null and _font_covers(theme_font, required_text):
		return {
			"font": theme_font,
			"source": FONT_SOURCE_THEME,
		}
	# Preserve the real SystemFont result so the caller reports the exact missing
	# glyphs. Never substitute a positive readability result without coverage.
	return {
		"font": system_font,
		"source": FONT_SOURCE_SYSTEM,
	}


func _font_covers(font: Font, required_text: String) -> bool:
	var found_required_glyph := false
	for index: int in required_text.length():
		var codepoint := required_text.unicode_at(index)
		if not _is_required_glyph(codepoint):
			continue
		found_required_glyph = true
		if not font.has_char(codepoint):
			return false
	return found_required_glyph


func _is_required_glyph(codepoint: int) -> bool:
	return (
		(codepoint >= 0x3400 and codepoint <= 0x4DBF)
		or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
		or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
	)


func _readability_failure(
	locale: StringName,
	primary_font_token: StringName,
	error_code: StringName,
	missing_glyphs: Array,
	measured_size: Vector2,
	required_glyph_count: int = 0,
	font_source: StringName = FONT_SOURCE_THEME
) -> Dictionary:
	return {
		"ok": false,
		"error_code": error_code,
		"locale": locale,
		"primary_font_token": primary_font_token,
		"fallback_font_tokens": _FALLBACKS.duplicate(),
		"font_source": font_source,
		"font_available": error_code != FONT_UNAVAILABLE,
		"readable": false,
		"required_glyph_count": required_glyph_count,
		"missing_glyphs": missing_glyphs.duplicate(),
		"measured_size": measured_size,
	}
