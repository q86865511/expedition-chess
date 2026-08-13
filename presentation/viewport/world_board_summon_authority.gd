class_name WorldBoardSummonAuthority
extends RefCounted

## Pinned authority that turns one committed `spawn` event into a renderer DTO.
##
## A spawn payload carries identity, side, origin and the destination cell only.
## The sprite comes from the adopted production visual manifest and every max
## stat comes from the pinned `SummonedUnitRuleSnapshot` closure of the same
## battle setup. No stat is derived here: a unit id without a pinned template, or
## without an authored sprite, has no complete authority and fails closed as
## null, so the caller keeps tracking that entity as unrenderable instead of
## fabricating a sprite or a health/mana maximum.

var _templates: Dictionary = {}
var _visuals := ProductionUnitVisualCatalog.new()


func _init(p_templates: Array[SummonedUnitRuleSnapshot] = []) -> void:
	for template: SummonedUnitRuleSnapshot in p_templates:
		if template == null or template.unit_id.is_empty():
			continue
		# Clone in: a caller that keeps mutating the array it passed must not be
		# able to rewrite the authority this table already accepted.
		_templates[template.unit_id] = template.deep_clone()


## The renderer DTO for one spawned entity, or null when this authority holds no
## complete visual/max-stat data for `unit_id`.
func try_spawned_unit(
	unit_id: StringName,
	presentation_instance_id: StringName,
	logical_cell: Vector2i
) -> WorldBoardUnitSnapshot:
	var template := _templates.get(unit_id) as SummonedUnitRuleSnapshot
	if template == null:
		return null
	# Domain validation already owns these invariants. Re-checking them keeps a
	# malformed template out of the renderer instead of clamping it into a
	# plausible-looking unit.
	if (
		template.health < 1
		or template.start_mana < 0
		or template.max_mana < template.start_mana
	):
		return null
	var frames := _visuals.try_sprite_frames(unit_id)
	var animation := _visuals.idle_animation(frames, template.star)
	if frames == null or animation.is_empty():
		return null
	var unit := WorldBoardUnitSnapshot.new()
	unit.presentation_instance_id = presentation_instance_id
	unit.logical_cell = logical_cell
	unit.sprite_frames = frames
	unit.animation = animation
	# A summoned entity enters at its template health and start mana; every later
	# value arrives as an explicit `*_after` transcript field.
	unit.health = template.health
	unit.max_health = template.health
	unit.mana = template.start_mana
	# Only the bar denominator is floored, exactly as the setup-side factory does
	# for units that never cast. The mana value itself stays authoritative.
	unit.max_mana = maxi(1, template.max_mana)
	if not unit.is_valid():
		return null
	return unit
