class_name RunMutationProposalBuildResult
extends RefCounted

var ok: bool
var proposal: RunMutationProposal
var error: RunMutationProposalError


static func success(p_proposal: RunMutationProposal) -> RunMutationProposalBuildResult:
	return RunMutationProposalBuildResult.new(true, p_proposal, null)


static func failure(p_error: RunMutationProposalError) -> RunMutationProposalBuildResult:
	return RunMutationProposalBuildResult.new(false, null, p_error)


func _init(
	p_ok: bool,
	p_proposal: RunMutationProposal,
	p_error: RunMutationProposalError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_proposal != null, p_proposal == null)
	ok = p_ok
	proposal = p_proposal.deep_clone() if p_proposal != null else null
	error = p_error.deep_clone() if p_error != null else null
