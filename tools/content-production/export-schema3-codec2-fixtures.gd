extends SceneTree

const OUTPUT_ROOT := "res://tests/fixtures/save/content_production"
const SOURCES: Array[Dictionary] = [
	{
		"short": "5ddf80a",
		"commit": "5ddf80a30481ee701ba90be48e0fd474bc8c2715",
		"content_version": "0.1.0-build-lab",
		"saved_at_utc": "2026-07-26T08:56:56Z",
		"label": "S5 historical baseline",
	},
	{
		"short": "9362e7d",
		"commit": "9362e7d2a06047994f85b8adf25f1c4a2f973b5f",
		"content_version": "0.1.0-presentation-ui",
		"saved_at_utc": "2026-07-30T11:37:50Z",
		"label": "PR #5 presentation merge",
	},
	{
		"short": "5e78ccf",
		"commit": "5e78ccf1766daf57fcd322fc861ddeb3fd73a932",
		"content_version": "0.1.0-presentation-ui",
		"saved_at_utc": "2026-07-30T16:38:06Z",
		"label": "PR #6 review-corrected baseline",
	},
]


func _init() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_ROOT)
	)
	if directory_error != OK:
		push_error("could not create fixture directory")
		quit(3)
		return
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(SaveRootFixture.create_valid_root())
	if not encoded.ok:
		push_error("could not encode source fixture root")
		quit(2)
		return
	var base: Variant = JSON.parse_string(encoded.json_text.value)
	if not base is Dictionary:
		push_error("encoded source fixture is not an object")
		quit(2)
		return
	var inventory: Array[Dictionary] = []
	for source: Dictionary in SOURCES:
		var data: Dictionary = (base as Dictionary).duplicate(true)
		data["schema_version"] = 3
		data["content_version"] = source["content_version"]
		data["saved_at_utc"] = source["saved_at_utc"]
		var run: Dictionary = data["run"]
		run.erase("node_choice_receipts")
		var snapshot: Dictionary = run["content_snapshot"]
		snapshot["content_version"] = source["content_version"]
		snapshot["manifest_digest"] = (
			"historical-codec2|" + String(source["commit"])
		).sha256_text()
		snapshot.erase("catalog_schema_version")
		snapshot.erase("content_codec_version")
		var json_text := JSON.stringify(data) + "\n"
		var file_name := "%s.schema3.codec2.json" % source["short"]
		var fixture_path := "%s/%s" % [OUTPUT_ROOT, file_name]
		if not _write(fixture_path, json_text):
			quit(3)
			return
		var fixture_hash := FileAccess.get_sha256(fixture_path)
		if not _write(
			"%s/%s.sha256" % [OUTPUT_ROOT, source["short"]],
			"%s  %s\n" % [fixture_hash, file_name]
		):
			quit(3)
			return
		inventory.append(
			{
				"source_commit": source["commit"],
				"source_label": source["label"],
				"source_schema_version": 3,
				"source_catalog_schema_version": 1,
				"source_content_codec_version": 2,
				"content_version": source["content_version"],
				"source_manifest_digest": snapshot["manifest_digest"],
				"fixture": "tests/fixtures/save/content_production/%s" % file_name,
				"fixture_sha256": fixture_hash,
			}
		)
	if not _write(
		"%s/inventory.json" % OUTPUT_ROOT,
		JSON.stringify(
			{
				"schema_version": 1,
				"status": "frozen",
				"generator": "tools/content-production/export-schema3-codec2-fixtures.gd",
				"fixtures": inventory,
			},
			"\t"
		) + "\n"
	):
		quit(3)
		return
	print("exported %d frozen schema-3/codec-2 fixtures" % inventory.size())
	quit(0)


func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("could not open fixture output: %s" % path)
		return false
	file.store_buffer(text.to_utf8_buffer())
	file.close()
	return true
