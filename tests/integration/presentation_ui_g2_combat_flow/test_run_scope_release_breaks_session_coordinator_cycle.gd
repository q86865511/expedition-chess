extends GutTest

## G2 H2：RunPresentationSession 與 CombatCoordinator 互持強引用（兩者都是 RefCounted），
## 全 repo 原本沒有任何解綁——AppRoot 只把自己那一邊的參照設 null，整組 run 物件圖
## （session／coordinator／controller／RunSession／已提交 transcript）永不釋放。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_combat_flow/"
	+ "g2_combat_flow_test_support.gd"
)


func _controller() -> RunController:
	var root := SaveRootFixture.create_valid_root()
	return RunController.new(
		RunSession.new(root.profile, root.run, null),
		null
	)


func test_release_unbinds_both_directions_and_frees_the_object_graph() -> void:
	var coordinator := CombatCoordinator.new(_controller())
	var session := RunPresentationSession.new(
		_controller(), null, null, [], coordinator
	)
	var session_ref: WeakRef = weakref(session)
	var coordinator_ref: WeakRef = weakref(coordinator)

	session.release()
	assert_null(
		coordinator.get("_presentation_session"),
		"release must clear the coordinator side of the binding"
	)
	assert_null(
		session.get("_combat"),
		"release must clear the facade side of the binding"
	)

	session = null
	coordinator = null
	assert_null(session_ref.get_ref())
	assert_null(coordinator_ref.get_ref())


func test_release_drops_the_committed_transcript_with_the_run_scope() -> void:
	var session := RunPresentationSession.new()
	Support.install_transcript(
		self,
		session,
		Support.tick_events(8),
		Support.identity()
	)
	assert_true(session.try_playback().ok)
	session.release()
	var after := session.try_playback()
	assert_false(after.ok)
	assert_eq(
		Support.error_code(after),
		RunPresentationSession.PLAYBACK_NOT_AVAILABLE
	)


func test_app_root_release_unbinds_the_live_run_coordinator() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	var session: Variant = harness.root.get("_run_presentation_session")
	assert_not_null(session)
	if session == null:
		return
	var coordinator: Variant = session.get("_combat")
	assert_not_null(coordinator, "an active run always owns its combat coordinator")
	if coordinator == null:
		return
	assert_not_null(coordinator.get("_presentation_session"))

	harness.root.call(&"_release_active_run")

	assert_null(harness.root.get("_run_presentation_session"))
	assert_null(
		coordinator.get("_presentation_session"),
		"leaving the run scope must unbind the coordinator, not only the AppRoot field"
	)
	assert_null(session.get("_combat"))


func test_terminal_session_invalidation_also_unbinds_the_coordinator() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.start_run(harness).ok)
	var session: Variant = harness.root.get("_run_presentation_session")
	var coordinator: Variant = session.get("_combat") if session != null else null
	assert_not_null(coordinator)
	if coordinator == null:
		return

	# terminal settlement 先走 _invalidate_run_session，_release_active_run 之後才跑；
	# 解綁只掛在後者的話，終局路徑就漏掉了。
	harness.root.call(&"_invalidate_run_session")

	assert_null(harness.root.get("_run_presentation_session"))
	assert_null(coordinator.get("_presentation_session"))
