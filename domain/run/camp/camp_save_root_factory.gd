class_name CampSaveRootFactory
extends RefCounted

## T04 (design.md §4.1): the only factory that builds a profile-only (run ==
## null) SaveRoot. RunSaveRootFactory cannot, because it reads
## run.content_snapshot.content_version_value() (run_save_root_factory.gd:14),
## so camp transactions with no active run need content_version supplied
## directly. Mirrors RunSaveRootFactory's shape otherwise (rng_version = 1,
## hash_version = 1, saved_at_utc = clock.now_utc()). Scoped strictly to the
## "no active run" case PurchaseUnlockCommand needs; StartExpedition /
## MetaSettlement produce/clear an actual RunState and are out of scope here.

var _app_version: String
var _clock: RunCommitClock

func _init(p_app_version: String = "0.2.0", p_clock: RunCommitClock = null) -> void:
	_app_version = p_app_version
	_clock = p_clock if p_clock != null else RunCommitClock.new()

func build(profile: ProfileState, content_version: String) -> SaveRoot:
	return SaveRoot.new(
		SaveSchemaContract.CURRENT,
		content_version,
		_app_version,
		1,
		1,
		_clock.now_utc(),
		profile,
		null
	)
