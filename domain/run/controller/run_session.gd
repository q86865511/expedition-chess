class_name RunSession
extends RefCounted

var _profile: ProfileState
var _canonical_run: RunState
var _publication_serial: U64Bits
var _catalog_lease: CatalogLease

func _init(
	p_profile: ProfileState,
	p_run: RunState,
	p_catalog_lease: CatalogLease,
	p_publication_serial: U64Bits = null
) -> void:
	_profile = p_profile.deep_clone()
	_canonical_run = p_run.deep_clone()
	_catalog_lease = p_catalog_lease
	_publication_serial = (
		p_publication_serial.deep_clone()
		if p_publication_serial != null
		else U64Bits.zero()
	)

func profile_snapshot() -> ProfileState:
	return _profile.deep_clone()

func run_snapshot() -> RunState:
	return _canonical_run.deep_clone()

func view_state() -> RunViewState:
	return RunViewState.from_run(_canonical_run, _publication_serial)

func committed_combat_snapshot() -> CombatCommittedSnapshot:
	return CombatCommittedSnapshot.new(
		_publication_serial,
		_canonical_run.run_phase,
		_canonical_run.run_seed,
		_canonical_run.resolution_state
	)

func publication_serial() -> U64Bits:
	return _publication_serial.deep_clone()

func can_publish() -> bool:
	return not _publication_serial.equals(U64Bits.max_value())

func has_catalog_pin() -> bool:
	return _catalog_lease != null \
		and _canonical_run != null \
		and _canonical_run.content_snapshot != null \
		and _catalog_lease.manifest_digest == _canonical_run.content_snapshot.manifest_digest_value() \
		and _catalog_lease.is_active()

## Swaps in the newly committed run (and, when provided, the profile carrying
## its T09 discovery union) only after the save succeeded, keeping the in-memory
## snapshot consistent with what was just persisted. profile stays untouched
## when null so non-discovery callers keep the run's existing profile.
func _commit_saved_draft(draft: RunState, profile: ProfileState = null) -> RunViewState:
	_canonical_run = draft.deep_clone()
	if profile != null:
		_profile = profile.deep_clone()
	_publication_serial = _publication_serial.add(U64Bits.one())
	return view_state()
