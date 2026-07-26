class_name ChallengeAffixEntryState
extends RefCounted

## design §6.3（S5-AC-010）：一條「生效中的挑戰詞綴」在其中一條軌上的投影。
## 同一個效果若同時帶 battle_operations 與 run_operations，會各自產生一筆 entry（兩軌非互斥），
## 因為兩軌的消費端完全不同（軌 A→EncounterCompiler；軌 B→RunRelicTable 的 always-active 加總）。
## challenge_level＝該效果所屬的解鎖階級（1..N，供開局前清單依階級呈現）。

const BATTLE_AFFIX_TRACK: StringName = &"battle_affix"
const RUN_MODIFIER_TRACK: StringName = &"run_modifier"

var effect_id: StringName
var challenge_level: int
var track: StringName

func _init(p_effect_id: StringName, p_challenge_level: int, p_track: StringName) -> void:
	effect_id = p_effect_id
	challenge_level = p_challenge_level
	track = p_track

func deep_clone() -> ChallengeAffixEntryState:
	return ChallengeAffixEntryState.new(effect_id, challenge_level, track)
