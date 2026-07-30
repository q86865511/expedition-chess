extends GutTest

const Candidate := preload(
	"res://tests/unit/presentation_ui_static_gate/fixtures/minimal_static_gate_candidate.gd"
)
const Support := preload(
	"res://tests/unit/presentation_ui_static_gate/static_gate_test_support.gd"
)


func test_production_dev_reference_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	Support.append_source(
		candidate,
		"res://app/main.tscn",
		"[ext_resource path=\"res://scripts/dev/fake_dependency.gd\" type=\"Script\" id=\"9\"]\n"
	)

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_DEV_REFERENCE")


func test_hardcoded_player_text_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	Support.append_source(
		candidate,
		"res://presentation/screens/menu_main.gd",
		"func forbidden_label() -> String:\n\treturn \"開始遊戲\"\n"
	)

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_HARDCODED_PLAYER_TEXT")


func test_zh_tw_and_en_key_set_mismatch_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	var localization: Dictionary = candidate["localization"]
	var english: Dictionary = localization["en"]
	english.erase("menu.exit")

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_LOCALIZATION_KEY_PARITY")


func test_missing_referenced_asset_is_named_and_fails_gate() -> void:
	var candidate := Candidate.build()
	candidate["asset_paths"] = PackedStringArray()

	var report := Support.validate(self, candidate)

	Support.assert_rejected_with(self, report, &"PUI_ASSET_REFERENCE_MISSING")
