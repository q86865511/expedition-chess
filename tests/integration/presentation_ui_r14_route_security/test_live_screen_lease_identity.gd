extends GutTest


func test_manual_and_foreign_leases_cannot_forge_active_identity() -> void:
	var registry_a := LiveScreenLeaseRegistry.new()
	var registry_b := LiveScreenLeaseRegistry.new()
	var lease_a := registry_a.activate(AppStateMachine.State.RUN, 51)
	var lease_b := registry_b.activate(AppStateMachine.State.RUN, 51)
	var manual := LiveScreenLease.new(
		lease_a.lease_id,
		lease_a.parent_state,
		lease_a.route_generation
	)
	assert_false(
		registry_a.is_active(manual),
		"copying predictable public fields must not forge an active lease"
	)
	assert_false(
		registry_b.is_active(lease_a),
		"a different registry must reject a field-colliding foreign lease"
	)
	assert_true(registry_b.is_active(lease_b))


func test_issued_clone_is_valid_but_becomes_stale_after_reactivation() -> void:
	var registry := LiveScreenLeaseRegistry.new()
	var first := registry.activate(AppStateMachine.State.RUN, 61)
	var issued_clone := first.deep_clone()
	assert_true(
		registry.is_active(issued_clone),
		"issuer-bearing deep clones are required by live ports"
	)
	var second := registry.activate(AppStateMachine.State.RUN, 62)
	assert_false(registry.is_active(issued_clone))
	assert_true(registry.is_active(second.deep_clone()))
