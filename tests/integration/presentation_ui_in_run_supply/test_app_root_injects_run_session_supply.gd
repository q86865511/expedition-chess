extends GutTest

## in-run-hud T10 上游：AppRoot 是 RunPresentationSession 鍛造／商店供給的唯一注入點。
##
## 單元測試證明 session 的讀取面與 domain 同源，但那是自己組出來的 session。這裡走
## 正式 composition（main.tscn ＋ 真 SaveRepository／SettingsRepository），確認
## app_root.gd 的建構點真的把 pinned ForgeRecipeTable／EconomyExpeditionCatalog／
## RunRelicTable／RunSession 傳了進去——少傳任何一個，畫面只會拿到空清單或
## GENERATION_MISMATCH，而那正是玩家看到「商店價格空白、合成永遠預覽不到」的成因。

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)
## 正式內容中的零件（content/packs/build_systems/equipment/arcane_ember.tres 的
## component_pair 之一）；forge table 若沒注入，這個查詢只會回空陣列。
const PRODUCTION_COMPONENT: StringName = &"item_component.arcane_dust"


func test_prepare_route_session_exposes_pinned_forge_and_shop_supply() -> void:
	var harness := Support.boot(self)
	assert_eq(harness.settings_bind_error, &"")
	assert_eq(harness.boot_error, &"")
	if not harness.settings_bind_error.is_empty() or not harness.boot_error.is_empty():
		return
	var driven := Support.drive_to_run_prepare(harness)
	assert_true(
		bool(driven.get("ok", false)),
		"production intent flow must reach RUN_PREPARE: %s"
		% String(driven.get("error", &""))
	)
	if not bool(driven.get("ok", false)):
		return
	await wait_process_frames(2)

	var session := harness.root.get(
		&"_run_presentation_session"
	) as RunPresentationSession
	assert_not_null(session)
	if session == null:
		return

	var recipes := session.forge_recipes_containing(PRODUCTION_COMPONENT)
	assert_false(
		recipes.is_empty(),
		"AppRoot 必須注入 pinned ForgeRecipeTable，否則合成預覽永遠是空的"
	)
	for rule: ForgeRecipeRule in recipes:
		assert_true(
			rule.component_ids.has(PRODUCTION_COMPONENT),
			"配方預覽必須是含該零件的配方"
		)

	var snapshot := session.snapshot()
	assert_not_null(snapshot)
	assert_not_null(snapshot.economy)
	if snapshot == null or snapshot.economy == null:
		return
	var status := session.shop_economy_status()
	assert_gt(status.gold_cap, 0, "AppRoot 必須注入 EconomyExpeditionCatalog")
	assert_eq(
		status.gold,
		snapshot.economy.gold,
		"經濟資訊列必須讀的是同一個 run 的 canonical 金幣"
	)
	assert_eq(status.level, snapshot.economy.level)

	var refresh := session.shop_refresh_quote()
	assert_ne(
		refresh.rejection_code,
		ShopError.GENERATION_MISMATCH,
		"報價供給與 run 必須是同一個 pinned 世代"
	)
	assert_ne(refresh.rejection_code, ShopError.INPUT_INVALID)
	assert_true(refresh.quotable, "刷新價必須算得出來（挑戰加價需 RunRelicTable）")
	assert_gt(refresh.gold_cost, 0)
