class_name ViewPublicationProbe
extends RefCounted

var count: int = 0
var last_view: RunViewState

func capture(view: RunViewState) -> void:
	count += 1
	last_view = view.deep_clone()
