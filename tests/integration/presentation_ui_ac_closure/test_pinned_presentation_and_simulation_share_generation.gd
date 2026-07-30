extends GutTest

const Support := preload(
	"res://tests/integration/presentation_ui_ac_closure/ac_closure_test_support.gd"
)


func test_pinned_presentation_and_simulation_share_generation() -> void:
	var result_source := FileAccess.get_file_as_string(Support.BOOTSTRAP_RESULT_PATH)
	assert_true(
		result_source.contains(
			"func definition_view(content_id: StringName) -> ContentDefinitionView"
		),
		"AC-024/075 require a clone-only definition view without exposing raw registry"
	)
	assert_true(
		result_source.contains("func battle_catalog_snapshot() -> BattleRuleCatalog"),
		"AC-024/075 require a clone-only pinned battle catalog accessor"
	)
	var registry := autofree(ContentRegistryService.new()) as ContentRegistryService
	var content := ProjectContentBootstrap.new().run(registry)
	content.release_registry_ownership()
	assert_true(content.ok, String(content.error_code))
	if not content.ok:
		return
	if not Support.require_methods(
		self,
		content,
		[&"definition_view", &"battle_catalog_snapshot"],
		"ProjectContentBootstrapResult pinned projection"
	):
		return
	var unit_id: StringName = content.player_unit_ids[0]
	var view_a: Variant = content.call(&"definition_view", unit_id)
	var view_b: Variant = content.call(&"definition_view", unit_id)
	assert_true(view_a is ContentDefinitionView)
	assert_true(view_b is ContentDefinitionView)
	if not view_a is ContentDefinitionView or not view_b is ContentDefinitionView:
		return
	var original_health := _view_health(view_b)
	assert_gt(original_health, 0)
	assert_eq(String(view_a.manifest_digest), content.manifest_digest)
	assert_eq(String(view_b.manifest_digest), content.manifest_digest)

	var catalog_a: Variant = content.call(&"battle_catalog_snapshot")
	var catalog_b: Variant = content.call(&"battle_catalog_snapshot")
	assert_true(catalog_a is BattleRuleCatalog)
	assert_true(catalog_b is BattleRuleCatalog)
	if not catalog_a is BattleRuleCatalog or not catalog_b is BattleRuleCatalog:
		return
	assert_ne(catalog_a, catalog_b, "two presentation consumers may not alias catalog")
	assert_eq(catalog_a.manifest_digest_value(), content.manifest_digest)
	assert_eq(catalog_b.manifest_digest_value(), content.manifest_digest)
	var rule_a: Variant = catalog_a.try_unit_rule(unit_id)
	var rule_b: Variant = catalog_b.try_unit_rule(unit_id)
	assert_not_null(rule_a)
	assert_not_null(rule_b)
	if rule_a == null or rule_b == null:
		return
	rule_a.base_stats.health = 999999
	assert_ne(
		catalog_b.try_unit_rule(unit_id).base_stats.health,
		999999,
		"catalog snapshots must be clone-only"
	)

	var before := _result_for_health(original_health, content.manifest_digest)
	view_a.payload.children[5].children[0].int_value = 999999
	var fresh_view: Variant = content.call(&"definition_view", unit_id)
	assert_eq(_view_health(fresh_view), original_health)
	assert_eq(String(fresh_view.manifest_digest), content.manifest_digest)
	var after := _result_for_health(_view_health(fresh_view), content.manifest_digest)
	assert_not_null(before)
	assert_not_null(after)
	if before == null or after == null:
		return
	assert_eq(after.result_hash, before.result_hash)
	assert_eq(after.summary_hash, before.summary_hash)


func _view_health(view: Variant) -> int:
	if not view is ContentDefinitionView or view.payload == null:
		return 0
	return int(view.payload.children[5].children[0].int_value)


func _result_for_health(health: int, digest: String) -> BattleResult:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.manifest_digest = StringName(digest)
	inputs.encounter_snapshot.manifest_digest = StringName(digest)
	inputs.player_units[0].health = health
	var setup := BattleSimulationFixture.build_setup(inputs)
	return BattleSimulationFixture.run_to_result(setup) if setup != null else null
