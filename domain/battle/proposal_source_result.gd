class_name ProposalSourceResult
extends RefCounted

var ok: bool
var token: OptionalStringValue
var error: ProposalSourceError


static func success(p_token: String) -> ProposalSourceResult:
	return ProposalSourceResult.new(true, OptionalStringValue.new(p_token), null)


static func failure(p_error: ProposalSourceError) -> ProposalSourceResult:
	return ProposalSourceResult.new(false, null, p_error)


func _init(
	p_ok: bool,
	p_token: OptionalStringValue,
	p_error: ProposalSourceError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_token != null, p_token == null)
	ok = p_ok
	token = p_token.deep_clone() if p_token != null else null
	error = p_error.deep_clone() if p_error != null else null
