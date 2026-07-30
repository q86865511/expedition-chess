extends GutTest

## G2 F5（fresh review `.pipeline/reviews/fix-branch-fresh-review.md`）：
## `AppRoot._battle_commander_passive_effect_ids()` 只把「battle_operations 非空且
## run_operations 為空」的指揮官被動餵進 BattleSetupSourceCompiler——混合型（兩邊
## 都非空）會被整條丟掉，連 battle 那半也不見。這個過濾判準在現行內容下正確，
## 但前提沒有任何 validator／gate 釘住：日後著作混合型被動時，症狀會是「戰鬥中
## 指揮官被動沒生效」這種靜默失效，而不是具名錯誤。
##
## 本檔對**真實 pack**（不是 synthetic fixture）釘死那個前提。它紅的意思是：
## 內容已經出現混合型被動，AppRoot 的過濾判準必須同步改（把 battle 那半拆出來
## 編譯，而不是整條丟掉），不是把這條測試放寬。

const BUILD_SYSTEMS_ROOT := "res://content/packs/build_systems"
const VERTICAL_SLICE_ROOT := "res://content/packs/vertical_slice"


func test_no_commander_passive_effect_mixes_battle_and_run_operations() -> void:
	var definitions := _load_all_packs()
	var by_id: Dictionary = {}
	for definition: ContentDefinition in definitions:
		by_id[definition.id] = definition

	var commanders: Array[CommanderDef] = []
	for definition: ContentDefinition in definitions:
		if definition is CommanderDef:
			commanders.append(definition as CommanderDef)
	assert_false(
		commanders.is_empty(),
		"正式 pack 必須含 CommanderDef，否則本測試等於空跑"
	)

	var inspected := 0
	var mixed: Array[String] = []
	for commander: CommanderDef in commanders:
		for effect_id: StringName in commander.passive_effect_refs:
			var effect: Variant = by_id.get(effect_id)
			if not effect is EffectDef:
				continue
			inspected += 1
			var typed := effect as EffectDef
			if (
				not typed.battle_operations.is_empty()
				and not typed.run_operations.is_empty()
			):
				mixed.append("%s/%s" % [String(commander.id), String(effect_id)])
	assert_gt(
		inspected,
		0,
		"passive_effect_refs 必須解析得到 EffectDef，否則本測試等於空跑"
	)
	assert_eq(
		mixed,
		([] as Array[String]),
		(
			"混合型指揮官被動會被 AppRoot._battle_commander_passive_effect_ids() "
			+ "整條丟掉（battle 那半也不見）: %s"
		) % ", ".join(mixed)
	)


func test_app_root_battle_passive_filter_keeps_only_pure_battle_effects() -> void:
	# 判準本身的正對照／反對照：過濾條件寫在 app_root.gd，這裡確認它就是
	# 「battle 非空 AND run 為空」，避免上面那條前提測試守著一個已經改掉的判準。
	var source := FileAccess.get_file_as_string("res://app/app_root.gd")
	assert_false(source.is_empty(), "app_root.gd 必須可讀")
	assert_true(
		source.contains("not rule.battle_operations.is_empty()"),
		"battle 側判準必須仍是 battle_operations 非空"
	)
	assert_true(
		source.contains("and rule.run_operations.is_empty()"),
		"run 側判準必須仍是 run_operations 為空（本檔前提測試守的就是這一條）"
	)


func _load_all_packs() -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	_load_dir(BUILD_SYSTEMS_ROOT, result)
	_load_dir(VERTICAL_SLICE_ROOT, result)
	return result


func _load_dir(path: String, result: Array[ContentDefinition]) -> void:
	var dir := DirAccess.open(path)
	assert_not_null(dir, "無法開啟目錄: %s" % path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := "%s/%s" % [path, entry]
			if dir.current_is_dir():
				_load_dir(full_path, result)
			elif entry.ends_with(".tres"):
				var resource := load(full_path)
				if resource is ContentDefinition:
					result.append(resource)
		entry = dir.get_next()
	dir.list_dir_end()
