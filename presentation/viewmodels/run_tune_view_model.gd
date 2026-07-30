class_name RunTuneViewModel
extends RefCounted

var _population_limit_value: int


static func from_content(
	content: ProjectContentBootstrapResult
) -> RunTuneViewModel:
	return RunTuneViewModel.new(
		content.maximum_population() if content != null else 0
	)


func _init(p_population_limit: int = 0) -> void:
	_population_limit_value = maxi(0, p_population_limit)


func population_limit() -> int:
	return _population_limit_value


func population_limit_text() -> String:
	return str(_population_limit_value)
