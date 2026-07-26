class_name PurchaseUnlockCommand
extends RefCounted

## T04 (design.md §3 module diagram "PurchaseUnlockCommand → UnlockPurchaseService";
## §4.3): thin adapter binding one resolved UnlockDef to UnlockPurchaseService,
## exposing the RunCommand-family-shaped is_concrete()/apply_to() pair. The
## caller (ViewModel/AppRoot) resolves exactly which UnlockDef the player chose
## before constructing this command, so a single UnlockDef is passed directly
## (not a catalog+id pair). The optional `service` seam lets tests inject a
## double (see tests/fixtures/camp/fake_invalidating_unlock_purchase_service.gd).

var _unlock_def: UnlockDef
var _service: UnlockPurchaseService

func _init(p_unlock_def: UnlockDef, p_service: UnlockPurchaseService = null) -> void:
	_unlock_def = p_unlock_def
	_service = p_service if p_service != null else UnlockPurchaseService.new()

func is_concrete() -> bool:
	return _unlock_def != null

func apply_to(profile: ProfileState) -> UnlockPurchaseResult:
	if not is_concrete():
		return UnlockPurchaseResult.failure(
			UnlockPurchaseError.new(UnlockPurchaseError.INPUT_INVALID, &"unlock_def")
		)
	return _service.purchase(profile, _unlock_def)
