class_name AccessibilityTooltipResult
extends RefCounted

var ok: bool
var accepted: bool
var error: StringName
var opened_depth: int


func deep_clone() -> AccessibilityTooltipResult:
	var clone := AccessibilityTooltipResult.new()
	clone.ok = ok
	clone.accepted = accepted
	clone.error = error
	clone.opened_depth = opened_depth
	return clone


static func failure(code: StringName) -> AccessibilityTooltipResult:
	var result := AccessibilityTooltipResult.new()
	result.error = code
	return result
