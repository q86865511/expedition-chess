extends GutTest


func test_every_declared_required_action_has_a_non_placeholder_handler() -> void:
	var screen_source := FileAccess.get_file_as_string(
		"res://presentation/screens/production_screen.gd"
	)
	var root_source := FileAccess.get_file_as_string("res://app/app_root.gd")
	var required: Array[StringName] = [
		&"menu.continue",
		&"menu.start",
		&"menu.settings",
		&"menu.exit",
		&"settings.apply",
		&"settings.back",
		&"camp.collection",
		&"camp.forge",
		&"camp.settings",
		&"camp.start",
		&"camp.menu",
		&"camp.back",
		&"map.select",
		&"map.confirm",
		&"prepare.unit",
		&"prepare.start",
		&"combat.pause",
		&"combat.inspect",
		&"combat.speed",
		&"reward.select",
		&"reward.confirm",
		&"run.menu",
		&"results.retry",
		&"results.camp",
		&"results.menu",
	]
	for action_id: StringName in required:
		assert_ne(
			screen_source.find("&\"%s\"" % String(action_id)),
			-1,
			"required Button declaration missing: %s" % String(action_id)
		)
		var app_handler := root_source.find(
			"actions[&\"%s\"]" % String(action_id)
		) >= 0
		var screen_handler := screen_source.find(
			"&\"%s\":" % String(action_id)
		) >= 0
		assert_true(
			app_handler or screen_handler,
			"required control has no production handler: %s" % String(action_id)
		)
	for forbidden_placeholder: String in [
		"_camp_settings_unavailable",
		"_camp_start_requires_selection",
	]:
		assert_eq(
			root_source.find(forbidden_placeholder),
			-1,
			"required controls cannot remain fixed unavailable placeholders"
		)
