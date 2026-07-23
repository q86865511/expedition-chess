extends GutTest

# T11(S4 build-systems,免TDD:開發灰盒,驗收走 headless smoke 而非單元紅綠)
# 驗收測試,比照 tests/integration/combat/test_combat_lab.gd 與
# tests/integration/expedition/test_expedition_lab.gd 的既有慣例:
# 場景可載入、session 初始化成功(真正雙 pack 內容經 ContentRegistry 安裝＋
# pinned BattleRuleCatalog 接線),並跑一輪代表性操作流
# (鍛造／換裝／拆卸／overflow 處置／遺物替換)全部經 ViewModel 成功完成。
#
# T11 wave4:content/packs/vertical_slice/economy_configs/slice_default.tres 已補齊
# layer_income 等必填 TUNE 欄位,雙 pack 亦已新增 meta_reward_table 內容(見該
# pack README「T11 wave4 內容缺口修復」),遺物替換的「寫」(choose_slot())
# 現在應真正 dispatch 成功,不再是具名內容缺口的軟性拒絕。save/load 亦已改回
# ContentRegistryReceiptAdapter 正常路徑(見 build_lab_session.gd)。

func test_lab_scene_initializes_real_content_and_exposes_controls() -> void:
	var packed := load("res://scenes/dev/build_lab/build_lab.tscn") as PackedScene
	assert_not_null(packed)
	if packed == null: return
	var screen := packed.instantiate() as BuildLabScreen
	add_child_autofree(screen)
	await get_tree().process_frame
	assert_not_null(screen.get_node("%ForgeButton"))
	assert_not_null(screen.get_node("%EquipButton"))
	assert_not_null(screen.get_node("%DismantleButton"))
	assert_not_null(screen.get_node("%OverflowButton"))
	assert_not_null(screen.get_node("%RelicButton"))
	var log := screen.get_node("%LogLabel") as RichTextLabel
	assert_true(log.get_parsed_text().contains("就緒"), "Build Lab 應完成雙 pack 安裝並就緒")

func test_lab_operation_flow_forges_equips_dismantles_and_resolves_overflow() -> void:
	var packed := load("res://scenes/dev/build_lab/build_lab.tscn") as PackedScene
	var screen := packed.instantiate() as BuildLabScreen
	add_child_autofree(screen)
	await get_tree().process_frame

	var trait_before := screen.get_node("%TraitLabel") as RichTextLabel
	assert_true(
		trait_before.get_parsed_text().contains("trait.faction_verdant"),
		"UNIT_A/UNIT_B 共享 faction_verdant,羈絆預覽應與實戰同源顯示啟動門檻"
	)

	var forge_button := screen.get_node("%ForgeButton") as Button
	forge_button.pressed.emit()
	var log := screen.get_node("%LogLabel") as RichTextLabel
	assert_true(log.get_parsed_text().contains("鍛造 iron_plate ×2 → equipment.iron_iron：成功"))

	var equip_button := screen.get_node("%EquipButton") as Button
	equip_button.pressed.emit()
	assert_true(log.get_parsed_text().contains("把 equipment.frost_frost 裝到 UNIT_A：成功"))

	var dismantle_button := screen.get_node("%DismantleButton") as Button
	dismantle_button.pressed.emit()
	assert_true(log.get_parsed_text().contains("消耗 dismantle_kit 拆下 UNIT_B 的裝備：成功"))

	var overflow_button := screen.get_node("%OverflowButton") as Button
	overflow_button.pressed.emit()
	assert_true(log.get_parsed_text().contains("overflow tray 明確放棄一件零件：成功"))

	# 遺物替換的讀端(槽序快照＋待選替換候選)在渲染時已與實戰同源運作;
	# 這裡先確認「寫」之前槽 0 仍是原本的 relic.iron_will,且候選預覽已顯示
	# relic.shadow_veil。
	var relic_label := screen.get_node("%RelicLabel") as RichTextLabel
	assert_true(relic_label.get_parsed_text().contains("槽 0：relic.iron_will"))
	assert_true(relic_label.get_parsed_text().contains("待選替換候選：relic.shadow_veil"))

	var relic_button := screen.get_node("%RelicButton") as Button
	relic_button.pressed.emit()
	assert_true(log.get_parsed_text().contains(
		"遺物替換：槽 0 換成 relic.shadow_veil：成功"
	))
	# 真正 dispatch 成功後,槽 0 應已替換為 relic.shadow_veil。
	assert_true(relic_label.get_parsed_text().contains("槽 0：relic.shadow_veil"))

	# save/load 走 ContentRegistryReceiptAdapter 正常路徑(每次 dispatch 內部已
	# save() 落盤,這裡讀回驗證 receipt_port.compile_or_lookup() 的 decode 路徑可用)。
	var reload_result := screen.session_for_test().reload_from_storage_for_test()
	assert_true(reload_result.ok, "save/load 往返應成功")
	assert_eq(reload_result.run_status, LoadResult.RunStatus.LOADED, "應讀回已存的 run")
	assert_not_null(reload_result.run)
