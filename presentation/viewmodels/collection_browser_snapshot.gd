class_name CollectionBrowserSnapshot
extends RefCounted

var content_ids: Array = []
var recipe_ids: Array = []
var glossary_ids: Array = []


func deep_clone() -> CollectionBrowserSnapshot:
	var clone := CollectionBrowserSnapshot.new()
	clone.content_ids.assign(content_ids)
	clone.recipe_ids.assign(recipe_ids)
	clone.glossary_ids.assign(glossary_ids)
	return clone
