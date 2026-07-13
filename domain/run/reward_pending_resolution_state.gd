class_name RewardPendingResolutionState
extends ResolutionState

var pending_reward: PendingRewardState

func _init(p_pending_reward: PendingRewardState) -> void:
	super(Kind.REWARD_PENDING)
	pending_reward = p_pending_reward.deep_clone()

func deep_clone() -> ResolutionState:
	return RewardPendingResolutionState.new(pending_reward)
