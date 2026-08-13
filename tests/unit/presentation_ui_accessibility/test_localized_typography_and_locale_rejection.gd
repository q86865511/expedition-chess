extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_accessibility/accessibility_test_support.gd"
)


func test_zh_tw_and_en_use_readable_cjk_and_latin_fallback_tokens() -> void:
	var script := Support.load_script(self, Support.TYPOGRAPHY_PATH)
	if script == null:
		return
	var policy: Object = script.new()
	if not Support.require_methods(
		self,
		policy,
		[&"font_tokens_for"],
		Support.TYPOGRAPHY_PATH
	):
		return

	var cases := {
		&"zh_TW": &"font.cjk",
		&"en": &"font.latin",
	}
	for locale: StringName in cases:
		var result: Variant = policy.call(&"font_tokens_for", locale)
		assert_true(result is Dictionary)
		if not result is Dictionary:
			continue
		assert_eq(result.get("ok"), true)
		assert_eq(result.get("primary_font_token"), cases[locale])
		var fallbacks := Support.names(result.get("fallback_font_tokens", []))
		assert_has(fallbacks, &"font.symbols")
		assert_has(fallbacks, &"font.fallback")
		assert_eq(result.get("error_code", &""), &"")


func test_locale_wire_set_is_exact_and_unsupported_locale_is_named() -> void:
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
	assert_eq(catalog.supported_locales(), [&"zh_TW", &"en"])
	var catalog_rejection := catalog.resolve(&"ja", &"loc.unsupported_probe")
	assert_false(catalog_rejection.ok)
	assert_eq(catalog_rejection.error_code, &"UNSUPPORTED_LOCALE")

	var script := Support.load_script(self, Support.TYPOGRAPHY_PATH)
	if script == null:
		return
	var policy: Object = script.new()
	if not Support.require_methods(
		self,
		policy,
		[&"font_tokens_for"],
		Support.TYPOGRAPHY_PATH
	):
		return
	var rejection: Variant = policy.call(&"font_tokens_for", &"ja")
	assert_true(rejection is Dictionary)
	if not rejection is Dictionary:
		return
	assert_eq(rejection.get("ok"), false)
	assert_eq(rejection.get("error_code"), &"UNSUPPORTED_LOCALE")
	assert_eq(rejection.get("primary_font_token", &""), &"")


func test_bundled_font_is_first_for_zh_tw_and_en_visible_text() -> void:
	var policy := LocalizedTypographyPolicy.new()
	for case: Dictionary in [
		{"locale": &"zh_TW", "text": "戰鬥規則與傷害提示"},
		{"locale": &"en", "text": "Combat rules and damage cues"},
	]:
		var report := policy.readability_report(case["locale"], case["text"])
		assert_true(bool(report.get("ok", false)))
		assert_eq(
			StringName(report.get("font_source", &"")),
			LocalizedTypographyPolicy.FONT_SOURCE_BUNDLED
		)
		assert_false(bool(report.get("fallback_used", true)))
		assert_gt(int(report.get("required_glyph_count", 0)), 0)


func test_real_missing_glyph_is_not_reported_as_readable() -> void:
	var report := LocalizedTypographyPolicy.new().readability_report(
		&"en",
		String.chr(0x10FFFF)
	)
	assert_false(bool(report.get("ok", true)))
	assert_eq(
		StringName(report.get("error_code", &"")),
		LocalizedTypographyPolicy.GLYPH_MISSING
	)
	assert_false((report.get("missing_glyphs", []) as Array).is_empty())
