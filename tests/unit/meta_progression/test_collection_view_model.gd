extends GutTest

## T09 (specs/meta-progression/design.md §8: "圖鑑館經 CollectionViewModel
## 按類別讀出"; tasks.md T09 驗收:"CollectionViewModel 按類別讀出"):
## design.md 未釘選確切 wire 契約,以下為測試作者決定(test-author decision,
## 沿用 tests/fixtures/build_items/forge_equipment_test_fixture.gd 開頭註解
## 對未釘選契約的處理慣例):
##
##   CollectionViewModel.new(profile: ProfileState) -- 只持 profile 的
##   deep_clone,不跨操作保留可變引用(沿用
##   presentation/viewmodels/trait_preview_view_model.gd 的既有慣例)。
##
##   內容 id 的 category 取其第一個 "." 前的區段(例如 "unit.fixture" ->
##   "unit"),沿用全專案 content id 一律 "<category>.<name>" 的既有命名慣例
##   (見 unit.fixture／relic.fixture／commander.fixture／equipment.* 等,
##   tests/fixtures/save/save_root_fixture.gd 與
##   tests/fixtures/build_items/forge_equipment_test_fixture.gd 皆同此慣例)。
##
##   discovered_ids_for_category(category)／unlocked_ids_for_category(category)
##   分別回傳 profile.discovered_content_ids／unlocked_content_ids 中屬於該
##   category 的子集(保留原陣列相對順序);is_discovered(id)／is_unlocked(id)
##   為單一 id 的布林查詢 -- 圖鑑館 UI 讀「發現/解鎖狀態」所需的最小介面。
##
## CollectionViewModel 這個 class_name 目前不存在。若直接在頂層寫
## `CollectionViewModel.new(...)`,GDScript 靜態解析會在「載入這個測試腳本」
## 當下就丟出 Parse Error,而 GUT 對載入失敗的腳本是整檔靜默排除、不計入
## 失敗數(exit code 仍為 0)-- 這樣反而看不出紅燈(見
## tests/unit/meta_progression/test_run_discovery_log.gd 同一段說明,以及
## 這兩份測試檔第一版曾實際驗證此行為:script parse error 使腳本被 GUT
## 標記「不是 GutTest」而整檔跳過,不計入 83 條既有測試的失敗數)。改用
## load() 動態載入:檔案不存在時 load() 在執行期回傳 null,讓
## assert_not_null() 成為一個會被 GUT 正確計入失敗數的斷言;
## CollectionViewModel 一旦存在,同一份測試會改走 script.new(profile) 動態
## 建構,驗證實際行為。

const SCRIPT_PATH := "res://presentation/viewmodels/collection_view_model.gd"


func test_discovered_ids_for_category_filters_by_prefix_and_preserves_order() -> void:
	var script := _load_script()
	if script == null: return
	var profile := SaveRootFixture.create_valid_root().profile
	profile.discovered_content_ids = [
		&"relic.alpha", &"unit.enemy", &"unit.fixture",
	]
	var view_model: Object = script.new(profile)
	assert_eq(
		view_model.call("discovered_ids_for_category", &"unit"),
		[&"unit.enemy", &"unit.fixture"]
	)
	assert_eq(
		view_model.call("discovered_ids_for_category", &"relic"),
		[&"relic.alpha"]
	)


func test_discovered_ids_for_category_is_empty_for_unknown_category() -> void:
	var script := _load_script()
	if script == null: return
	var profile := SaveRootFixture.create_valid_root().profile
	profile.discovered_content_ids = [&"unit.fixture"]
	var view_model: Object = script.new(profile)
	var equipment_ids: Array = view_model.call("discovered_ids_for_category", &"equipment")
	assert_eq(equipment_ids, [])


func test_unlocked_ids_for_category_filters_by_prefix() -> void:
	var script := _load_script()
	if script == null: return
	var profile := SaveRootFixture.create_valid_root().profile
	profile.unlocked_content_ids = [&"commander.fixture", &"commander.second"]
	var view_model: Object = script.new(profile)
	assert_eq(
		view_model.call("unlocked_ids_for_category", &"commander"),
		[&"commander.fixture", &"commander.second"]
	)


func test_is_discovered_reflects_membership_in_profile_discovered_content_ids() -> void:
	var script := _load_script()
	if script == null: return
	var profile := SaveRootFixture.create_valid_root().profile
	profile.discovered_content_ids = [&"unit.fixture"]
	var view_model: Object = script.new(profile)
	assert_true(view_model.call("is_discovered", &"unit.fixture"))
	assert_false(view_model.call("is_discovered", &"unit.enemy"))


func test_is_unlocked_reflects_membership_in_profile_unlocked_content_ids() -> void:
	var script := _load_script()
	if script == null: return
	var profile := SaveRootFixture.create_valid_root().profile
	profile.unlocked_content_ids = [&"commander.fixture"]
	var view_model: Object = script.new(profile)
	assert_true(view_model.call("is_unlocked", &"commander.fixture"))
	assert_false(view_model.call("is_unlocked", &"commander.second"))


func test_view_model_holds_a_clone_not_a_live_profile_reference() -> void:
	# Mirrors trait_preview_view_model.gd's documented convention: a ViewModel
	# only ever holds a clone/snapshot, never a mutable reference back into
	# live domain state.
	var script := _load_script()
	if script == null: return
	var profile := SaveRootFixture.create_valid_root().profile
	profile.discovered_content_ids = [&"unit.fixture"]
	var view_model: Object = script.new(profile)
	profile.discovered_content_ids.append(&"unit.enemy")
	assert_false(view_model.call("is_discovered", &"unit.enemy"))


## Loads presentation/viewmodels/collection_view_model.gd dynamically so a
## not-yet-existing class produces a normal, GUT-countable failing assertion
## (load() -> null at runtime) instead of a script-load Parse Error that
## silently excludes the whole file from the run (see header comment).
func _load_script() -> GDScript:
	var script := load(SCRIPT_PATH) as GDScript
	assert_not_null(
		script,
		"CollectionViewModel (%s) must exist and take a ProfileState in its constructor" % SCRIPT_PATH
	)
	return script
