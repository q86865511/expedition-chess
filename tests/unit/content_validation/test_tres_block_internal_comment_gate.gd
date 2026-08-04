extends GutTest

# Fail-closed 守門：Godot 4.7 的 .tres 文字格式在 [sub_resource]/[resource] 區塊內，
# 若屬性賦值前一行是 `#` 註解，該屬性會被靜默解析成型別預設值（int -> 0），不報任何錯誤。
# 已實證受害（修復前 amount 解析為 0，見 commit 修復本檔的同一批變更）：
#   trait_faction_arcane / trait_faction_shadow / trait_role_mystic /
#   trait_role_sentinel / trait_role_trickster 等 EffectDef 的 amount。
# 本測試逐檔掃描 content/packs/**/*.tres 的原始文字，偵測「區塊內、屬性行之前出現
# 註解行」的模式即 FAIL；正確寫法是把備註移到檔案最末尾（區塊與屬性行之外）。

const PACKS_ROOT := "res://content/packs"

# G2 balance-playtest 修復批次：5 個已實證受害檔的 amount 應被救回著作值，
# 防止未來又被區塊內註解重新毒害而回歸為 0。
const EXPECTED_AMOUNTS := {
	"res://content/packs/build_systems/effects/trait_faction_arcane.tres": 15,
	"res://content/packs/build_systems/effects/trait_faction_shadow.tres": 80,
	"res://content/packs/build_systems/effects/trait_role_mystic.tres": 10,
	"res://content/packs/build_systems/effects/trait_role_sentinel.tres": 10,
	"res://content/packs/build_systems/effects/trait_role_trickster.tres": 100,
	# 同批全 packs 掃蕩另尋獲的受害檔，一併鎖定回歸。
	"res://content/packs/build_systems/effects/equip_arcane.tres": 10,
	"res://content/packs/build_systems/effects/equip_shadow.tres": 50,
	"res://content/packs/build_systems/effects/equip_verdant.tres": 20,
	"res://content/packs/build_systems/effects/relic_frost_edge.tres": 15,
	"res://content/packs/build_systems/effects/relic_iron_will.tres": 40,
	"res://content/packs/build_systems/effects/relic_shadow_veil.tres": 120,
}

func test_no_pack_tres_file_has_a_block_internal_comment_before_a_property_line() -> void:
	var offenders: Array[String] = []
	_scan_dir(PACKS_ROOT, offenders)
	assert_true(offenders.is_empty(), "區塊內註解會靜默毒害屬性解析(int -> 0):\n" + "\n".join(offenders))

func test_recovered_effect_amounts_match_authored_values() -> void:
	for path: String in EXPECTED_AMOUNTS.keys():
		var resource: EffectDef = load(path)
		assert_not_null(resource, "無法載入: %s" % path)
		if resource == null: continue
		assert_eq(resource.battle_operations.size(), 1, "應恰含 1 個 battle_operation: %s" % path)
		if resource.battle_operations.is_empty(): continue
		var amount := int(resource.battle_operations[0].get("amount"))
		assert_eq(amount, int(EXPECTED_AMOUNTS[path]), "amount 應等於著作值: %s" % path)

# ================= 掃描實作 =================

static func _scan_dir(path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := "%s/%s" % [path, entry]
			if dir.current_is_dir():
				_scan_dir(full_path, offenders)
			elif entry.ends_with(".tres"):
				_scan_file(full_path, offenders)
		entry = dir.get_next()
	dir.list_dir_end()

static func _scan_file(path: String, offenders: Array[String]) -> void:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		offenders.append("%s: 無法開啟檔案" % path)
		return
	var text := handle.get_as_text()
	var lines := text.split("\n")
	var property_regex := RegEx.new()
	property_regex.compile("^[A-Za-z_][A-Za-z0-9_]*\\s*=\\s*")
	var in_block := false
	var pending: Array[Array] = []
	for index in lines.size():
		var line := lines[index]
		var line_no := index + 1
		if line.begins_with("["):
			in_block = line.begins_with("[sub_resource") or line.begins_with("[resource]") or line.begins_with("[resource ")
			pending.clear()
			continue
		if line.strip_edges() == "":
			in_block = false
			pending.clear()
			continue
		if not in_block:
			continue
		if line.begins_with("#"):
			pending.append([line_no, line])
			continue
		if property_regex.search(line) != null:
			for entry: Array in pending:
				offenders.append("%s:%d\t%s" % [path, entry[0], entry[1]])
			pending.clear()
			continue
		# 其他行(例如陣列值的延續行)不影響 pending 狀態。
