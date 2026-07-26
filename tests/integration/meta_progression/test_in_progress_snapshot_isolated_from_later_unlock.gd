extends GutTest

## T10 (specs/meta-progression) — S5-AC-005 進行中快照隔離（design.md §4.2、§2；
## requirements.md S5-AC-005；tasks.md T10 驗收欄「進行中 run（lease）購新解鎖後內容池不變、
## 新 run 才套用」）：組合 wave3 的 StartExpeditionCommand／RunBootstrapService 與 wave2 的
## PurchaseUnlockCommand／UnlockPurchaseService，證明「局外解鎖」（純 ProfileState 操作）
## 不會影響一個已經在跑的 RunState 的 content_snapshot，且同一 profile 之後開的新遠征才看得
## 到新解鎖的內容。
##
## ============================== 假設聲明／已知情況（務必在派工回報中轉達） ==============================
## 1. 【誠實揭露：本檔測試預期本來就是綠燈，不貢獻紅燈證據】StartExpeditionCommand、
##    RunBootstrapService、PurchaseUnlockCommand、UnlockPurchaseService 皆為 wave2/wave3
##    已完成、已鎖定的既有實作（非本任務新增）。requirements.md 對 REQ-META-003 的擁有權表
##    明確寫「partial（快照釘選/lease 機制屬 S1 已驗 AC-078；S5 擁有局外解鎖端行為與
##    AC-023）」——S1 的 catalog lease/pinning 機制與 S5(T04/T05) 的「解鎖只動
##    ProfileState.unlocked_content_ids、完全不接觸 RunState」的指令簽章設計，兩者疊加後，
##    S5-AC-005 描述的隔離性質在 wave2/wave3 完成當下就已經結構性成立
##    （PurchaseUnlockCommand.apply_to(profile: ProfileState) 的簽章本身就不接受也不可能
##    觸碰任何 RunState 物件）。本檔是 T10 任務清單指定的驗收項（tasks.md T10 依賴
##    T07/T08，屬 wave5，晚於 T04/T05 的 wave2/wave3），其角色是「補齊 S5-AC-005 的端到端
##    整合證明」，不是在測試某個尚未實作的新行為——實際執行極可能一開始就是綠燈（PASS），
##    這點已用 domain 既有原始碼逐一核對確認（見下方第 2 點的具體推導），不是本檔測試作者
##    寫錯或偷懶。紅燈證據由本次交付的其餘 4 個 content_validation 測試檔提供，本檔的角色是
##    覆蓋 T10 任務清單「進行中 run（lease）購新解鎖後內容池不變、新 run 才套用」這行字面
##    驗收敘述、並在實作階段守住這條回歸線，即使當下就是綠的。
## 2. 「內容池不變」的具體觀察面：本檔比較 RunState.content_snapshot（ContentSnapshotState，
##    具 canonical_equals() 可直接逐欄比較，domain/run/content_snapshot_state.gd:347-358）
##    在一次 PurchaseUnlockCommand 執行前後是否維持不變；「新 run 才套用」則借用
##    StartExpeditionCommand 既有的 EXPEDITION_COMMANDER_LOCKED 檢查作為可觀察代理——解鎖
##    前用尚未解鎖的指揮官開局必須被拒絕，解鎖後用同一位指揮官開局必須成功，藉此證明「解鎖」
##    確實只對「新開的遠征」生效。本檔刻意不透過 ContentRegistryService 模擬兩個不同的
##    content generation（D1/D2）：StartExpeditionTestFixture 的 receipt()/catalog() 是與
##    ContentRegistryService 脫鉤的靜態 fixture（詳見該檔標頭），且 design.md §7.3／
##    StartExpeditionCommand 的既有邏輯顯示「解鎖」在本架構下純粹是 profile 端的可見性/
##    存取控制（unlocked_content_ids 是否含某 id），不要求對應內容真的隸屬一個新的 content
##    manifest generation——真正測試「同一 registry 內新舊 generation 皆可正確 resolve」是
##    ContentRegistryService 自己的既有覆蓋（_case_registry_pinning，
##    tests/fixtures/content/content_verification_suite.gd:154-193，經
##    tests/unit/content_registry/test_content_registry.gd:11 執行、現行已綠），不是 T10
##    的新職責，重複測試無助於捕捉新缺陷。
## 3. 本檔直接呼叫 StartExpeditionCommand.apply_to()／PurchaseUnlockCommand.apply_to()
##    （command 層），不經過 CampController.dispatch()／dispatch_start_expedition()：
##    CampController 的兩個 dispatch 方法各自建構「run=null」或「run=新建」的 SaveRoot 並
##    整份覆蓋持久化狀態（camp_controller.gd:95/146-148）——同一個 CampController 實例若先
##    dispatch_start_expedition() 再 dispatch()（PurchaseUnlockCommand），第二次呼叫會把
##    persisted SaveRoot 的 run 欄位覆寫為 null（CampSaveRootFactory.build() 恆為
##    run=null）。這不是本檔要測的東西：AppRoot 的既有 composition 規則是「有 active run
##    時建 RunController，否則才建 CampController」（design.md §4.4），現實流程中不會在
##    同一個 profile 上對「已有 active run」重複呼叫 CampController.dispatch()。本檔聚焦
##    S5-AC-005 字面描述的「內容池隔離」，故在 COMMAND 層直接組裝情境，避開這個與本 AC 無關
##    的 CampController 儲存層邊界案例（該邊界案例不在 T10 範圍內，若有需要應屬另一個任務）。
## ============================================================================================================

func test_in_progress_run_content_snapshot_unaffected_by_later_unlock_purchase() -> void:
	var profile_0 := StartExpeditionTestFixture.base_profile(
		5, [StartExpeditionTestFixture.COMMANDER_ALPHA_ID]
	)
	var start_a := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)
	var result_a := start_a.apply_to(profile_0)
	assert_true(result_a.ok, "run A 建立必須成功")
	if not result_a.ok:
		return
	var run_a := result_a.run
	var profile_1 := result_a.profile
	var snapshot_before := run_a.content_snapshot.deep_clone()

	# beta 尚未解鎖：以 beta 另開新遠征必須被拒絕（購買解鎖前的對照基準）。
	var start_b_before := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_BETA_ID,
		StartExpeditionTestFixture.commander_beta(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)
	var result_b_before := start_b_before.apply_to(profile_1)
	assert_false(result_b_before.ok, "beta 解鎖前必須拒絕以 beta 開局")
	if result_b_before.ok:
		return
	assert_eq(result_b_before.error.code, StartExpeditionError.EXPEDITION_COMMANDER_LOCKED)

	# 局外解鎖 beta（PurchaseUnlockCommand 只動 ProfileState，簽章上不可能碰到 run_a）。
	var unlock_def := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.test_grant_beta", 0, [], [StartExpeditionTestFixture.COMMANDER_BETA_ID]
	)
	var purchase_result := PurchaseUnlockCommand.new(unlock_def).apply_to(profile_1)
	assert_true(purchase_result.ok, "購買解鎖 beta 必須成功")
	if not purchase_result.ok:
		return
	var profile_2 := purchase_result.profile
	assert_true(profile_2.unlocked_content_ids.has(StartExpeditionTestFixture.COMMANDER_BETA_ID))

	# 進行中 run（run_a）的 content_snapshot 完全不受這次解鎖影響。
	assert_true(
		run_a.content_snapshot.canonical_equals(snapshot_before),
		"run A 的 content_snapshot 必須在購買解鎖後保持逐欄相等（進行中遠征內容池不變）"
	)
	assert_eq(
		run_a.content_snapshot.manifest_digest_value(),
		StartExpeditionTestFixture.receipt().manifest_digest
	)

	# 同 profile 的新遠征（run_b）在解鎖後才套用新指揮官。
	var start_b_after := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_BETA_ID,
		StartExpeditionTestFixture.commander_beta(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)
	var result_b_after := start_b_after.apply_to(profile_2)
	assert_true(result_b_after.ok, "beta 解鎖後開局必須成功（同 profile 的新遠征才套用新解鎖）")
	if not result_b_after.ok:
		return
	assert_eq(result_b_after.run.commander_id, StartExpeditionTestFixture.COMMANDER_BETA_ID)
	assert_eq(
		run_a.content_snapshot.manifest_digest_value(),
		result_b_after.run.content_snapshot.manifest_digest_value(),
		"本檔情境中「新解鎖」屬存取控制而非新 content generation，新舊 run 理應共享同一 pinned digest"
	)
