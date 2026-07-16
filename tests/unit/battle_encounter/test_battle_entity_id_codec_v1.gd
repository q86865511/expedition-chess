extends GutTest

const ENEMY_PREIMAGE_HEX := "42454931000000456e6f64655f6439343939323332303534313237366466643338346136313465323830633065316530663830343933316133626136656338653539666434363761303333626300000006626f73735f30"
const SUMMON_PREIMAGE_HEX := "42534931000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f00000012655f303062653537303965646230333739620000000d6566666563742e73756d6d6f6e0000000200000003"

var _codec := BattleEntityIdCodecV1.new()

func test_bei1_enemy_golden_uses_u32_be_ascii_and_first_16_hex() -> void:
	var result := _codec.encode_enemy(
		&"node_d94992320541276dfd384a614e280c0e1e0f804931a3ba6ec8e59fd467a033bc",
		"boss_0"
	)
	assert_true(result.ok)
	assert_eq(result.entity_id, &"e_00be5709edb0379b")
	assert_eq(result.canonical_bytes.hex_encode(), ENEMY_PREIMAGE_HEX)

func test_bsi1_summon_golden_uses_raw_setup_digest_and_u32_fields() -> void:
	var setup_hash := PackedByteArray()
	for value: int in range(32):
		setup_hash.append(value)
	var result := _codec.encode_summon(
		setup_hash,
		&"e_00be5709edb0379b",
		&"effect.summon",
		2,
		3
	)
	assert_true(result.ok)
	assert_eq(result.entity_id, &"s_f77a247cc5e21733")
	assert_eq(result.canonical_bytes.hex_encode(), SUMMON_PREIMAGE_HEX)

func test_enemy_rejects_non_ascii_or_noncanonical_spawn_keys() -> void:
	var bad_node := _codec.encode_enemy(&"node_中", "boss_0")
	assert_false(bad_node.ok)
	assert_eq(bad_node.error.field_path, &"node_id")
	for spawn_key: String in ["", "Boss_0", "boss-0", "a".repeat(65)]:
		var bad_spawn := _codec.encode_enemy(&"node_ascii", spawn_key)
		assert_false(bad_spawn.ok, spawn_key)
		assert_eq(bad_spawn.error.field_path, &"spawn_key")

func test_summon_rejects_wrong_digest_ascii_and_u32_bounds() -> void:
	var valid_hash := PackedByteArray()
	valid_hash.resize(32)
	var wrong_hash := _codec.encode_summon(
		PackedByteArray([0]), &"e_0123456789abcdef", &"effect.summon", 0, 0
	)
	assert_false(wrong_hash.ok)
	assert_eq(wrong_hash.error.field_path, &"setup_hash")
	var bad_summoner := _codec.encode_summon(
		valid_hash, &"enemy id", &"effect.summon", 0, 0
	)
	assert_false(bad_summoner.ok)
	assert_eq(bad_summoner.error.field_path, &"summoner_instance_id")
	var bad_effect := _codec.encode_summon(
		valid_hash, &"e_0123456789abcdef", &"effect.中", 0, 0
	)
	assert_false(bad_effect.ok)
	assert_eq(bad_effect.error.field_path, &"effect_id")
	var bad_index := _codec.encode_summon(
		valid_hash, &"e_0123456789abcdef", &"effect.summon", -1, 0
	)
	assert_false(bad_index.ok)
	assert_eq(bad_index.error.field_path, &"operation_index")
	var bad_serial := _codec.encode_summon(
		valid_hash, &"e_0123456789abcdef", &"effect.summon", 0, 0x100000000
	)
	assert_false(bad_serial.ok)
	assert_eq(bad_serial.error.field_path, &"summon_request_serial")
