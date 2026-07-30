class_name GodotAudioBusPort
extends AudioBusPort


func apply_batch(batch: AudioBusBatch) -> AudioBusBatchResult:
	if batch == null:
		return AudioBusBatchResult.failure(AUDIO_BUS_BATCH_INVALID)
	var expected := AudioBusKind.ordered_names()
	if batch.assignments.size() != expected.size():
		return AudioBusBatchResult.failure(AUDIO_BUS_BATCH_INVALID)
	var seen: Dictionary = {}
	var prepared: Array[AudioBusAssignment] = []
	for assignment: AudioBusAssignment in batch.assignments:
		if assignment == null:
			return AudioBusBatchResult.failure(AUDIO_BUS_VALUE_INVALID)
		var bus := assignment.bus
		if not expected.has(bus) or seen.has(bus):
			return AudioBusBatchResult.failure(AUDIO_BUS_BATCH_INVALID)
		seen[bus] = true
		if (
			assignment.volume_bps < 0
			or assignment.volume_bps > 10000
			or is_nan(assignment.volume_db)
		):
			return AudioBusBatchResult.failure(AUDIO_BUS_VALUE_INVALID)
		var bus_index := AudioServer.get_bus_index(bus)
		if bus_index < 0:
			return AudioBusBatchResult.failure(AUDIO_BUS_MISSING)
		prepared.append(assignment.deep_clone())

	# All calls below use preflighted indices and primitive values. Godot's
	# setters do not return errors, so this is the no-fail commit segment.
	for assignment: AudioBusAssignment in prepared:
		var bus_index := AudioServer.get_bus_index(assignment.bus)
		AudioServer.set_bus_volume_db(bus_index, assignment.volume_db)
		AudioServer.set_bus_mute(bus_index, assignment.muted)
	return AudioBusBatchResult.success()
