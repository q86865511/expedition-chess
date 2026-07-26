class_name ShopSurchargeOperationDef
extends RunOperationDef

## design §6.3 軌 B（挑戰詞綴的經濟壓力）：amount 為商店單件購買成本的**增量**（幅度，恆 ≥0；
## 負向語意由型別本身表達，不放寬 content_validator 的 amount≥0 不變量）。消費端為
## ShopService._economy_discount（cost + surcharge − discount，下限 clamp 沿用既有規則）。
@export var amount: int
@export var claim_scope: StringName

func operation_type() -> int:
	return 0x3109
