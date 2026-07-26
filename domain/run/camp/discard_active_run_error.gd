class_name DiscardActiveRunError
extends RefCounted

## S5-AC-008 玩家明示棄置的 domain rejection。結構性 validation/save 失敗仍沿用
## CampCommandError，讓所有 camp 交易維持同一機械故障契約。

const INPUT_INVALID: StringName = &"DISCARD_ACTIVE_RUN_INPUT_INVALID"
const LOAD_FAILED: StringName = &"DISCARD_ACTIVE_RUN_LOAD_FAILED"
const NOT_FOUND: StringName = &"DISCARD_ACTIVE_RUN_NOT_FOUND"
const RUN_CHANGED: StringName = &"DISCARD_ACTIVE_RUN_CHANGED"
