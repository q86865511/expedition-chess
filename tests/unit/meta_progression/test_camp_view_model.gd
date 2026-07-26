extends GutTest

## T11 (specs/meta-progression/design.md §4.4; requirements.md S5-AC-001; tasks.md T11;
## design.md §12 test case 001 "test_camp_view_model_derives_all_facilities_from_single_
## profile") — CampViewModel is the single read-only projection the Camp gray box's five
## facilities (遠征門/指揮官廳/圖鑑館/解鎖工坊/挑戰碑) read from; design.md §4.4 enumerates
## exactly what each facility's fields derive from, all out of one ProfileState.
##
## 假設聲明（design.md 列出五設施各自要顯示什麼，但未給 CampViewModel 的確切方法簽章，以下
## 為 test-author 的 binding decision，沿用既有 ExpeditionGateViewModel／CollectionViewModel
## 的既定命名與「只持 clone」慣例）：
## 1. 新型別 CampViewModel（RefCounted），路徑 presentation/viewmodels/camp_view_model.gd。
## 2. _init(profile: ProfileState)：只持 profile 的 deep_clone（同
##    presentation/viewmodels/collection_view_model.gd 的既定慣例），不需要 registry ——
##    design.md §4.4 對 CampViewModel 五設施的描述（last_selection／unlocked_content_ids／
##    discovered_content_ids／meta_currency／commander_challenge_records／
##    highest_challenge_level）全部是 ProfileState 自身欄位，不像 ExpeditionGateViewModel
##    的「生效詞綴清單」子功能需要解析內容——CampViewModel 明確不含該子功能（那屬
##    ExpeditionGateViewModel 自己的職責，design.md §3 模組圖將兩者並列為獨立 ViewModel）。
## 3. 五設施各自的讀取方法：
##    - 遠征門：expedition_gate_last_selection() -> ProfileLastSelectionState（可 null）、
##      expedition_gate_highest_cleared_level(commander_id: StringName) -> int（無紀錄回 0，
##      沿用 expedition_gate_view_model.gd:38-42 完全相同的既定語意）。
##    - 指揮官廳：commander_hall_unlocked_commander_ids() -> Array[StringName]（
##      unlocked_content_ids 濾 category=="commander"，沿用 collection_view_model.gd 的
##      「id 第一個 '.' 前的區段為 category」既定慣例，保留原陣列相對順序）。
##    - 圖鑑館：collection_discovered_ids_for_category(category)／
##      collection_unlocked_ids_for_category(category) -> Array[StringName]（同一濾法，
##      任意 category，不限 commander）。
##    - 解鎖工坊：unlock_workshop_currency() -> int（=meta_currency）、
##      unlock_workshop_unlocked_content_ids() -> Array[StringName]（design.md §4.3
##      「購買紀錄＝unlocked_content_ids，由 CampViewModel 解鎖工坊讀出」——與
##      unlocked_content_ids 全量相同，不濾 category，因為解鎖工坊涵蓋各類可購內容）。
##    - 挑戰碑：challenge_monument_records() -> Array[CommanderChallengeRecordState]（
##      commander_challenge_records 的 deep_clone 陣列）、
##      challenge_monument_highest_challenge_level() -> int（=highest_challenge_level）。
##
## GUT 陷阱：CampViewModel 目前不存在，直接以 class_name 頂層引用會讓整檔 parse error 被
## GUT 靜默排除（不計入失敗數）。比照 tests/unit/meta_progression/test_collection_view_model.gd
## 的 load() 動態載入寫法。

const SCRIPT_PATH := "res://presentation/viewmodels/camp_view_model.gd"


func test_all_five_facilities_derive_from_the_same_profile_state() -> void:
	var script := _load_script()
	if script == null:
		return
	var profile := _profile(
		&"commander.alpha", 2, 250,
		[&"commander.alpha", &"commander.beta", &"unit.recruit_a", &"relic.charm"],
		[&"unit.recruit_a", &"relic.charm"],
		3,
		[
			CommanderChallengeRecordState.new(&"commander.alpha", 3),
			CommanderChallengeRecordState.new(&"commander.beta", 1),
		]
	)
	var view_model: Object = script.new(profile)

	# 遠征門
	var last_selection: ProfileLastSelectionState = view_model.call("expedition_gate_last_selection")
	assert_not_null(last_selection)
	if last_selection != null:
		assert_eq(last_selection.commander_id, &"commander.alpha")
		assert_eq(last_selection.challenge_level, 2)
	assert_eq(view_model.call("expedition_gate_highest_cleared_level", &"commander.alpha"), 3)
	assert_eq(view_model.call("expedition_gate_highest_cleared_level", &"commander.beta"), 1)
	assert_eq(
		view_model.call("expedition_gate_highest_cleared_level", &"commander.unrecorded"), 0,
		"a commander with no challenge record must read as highest cleared level 0"
	)

	# 指揮官廳：濾 category==commander，保留原順序
	assert_eq(
		view_model.call("commander_hall_unlocked_commander_ids"),
		[&"commander.alpha", &"commander.beta"]
	)

	# 圖鑑館：按類別讀發現／解鎖
	assert_eq(view_model.call("collection_discovered_ids_for_category", &"unit"), [&"unit.recruit_a"])
	assert_eq(view_model.call("collection_discovered_ids_for_category", &"relic"), [&"relic.charm"])
	assert_eq(
		view_model.call("collection_unlocked_ids_for_category", &"commander"),
		[&"commander.alpha", &"commander.beta"]
	)

	# 解鎖工坊：貨幣 + 購買紀錄（=unlocked_content_ids 全量）
	assert_eq(view_model.call("unlock_workshop_currency"), 250)
	assert_eq(
		view_model.call("unlock_workshop_unlocked_content_ids"),
		[&"commander.alpha", &"commander.beta", &"unit.recruit_a", &"relic.charm"]
	)

	# 挑戰碑：per-commander 紀錄 + 整體最高階
	var records: Array = view_model.call("challenge_monument_records")
	assert_eq(records.size(), 2)
	assert_eq(view_model.call("challenge_monument_highest_challenge_level"), 3)


## design.md §4.4「無第二資料源」的具體翻譯：改一個 profile 的值，所有五設施的讀出值都要
## 跟著變——若某設施的方法其實是從別的物件（而非傳入的這個 profile）讀資料，這條測試會抓到。
func test_changing_the_profile_changes_every_facility_view() -> void:
	var script := _load_script()
	if script == null:
		return
	var profile_a := _profile(
		&"commander.alpha", 0, 10, [&"commander.alpha"], [], 0, []
	)
	var view_model_a: Object = script.new(profile_a)

	var profile_b := _profile(
		&"commander.beta", 4, 999,
		[&"commander.alpha", &"commander.beta", &"commander.gamma"],
		[&"commander.gamma"],
		5,
		[CommanderChallengeRecordState.new(&"commander.beta", 5)]
	)
	var view_model_b: Object = script.new(profile_b)

	var last_selection_a: ProfileLastSelectionState = view_model_a.call("expedition_gate_last_selection")
	var last_selection_b: ProfileLastSelectionState = view_model_b.call("expedition_gate_last_selection")
	assert_ne(last_selection_a.commander_id, last_selection_b.commander_id)
	assert_ne(
		view_model_a.call("commander_hall_unlocked_commander_ids").size(),
		view_model_b.call("commander_hall_unlocked_commander_ids").size()
	)
	assert_ne(
		view_model_a.call("collection_unlocked_ids_for_category", &"commander"),
		view_model_b.call("collection_unlocked_ids_for_category", &"commander")
	)
	assert_ne(view_model_a.call("unlock_workshop_currency"), view_model_b.call("unlock_workshop_currency"))
	assert_ne(
		view_model_a.call("challenge_monument_highest_challenge_level"),
		view_model_b.call("challenge_monument_highest_challenge_level")
	)


## 「只持 clone」慣例（同 collection_view_model.gd:99-109 已鎖的既有測試模式）：建構後修改
## 呼叫端手上的 profile 物件，不得反映到已建好的 ViewModel 讀出值——否則就是持了活引用而非
## snapshot，形同第二資料源的另一種樣貌（沿用同一份 profile 物件、事後修改）。
func test_view_model_holds_a_clone_not_a_live_profile_reference() -> void:
	var script := _load_script()
	if script == null:
		return
	var profile := _profile(&"commander.alpha", 0, 10, [&"commander.alpha"], [], 0, [])
	var view_model: Object = script.new(profile)
	profile.meta_currency = 99999
	profile.unlocked_content_ids.append(&"commander.zzz_added_after_construction")
	assert_eq(view_model.call("unlock_workshop_currency"), 10)
	assert_eq(
		view_model.call("commander_hall_unlocked_commander_ids"),
		[&"commander.alpha"]
	)


func test_expedition_gate_last_selection_is_null_for_a_profile_that_never_started_a_run() -> void:
	var script := _load_script()
	if script == null:
		return
	var profile := ProfileState.new(
		SaveRootFixture.PROFILE_ID, U64Bits.one(), 0, [], [], 0, [], &"settings.default", null, []
	)
	var view_model: Object = script.new(profile)
	assert_null(view_model.call("expedition_gate_last_selection"))


func _profile(
	last_selection_commander: StringName,
	last_selection_challenge: int,
	currency: int,
	unlocked: Array[StringName],
	discovered: Array[StringName],
	highest_challenge_level: int,
	records: Array[CommanderChallengeRecordState]
) -> ProfileState:
	var settlements: Array[SettlementReceiptState] = []
	return ProfileState.new(
		SaveRootFixture.PROFILE_ID, U64Bits.one(), currency, unlocked, discovered,
		highest_challenge_level, settlements, &"settings.default",
		ProfileLastSelectionState.new(last_selection_commander, last_selection_challenge),
		records
	)


func _load_script() -> GDScript:
	var script := load(SCRIPT_PATH) as GDScript
	assert_not_null(
		script,
		"CampViewModel (%s) must exist and take a ProfileState in its constructor" % SCRIPT_PATH
	)
	return script
