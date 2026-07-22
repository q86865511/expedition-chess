class_name ShopError
extends RefCounted

const INPUT_INVALID: StringName = &"SHOP_INPUT_INVALID"
const GENERATION_MISMATCH: StringName = &"SHOP_CATALOG_GENERATION_MISMATCH"
const RNG_FAILED: StringName = &"SHOP_RNG_FAILED"
const CONFIG_INVALID: StringName = &"SHOP_CONFIG_INVALID"
const SERIAL_EXHAUSTED: StringName = &"SHOP_SERIAL_EXHAUSTED"
const KEY_FAILED: StringName = &"SHOP_KEY_FAILED"
const DIGEST_FAILED: StringName = &"SHOP_DIGEST_FAILED"
const GOLD_INSUFFICIENT: StringName = &"SHOP_GOLD_INSUFFICIENT"
const OFFER_STALE: StringName = &"SHOP_OFFER_STALE"
const RESERVATION_INVALID: StringName = &"SHOP_RESERVATION_INVALID"
const UNIT_POOL_INVALID: StringName = &"SHOP_UNIT_POOL_INVALID"
const ROSTER_FULL: StringName = &"SHOP_ROSTER_FULL"
const UNIT_MISSING: StringName = &"SHOP_UNIT_MISSING"
const UNIT_RULE_MISSING: StringName = &"SHOP_UNIT_RULE_MISSING"
const MERGE_FAILED: StringName = &"SHOP_MERGE_FAILED"
const LEVEL_MAX: StringName = &"SHOP_LEVEL_MAX"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> ShopError:
	return ShopError.new(code, field_path)
