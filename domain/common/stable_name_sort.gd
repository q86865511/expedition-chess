class_name StableNameSort
extends RefCounted

## StringName 的裸 sort() 依 interned 指標序排序（受 process 歷史影響，非決定性；BP-SI-007）。
## 任何要求決定性順序的 StringName 陣列（canonical 狀態、內容池排序等）一律改用本工具的
## 字典序比較，取代各檔各自定義的 _id_less／_string_name_less 等重複 static helper。

static func id_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

## 便利函式：回傳依字典序排序過的新陣列（不修改輸入）。
static func sort_ids(ids: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = ids.duplicate()
	result.sort_custom(id_less)
	return result
