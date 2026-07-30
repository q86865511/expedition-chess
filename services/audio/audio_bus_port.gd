class_name AudioBusPort
extends RefCounted

const AUDIO_BUS_MISSING: StringName = &"AUDIO_BUS_MISSING"
const AUDIO_BUS_APPLY_PRECOMMIT_FAULT: StringName = \
	&"AUDIO_BUS_APPLY_PRECOMMIT_FAULT"
const AUDIO_BUS_BATCH_INVALID: StringName = &"AUDIO_BUS_BATCH_INVALID"
const AUDIO_BUS_VALUE_INVALID: StringName = &"AUDIO_BUS_VALUE_INVALID"


func apply_batch(_batch: AudioBusBatch) -> AudioBusBatchResult:
	return AudioBusBatchResult.failure(AUDIO_BUS_APPLY_PRECOMMIT_FAULT)
