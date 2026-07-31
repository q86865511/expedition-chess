class_name NodeChoiceOverlaySnapshot
extends RefCounted

var choice_set_id: StringName
var display_name_key: StringName
var pending_digest: String
var options: Array[NodeChoiceOptionSnapshot] = []


static func from_rule(
	rule: NodeChoiceSetRule,
	pending: NodeChoicePendingState
) -> NodeChoiceOverlaySnapshot:
	if (
		rule == null
		or pending == null
		or rule.choice_set_id != pending.choice_set_id
	):
		return null
	var result := NodeChoiceOverlaySnapshot.new()
	result.choice_set_id = rule.choice_set_id
	result.display_name_key = rule.display_name_key
	result.pending_digest = pending.pending_digest
	for choice: NodeChoiceRule in rule.choices:
		if not pending.choice_ids.has(choice.choice_id):
			return null
		result.options.append(
			NodeChoiceOptionSnapshot.new(
				choice.choice_id,
				choice.title_key,
				choice.description_key,
				choice.preview_key,
				choice.confirmation_required
			)
		)
	return result if result.options.size() >= 2 else null


func try_option(choice_id: StringName) -> NodeChoiceOptionSnapshot:
	for option: NodeChoiceOptionSnapshot in options:
		if option.choice_id == choice_id:
			return option.deep_clone()
	return null


func deep_clone() -> NodeChoiceOverlaySnapshot:
	var clone := NodeChoiceOverlaySnapshot.new()
	clone.choice_set_id = choice_set_id
	clone.display_name_key = display_name_key
	clone.pending_digest = pending_digest
	for option: NodeChoiceOptionSnapshot in options:
		clone.options.append(option.deep_clone())
	return clone
