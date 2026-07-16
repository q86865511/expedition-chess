class_name BoardValidationReport
extends RefCounted

var valid: bool
var derived_capacity: int
var issues: Array[BoardValidationIssue] = []

func _init(p_derived_capacity: int, p_issues: Array[BoardValidationIssue]) -> void:
	derived_capacity = p_derived_capacity
	for issue: BoardValidationIssue in p_issues:
		issues.append(issue.deep_clone())
	valid = issues.is_empty()

func deep_clone() -> BoardValidationReport:
	return BoardValidationReport.new(derived_capacity, issues)
