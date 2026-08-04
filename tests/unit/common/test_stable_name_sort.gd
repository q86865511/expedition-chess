extends GutTest

## BP-SI-007 回歸測試：StringName 陣列的裸 sort() 依 interned 指標序排序（受 process 歷史
## 影響、非決定性）。StableNameSort.id_less 改用 String() 轉換後比較，須具備字典序保證。

func test_id_less_sorts_shuffled_string_names_in_dictionary_order() -> void:
	# 刻意打亂輸入順序，且混入位數不同的數字後綴（event_2 對比 event_10）── 純數值序與
	# 字典序在此會分歧，能揪出「剛好排對」的偽陽性。
	var shuffled: Array[StringName] = [
		&"map_node.event_10",
		&"zzz.last",
		&"aaa.first",
		&"map_node.event_2",
		&"unit.player_09",
		&"unit.player_01",
		&"map_node.event_1",
		&"middle.value",
	]
	var expected_strings: Array[String] = []
	for value: StringName in shuffled:
		expected_strings.append(String(value))
	expected_strings.sort()

	var sorted_ids := StableNameSort.sort_ids(shuffled)
	assert_eq(sorted_ids.size(), expected_strings.size())
	for index: int in range(expected_strings.size()):
		assert_eq(
			String(sorted_ids[index]), expected_strings[index],
			"index %d 應為字典序" % index
		)

	# id_less 本身也要能直接驅動 sort_custom，不只是便利函式 sort_ids。
	var duplicate := shuffled.duplicate()
	duplicate.sort_custom(StableNameSort.id_less)
	for index: int in range(expected_strings.size()):
		assert_eq(String(duplicate[index]), expected_strings[index])

func test_id_less_is_strict_weak_ordering_consistent_with_string_comparison() -> void:
	assert_true(StableNameSort.id_less(&"a.b", &"a.c"))
	assert_false(StableNameSort.id_less(&"a.c", &"a.b"))
	assert_false(StableNameSort.id_less(&"a.b", &"a.b"))
	assert_true(StableNameSort.id_less(&"map_node.event_1", &"map_node.event_10"))
	assert_true(StableNameSort.id_less(&"map_node.event_10", &"map_node.event_2"))
