class_name ContentGenerationMigrationReference
extends RefCounted

## Active run 對 content 的單一引用點。`category` 為空字串代表「來源只是 pinned
## selection(enabled_content_ids),或 save 上無法區分子類別(item def)」——這種
## 引用只能以 source_id 唯一比對 mapping,比對不唯一即拒絕。
## design.md「Adapter先驗全部digest…再traverse」列出的 run state 引用面由
## SaveMigrationRegistry 逐欄產生,port 不再自行猜測。

var category: StringName
var content_id: StringName
var field_path: StringName
## true = 由 active run 結構性欄位引用(必須 REQUIRED 且禁止 TOMBSTONE);
## false = collection／codex 面(enabled_content_ids、discovered_content_ids),
## 允許 OPTIONAL/TOMBSTONE,且 TOMBSTONE 在套用階段是「移除」而非保留舊 id。
var structural: bool
## true = 此 id 已進了 runtime key／receipt digest 的 preimage
## (claim receipt 的 effect_id、node choice receipt 的 choice_set_id／choice_id)。
## 這些位置無法在 migration 內重算 digest,因此只允許 IDENTITY;ALIAS／TOMBSTONE
## 一律 fail-closed,不得靜默保留舊 id,也不得產生內容與 digest 不符的 exactly-once
## 憑證(design.md:311「任一validation/transcode/save/read-back fault保留原main bytes」)。
var ledger_bound: bool


func _init(
	p_category: StringName,
	p_content_id: StringName,
	p_field_path: StringName,
	p_structural: bool,
	p_ledger_bound: bool = false
) -> void:
	category = p_category
	content_id = p_content_id
	field_path = p_field_path
	structural = p_structural
	ledger_bound = p_ledger_bound


func deep_clone() -> ContentGenerationMigrationReference:
	return ContentGenerationMigrationReference.new(
		category, content_id, field_path, structural, ledger_bound
	)
