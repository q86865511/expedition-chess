class_name BuildLabDependencyPort
extends ContentDependencyPort

## T11 (specs/build-systems/design.md §8) -- Build Lab 灰盒的內容驗證依賴埠。
## 表現層現況（HANDOFF.md §3）全專案尚無正式在地化/美術資源，因此本埠一律回報
## 「資源已存在」，讓 ContentValidator 對 asset_refs／display_name_key 的存在性
## 檢查不會因為美術/在地化尚未由 Codex 建立而擋下開發灰盒的內容安裝——僅供本 Lab
## 使用，不代表正式資源已齊備。

func asset_exists(_path: String) -> bool:
	return true

func localization_key_exists(_key: StringName) -> bool:
	return true
