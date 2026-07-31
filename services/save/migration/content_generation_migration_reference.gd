class_name ContentGenerationMigrationReference
extends RefCounted

## Active run 對 content 的單一引用點。`category` 為空字串代表「來源只是 pinned
## selection(enabled_content_ids),save 上沒有結構性欄位可推得 category」——這種
## 引用只能以 source_id 唯一比對 mapping,比對不唯一即拒絕。
## design.md「Adapter先驗全部digest…再traverse」列出的 run state 引用面由
## SaveMigrationRegistry 逐欄產生,port 不再自行猜測。

var category: StringName
var content_id: StringName
var field_path: StringName
## true = 由 active run 結構性欄位引用(必須 REQUIRED 且禁止 TOMBSTONE);
## false = 只出現在 pinned selection,允許 OPTIONAL/TOMBSTONE。
var structural: bool


func _init(
	p_category: StringName,
	p_content_id: StringName,
	p_field_path: StringName,
	p_structural: bool
) -> void:
	category = p_category
	content_id = p_content_id
	field_path = p_field_path
	structural = p_structural


func deep_clone() -> ContentGenerationMigrationReference:
	return ContentGenerationMigrationReference.new(
		category, content_id, field_path, structural
	)
