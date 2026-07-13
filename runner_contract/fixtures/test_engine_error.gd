extends GutTest


func test_runner_contract_tracks_engine_errors() -> void:
	var node := Node.new()
	add_child_autofree(node)
	node.get_node(NodePath("missing"))
