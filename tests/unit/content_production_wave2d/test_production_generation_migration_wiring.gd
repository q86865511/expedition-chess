extends GutTest

## B3 回歸:正式 boot 的 SaveRepository 組裝必須帶 codec 2→3 generation migration
## port。先前只傳 receipt/id migration 兩個 port,歷史 schema 3／codec 2 save 一律
## PORT_UNCONFIGURED → incompatible_preserved(歷史 fixture 測試會綠,只因為測試
## 自己注入了 port)。本測試走的是正式路徑:正式 bootstrap 安裝內容 →
## ProductionContentGenerationMigrationPortBuilder 封裝 → SaveRepository
## `_configure_content_ports`,再用 5e78ccf 的 fixture bytes 實際 load。
##
## B4 回歸(第三複驗):migration 成功後必須依 mapping 就地改寫／移除 raw run 內
## 的每一個引用面,不能只換 content_snapshot。`run.discovered_content_ids` 是
## codex 指出的具體繞過面:ALIAS 必須真的改名、OPTIONAL TOMBSTONE 必須真的移除;
## 任何一個引用面沒有 mapping 就必須 incompatible-preserved。

const FIXTURE_PATH := \
	"res://tests/fixtures/save/content_production/5e78ccf.schema3.codec2.json"

var _registry: ContentRegistryService
var _content: ProjectContentBootstrapResult
var _port: ContentGenerationMigrationPortV2


func before_all() -> void:
	_registry = ContentRegistryService.new()
	_content = ProjectContentBootstrap.new().run(_registry)
	if not _content.ok:
		return
	_content.release_registry_ownership()
	_port = ProductionContentGenerationMigrationPortBuilder.new().build(
		_registry, _content.receipt, _content.localization_catalog
	)


func after_all() -> void:
	if _registry != null:
		_registry.free()
		_registry = null


func test_production_repository_upgrades_historical_schema3_codec2_save() -> void:
	if not _require_content():
		return
	assert_not_null(
		_content.localization_catalog,
		"正式 bootstrap 必須把安裝中的 localization catalog 交出來"
	)
	var loaded := _load(_source())
	assert_true(loaded.ok, "歷史 save 必須可載入")
	if not loaded.ok:
		return
	assert_eq(
		loaded.run_status,
		LoadResult.RunStatus.LOADED,
		"接上 production port 後不得再落回 incompatible_preserved"
	)
	if loaded.run == null:
		return
	assert_eq(loaded.run.content_snapshot.catalog_schema_version_value(), 2)
	assert_eq(loaded.run.content_snapshot.content_codec_version_value(), 3)
	assert_eq(
		loaded.run.content_snapshot.manifest_digest_value(),
		_content.manifest_digest
	)
	assert_eq(
		loaded.run.commander_id,
		&"commander.slice_c0",
		"歷史 commander id 必須依宣告表 alias 到正式指揮官"
	)


## codex 繞過構造 1:ALIAS 過的 id 留在 run.discovered_content_ids。
func test_aliased_discovered_content_id_is_rewritten_in_the_run() -> void:
	if not _require_content():
		return
	var source := _source()
	source.run.discovered_content_ids = ["commander.fixture"]
	var loaded := _load(source)
	assert_true(loaded.ok)
	if not loaded.ok or loaded.run == null:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	assert_eq(loaded.run.discovered_content_ids.size(), 1)
	if loaded.run.discovered_content_ids.is_empty():
		return
	assert_eq(
		loaded.run.discovered_content_ids[0],
		&"commander.slice_c0",
		"ALIAS 必須改寫 run 內的引用,不得只換 content_snapshot"
	)


## codex 繞過構造 2:OPTIONAL TOMBSTONE 的 id 留在 run.discovered_content_ids。
func test_tombstoned_discovered_content_id_is_removed_from_the_run() -> void:
	if not _require_content():
		return
	var source := _source()
	source.run.discovered_content_ids = ["relic.fixture"]
	var loaded := _load(source)
	assert_true(loaded.ok)
	if not loaded.ok or loaded.run == null:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	assert_true(
		loaded.run.discovered_content_ids.is_empty(),
		"OPTIONAL TOMBSTONE 必須從 codex 集合移除,不得保留舊 id"
	)


func test_unmapped_roster_unit_def_is_preserved_incompatible() -> void:
	if not _require_content():
		return
	var source := _source()
	source.run.roster_state.unit_instances = [{"def_id": "unit.unmapped"}]
	_assert_incompatible(source, "roster unit def")


func test_unmapped_map_node_def_is_preserved_incompatible() -> void:
	if not _require_content():
		return
	var source := _source()
	source.run.map_state.nodes = [
		{"def_id": "map_node.unmapped", "encounter_preview": null},
	]
	_assert_incompatible(source, "map node def")


func test_unmapped_discovered_content_id_is_preserved_incompatible() -> void:
	if not _require_content():
		return
	var source := _source()
	source.run.discovered_content_ids = ["unit.unmapped"]
	_assert_incompatible(source, "discovered content id")


func test_production_port_rejects_unknown_source_generation() -> void:
	if not _require_content():
		return
	var empty: Array[StringName] = []
	var references: Array[ContentGenerationMigrationReference] = [
		ContentGenerationMigrationReference.new(
			&"economy_config", &"economy.fixture",
			&"run.content_snapshot.economy_config_id", true
		),
	]
	var enabled: Array[StringName] = [&"economy.fixture"]
	var request := ContentGenerationMigrationRequest.new(
		"0.1.0-unlisted",
		"f".repeat(64),
		enabled,
		&"economy.fixture",
		empty,
		empty,
		empty,
		&"meta.fixture",
		1,
		2,
		references
	)
	var result := _port.migrate_generation(request)
	assert_false(result.ok, "未列入 allowlist 的來源世代不得升級")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.PACK_MISSING)


func _assert_incompatible(source: Dictionary, face: String) -> void:
	var loaded := _load(source)
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(
		loaded.run_status,
		LoadResult.RunStatus.INCOMPATIBLE_PRESERVED,
		"%s 沒有 mapping 時必須保留原 bytes 而不是靜默升級" % face
	)


func _require_content() -> bool:
	var ready := _content != null and _content.ok
	assert_true(
		ready,
		String(_content.error_code) if _content != null else "bootstrap missing"
	)
	return ready


func _source() -> Dictionary:
	return JSON.parse_string(_fixture_text())


func _load(source: Dictionary) -> LoadResult:
	var storage := FakeSaveStorage.new()
	storage.seed_file(
		StorageFaultKey.MAIN, JSON.stringify(source).to_utf8_buffer()
	)
	var repository := SaveRepository.new(storage)
	add_child_autofree(repository)
	var configured := repository._configure_content_ports(
		ContentRegistryReceiptAdapter.new(_registry),
		ContentRegistryMigrationAdapter.new(_registry),
		_port
	)
	assert_true(configured.ok)
	return repository.load()


func _fixture_text() -> String:
	var handle := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	return handle.get_as_text() if handle != null else ""
