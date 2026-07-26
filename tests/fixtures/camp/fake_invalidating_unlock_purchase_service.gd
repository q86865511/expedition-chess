class_name FakeInvalidatingUnlockPurchaseService
extends UnlockPurchaseService

## T04 (specs/meta-progression/design.md SS4.1 "clone→validate→...": the
## explicit "validate" step between apply_to() and SaveRepository.save() must
## be a real, independently-observable gate, not merely relying on
## SaveRepository.save()'s own internal validate_root() call). This test
## double always reports success but returns a profile with an out-of-range
## meta_currency (fails RunStateValidator._is_u32), so
## CampController.dispatch() can only be proven to reject it distinctly as
## CampCommandError.VALIDATION_FAILED -- not CampCommandError.SAVE_FAILED --
## if CampController actually calls RunStateValidator.validate_profile() on
## the command's output before ever reaching SaveRepository.save().
##
## Deliberately extends the real UnlockPurchaseService (a plain RefCounted
## with no abstract/virtual contract to honor) purely so PurchaseUnlockCommand
## -- typed to accept `service: UnlockPurchaseService = null` -- can be handed
## this double via its constructor's injection seam, exactly like
## BuyOfferCommand accepts an injected ShopService in
## tests/integration/run_controller/*.

func purchase(profile: ProfileState, _unlock_def: UnlockDef) -> UnlockPurchaseResult:
	var draft := profile.deep_clone()
	draft.meta_currency = -1
	return UnlockPurchaseResult.success(draft)
