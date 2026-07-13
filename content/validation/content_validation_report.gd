class_name ContentValidationReport
extends RefCounted

var valid: bool
var issues: Array[ContentValidationIssue] = []
var manifest_digest: OptionalStringValue
var version_maximum_population: int
var per_side_stress_minimum: int
var maximum_simultaneous_entities: int
var entity_stress_minimum: int

static func failure(code: StringName, path: StringName = &"", source: StringName = &"") -> ContentValidationReport:
	var report := ContentValidationReport.new()
	report.valid = false
	report.issues.append(ContentValidationIssue.new(code, source, path))
	return report

func deep_clone() -> ContentValidationReport:
	var result := ContentValidationReport.new()
	result.valid = valid
	for issue in issues: result.issues.append(issue.deep_clone())
	result.manifest_digest = manifest_digest.deep_clone() if manifest_digest != null else null
	result.version_maximum_population = version_maximum_population
	result.per_side_stress_minimum = per_side_stress_minimum
	result.maximum_simultaneous_entities = maximum_simultaneous_entities
	result.entity_stress_minimum = entity_stress_minimum
	return result
