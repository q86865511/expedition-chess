class_name BuildLabActiveContentIdPort
extends ContentIdMigrationPort

## T11 (specs/build-systems/design.md §8) -- Build Lab 灰盒的內容 id 遷移埠。
## 單一世代、不做跨世代遷移：Build Lab 只跑
## 一個 digest,save/load 期間每個 def_id 一律視為仍在該 digest 下 active
## (真正安裝時已經是 ContentValidator 驗證通過的雙 pack 內容,不會有 tombstone/
## alias 情境需要處理)。

func resolve(request: ContentIdMigrationRequest) -> ContentIdMigrationResult:
	return ContentIdMigrationResult.active(request.content_id)
