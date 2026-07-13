class_name ContentGoldenFixture
extends RefCounted

static func unit_definition() -> UnitDef:
	var unit := UnitDef.new()
	unit.id = &"unit.a"
	unit.schema_version = 1
	unit.display_name_key = &"unit.a.name"
	unit.cost_tier = 1
	unit.base_stats = UnitStatsDef.new()
	unit.base_stats.health = 100
	unit.base_stats.attack = 10
	unit.base_stats.armor = 0
	unit.base_stats.magic_resist = 0
	unit.base_stats.attack_speed_milli = 1000
	unit.base_stats.attack_range_cells = 1
	unit.base_stats.start_mana = 0
	unit.base_stats.max_mana = 50
	unit.base_stats.move_speed_milli = 1000
	unit.star_scalings = [_scaling(1, 10000), _scaling(2, 18000), _scaling(3, 32000)]
	unit.has_ability_ref = false
	unit.ai_profile = &"frontline"
	unit.basic_attack_profile = &"melee"
	unit.availability = &"player"
	unit.shop_condition = &"always"
	return unit

static func manifest(entry_digest: PackedByteArray) -> ContentManifestValue:
	var value := ContentManifestValue.new()
	value.catalog_schema_version = 1
	value.content_version = "fixture.1"
	value.pack_ids = [&"pack.core"]
	value.aliases = [ContentAliasValue.new(&"unit.old", &"unit.a")]
	value.tombstones = [ContentTombstoneValue.new(&"relic.old", &"relic", &"safe_absent", &"", false, &"removed")]
	value.entry_indexes = [ContentEntryIndexValue.new(&"unit", &"unit.a", 1, entry_digest)]
	return value

static func _scaling(star: int, basis_points: int) -> StarScalingDef:
	var value := StarScalingDef.new()
	value.star = star
	value.health_bps = basis_points
	value.attack_bps = basis_points
	value.armor_bps = basis_points
	value.magic_resist_bps = basis_points
	value.attack_speed_bps = basis_points
	value.attack_range_bps = basis_points
	value.start_mana_bps = basis_points
	value.max_mana_bps = basis_points
	value.move_speed_bps = basis_points
	return value
