extends RefCounted

## T14 的最小 deterministic candidate。
##
## production validator 必須只掃 production_roots；sources 故意同時放入 dev、tests、
## `.godot` 與 pipeline artifact，乾淨候選不得因這些非 production 檔案而失敗。


static func build() -> Dictionary:
	return {
		"production_roots": PackedStringArray([
			"res://app/",
			"res://presentation/",
			"res://scenes/production/",
			"res://services/settings/",
		]),
		"ignored_roots": PackedStringArray([
			"res://.godot/",
			"res://.pipeline/",
			"res://scripts/dev/",
			"res://scenes/dev/",
			"res://tests/",
		]),
		"sources": {
			"res://app/main.tscn": (
				"[gd_scene load_steps=2 format=3]\n"
				+ "[ext_resource path=\"res://presentation/screens/menu_main.gd\" "
				+ "type=\"Script\" id=\"1\"]\n"
				+ "[node name=\"Main\" type=\"Control\"]\n"
				+ "script = ExtResource(\"1\")\n"
			),
			"res://presentation/screens/menu_main.gd": (
				"extends Control\n"
				+ "const PANEL_TEXTURE := preload(\"res://assets/ui/panel.png\")\n"
				+ "func title_key() -> StringName:\n"
				+ "\treturn &\"menu.title\"\n"
				+ "func primary_action_key() -> StringName:\n"
				+ "\treturn &\"menu.start\"\n"
				+ "func party_limit_text(snapshot: Variant) -> String:\n"
				+ "\treturn str(snapshot.party_limit)\n"
			),
			"res://presentation/accessibility/menu_focus.json": (
				"{\"graph_id\":\"menu\",\"nodes\":[\"start\",\"settings\",\"exit\"],"
				+ "\"edges\":{\"start\":[\"settings\"],\"settings\":[\"exit\"],"
				+ "\"exit\":[\"start\"]},"
				+ "\"required_actions\":[\"start\",\"settings\",\"exit\"]}"
			),
			"res://scenes/production/menu_main.tscn": (
				"[gd_scene format=3]\n"
				+ "[node name=\"MenuMain\" type=\"Control\"]\n"
				+ "theme_type_variation = &\"PrimaryScreen\"\n"
			),
			"res://services/settings/adapters/theme_settings_adapter.gd": (
				"extends RefCounted\n"
				+ "const SUPPORTED_UI_SCALES := [1.0, 1.25, 1.5]\n"
			),
			"res://scripts/dev/ignored.gd": (
				"const LAB := preload(\"res://scenes/dev/ignored_lab.tscn\")\n"
				+ "var player_text := \"非正式工具文字\"\n"
			),
			"res://tests/ignored_test.gd": "var repo: SaveRepository\n",
			"res://.godot/imported/ignored.md5": "res://scripts/dev/ignored.gd\n",
			"res://.pipeline/tdd/ignored-red.txt": "res://scenes/dev/ignored_lab.tscn\n",
		},
		"asset_paths": PackedStringArray([
			"res://assets/ui/panel.png",
		]),
		"localization": {
			"zh_TW": {
				"menu.title": "主選單",
				"menu.start": "開始",
				"menu.settings": "設定",
				"menu.exit": "離開",
			},
			"en": {
				"menu.title": "Main Menu",
				"menu.start": "Start",
				"menu.settings": "Settings",
				"menu.exit": "Exit",
			},
		},
		"focus_graphs": [
			{
				"graph_id": "menu",
				"nodes": PackedStringArray(["start", "settings", "exit"]),
				"edges": {
					"start": PackedStringArray(["settings"]),
					"settings": PackedStringArray(["exit"]),
					"exit": PackedStringArray(["start"]),
				},
				"required_actions": PackedStringArray(["start", "settings", "exit"]),
			},
		],
		"render_policy": {
			"world_size": Vector2i(640, 360),
			"ui_reference_size": Vector2i(1280, 720),
			"integer_scale": true,
			"letterbox": true,
			"world_texture_filter": "nearest",
			"pixel_snap": true,
		},
		"theme_policy": {
			"ui_scale_tokens": PackedFloat32Array([1.0, 1.25, 1.5]),
			"color_modes": PackedStringArray([
				"standard",
				"protanopia",
				"deuteranopia",
				"tritanopia",
			]),
			"non_color_cues": true,
			"focus_token": "focus.visible",
			"tooltip_max_depth": 2,
			"cjk_font_token": "font.cjk.body",
		},
		"ui_tune": {
			"forbidden_literal": "12",
			"forbidden_declaration_markers": PackedStringArray([
				"MAX_PARTY",
				"PARTY_LIMIT",
				"MAX_DEPLOY",
			]),
			"authoritative_member": "snapshot.party_limit",
		},
	}
