class_name PreparedProductionRoute
extends RefCounted

var _issuer: RefCounted
var _route_kind: StringName
var _candidate: ProductionScreen
var _issue_nonce: int = -1
var _consumed: bool = false


func _init(
	issuer: RefCounted = null,
	route_kind: StringName = &"",
	candidate: ProductionScreen = null,
	issue_nonce: int = -1
) -> void:
	_issuer = issuer
	_route_kind = route_kind
	_candidate = candidate
	_issue_nonce = issue_nonce
