class_name DrainExpeditionHpOperationDef
extends RunOperationDef

## design §6.3 軌 B（挑戰詞綴的遠征傷害）：amount 為戰敗結算時**額外**的遠征 HP 損失（幅度，
## 恆 ≥0；負向語意由型別本身表達）。消費端為 BattleSettlementService 的戰敗路徑（與既有
## heal_expedition_hp 同一決定性加總慣例、受既有 HP 下限 clamp；勝利路徑不生效）。
@export var amount: int
@export var claim_scope: StringName

func operation_type() -> int:
	return 0x310a
