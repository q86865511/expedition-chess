class_name RngSnapshot
extends RefCounted

var rng_version: int = 1
var state: U64Bits = null
var inc: U64Bits = null
var counter: U64Bits = null

static func create(version: int, current_state: U64Bits, increment: U64Bits, raw_counter: U64Bits) -> RngSnapshotResult:
	if version != 1 or current_state == null or increment == null or raw_counter == null or not increment.is_odd():
		return RngSnapshotResult.failure(&"RNG_SNAPSHOT_INVALID", &"snapshot")
	return RngSnapshotResult.success(_create_unchecked(version, current_state, increment, raw_counter))

static func _create_unchecked(version: int, current_state: U64Bits, increment: U64Bits, raw_counter: U64Bits) -> RngSnapshot:
	var value := RngSnapshot.new()
	value.rng_version = version
	value.state = current_state.deep_clone()
	value.inc = increment.deep_clone()
	value.counter = raw_counter.deep_clone()
	return value

func deep_clone() -> RngSnapshot:
	return _create_unchecked(rng_version, state, inc, counter)

func equals(other: RngSnapshot) -> bool:
	return other != null and rng_version == other.rng_version and state.equals(other.state) and inc.equals(other.inc) and counter.equals(other.counter)
