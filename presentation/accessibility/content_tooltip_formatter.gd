class_name ContentTooltipFormatter
extends RefCounted

const MAX_DEPTH: int = 2

func format_value(
	label_key: StringName,
	localized_text: String,
	numeric_value: int,
	locale: StringName,
	locale_generation: int,
	depth: int
) -> ContentTooltipFormatResult:
	if label_key.is_empty() or localized_text.is_empty():
		return ContentTooltipFormatResult.failure(&"TOOLTIP_INPUT_INVALID")
	if locale != &"zh_TW" and locale != &"en":
		return ContentTooltipFormatResult.failure(&"TOOLTIP_LOCALE_UNSUPPORTED")
	if locale_generation < 0:
		return ContentTooltipFormatResult.failure(&"TOOLTIP_LOCALE_GENERATION")
	if depth < 0 or depth > MAX_DEPTH:
		return ContentTooltipFormatResult.failure(&"TOOLTIP_DEPTH_EXCEEDED")
	return ContentTooltipFormatResult.success(ContentTooltipSnapshot.new(
		label_key,
		localized_text,
		numeric_value,
		locale,
		locale_generation,
		depth
	))
