class_name NodeChoiceRejection
extends RefCounted

## specs/content-production/design.md §5（:179-184）的 normative rejection code 集合。
## CommitNodeChoiceCommand／CommitNodeChoiceService 的 payload 閘門只以本清單的具名碼
## 拒絕；design 另外保留給 LiveScreen 層的
## LEASE_STALE／ROUTE_GENERATION_STALE／LIFECYCLE_STALE／PAYLOAD_DIGEST_MISMATCH／
## CONFIRMATION_ALREADY_CLOSED 仍由 LiveScreenIntentPort 的 lease／draft 驗證負責，
## 不在本檔重複定義（同一情境兩套碼會讓錯誤來源無法辨識）。
##
## 這些碼經 CommandApplyError 的 "source_code" diagnostic 原樣傳到 presentation，
## 與 DISMANTLE_EQUIPMENT_* 等既有具名碼走同一條通道。

const RUN_MISMATCH: StringName = &"RUN_MISMATCH"
const NODE_MISMATCH: StringName = &"NODE_MISMATCH"
const CHOICE_SET_MISMATCH: StringName = &"CHOICE_SET_MISMATCH"
const CONTENT_VERSION_MISMATCH: StringName = &"CONTENT_VERSION_MISMATCH"
const CATALOG_SCHEMA_MISMATCH: StringName = &"CATALOG_SCHEMA_MISMATCH"
const CODEC_MISMATCH: StringName = &"CODEC_MISMATCH"
const MANIFEST_MISMATCH: StringName = &"MANIFEST_MISMATCH"
const PENDING_DIGEST_MISMATCH: StringName = &"PENDING_DIGEST_MISMATCH"
const NONCE_MISMATCH: StringName = &"NONCE_MISMATCH"
const CHOICE_UNKNOWN: StringName = &"CHOICE_UNKNOWN"
const ALREADY_COMMITTED: StringName = &"ALREADY_COMMITTED"

const ALL: Array[StringName] = [
	RUN_MISMATCH,
	NODE_MISMATCH,
	CHOICE_SET_MISMATCH,
	CONTENT_VERSION_MISMATCH,
	CATALOG_SCHEMA_MISMATCH,
	CODEC_MISMATCH,
	MANIFEST_MISMATCH,
	PENDING_DIGEST_MISMATCH,
	NONCE_MISMATCH,
	CHOICE_UNKNOWN,
	ALREADY_COMMITTED,
]
