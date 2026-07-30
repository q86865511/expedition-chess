extends RefCounted


class BootHarness:
	extends RefCounted

	var registry: ContentRegistryService
	var repository: SaveRepository
	var router: SceneRouterService
	var root: ApplicationRoot
	var host: Control
	var boot_error: StringName = &""


static func boot(
	test: GutTest,
	storage: FakeSaveStorage,
	root_override: ApplicationRoot = null
) -> BootHarness:
	var harness := BootHarness.new()
	harness.registry = ContentRegistryService.new()
	test.add_child_autofree(harness.registry)
	harness.repository = SaveRepository.new(storage)
	test.add_child_autofree(harness.repository)
	harness.router = SceneRouterService.new()
	test.add_child_autofree(harness.router)
	harness.root = (
		root_override if root_override != null else ApplicationRoot.new()
	)
	harness.root.name = "AppRoot"
	harness.host = Control.new()
	harness.host.name = "PresentationHost"
	harness.root.add_child(harness.host)
	harness.root.boot_failed.connect(func(error_code: StringName) -> void:
		harness.boot_error = error_code
	)
	var bind_error := harness.root.bind_services(
		harness.registry,
		harness.repository,
		harness.router
	)
	test.assert_eq(bind_error, &"", "test graph must bind before tree entry")
	test.add_child_autofree(harness.root)
	return harness


static func source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


static func method_argument_count(target: Object, method_name: StringName) -> int:
	if target == null:
		return -1
	for method: Dictionary in target.get_method_list():
		if StringName(method.get("name", "")) == method_name:
			var arguments: Array = method.get("args", [])
			var default_arguments: Array = method.get("default_args", [])
			return arguments.size() - default_arguments.size()
	return -1


static func app_action_error_code(result: Variant) -> StringName:
	if result is AppActionResult and result.error != null:
		return result.error.source_code
	return &""


static func main_bytes(storage: FakeSaveStorage) -> PackedByteArray:
	var value := storage.file_bytes(StorageFaultKey.MAIN)
	return value.value.duplicate() if value != null else PackedByteArray()


static func host_identity(host: Control) -> Array[int]:
	var identities: Array[int] = []
	if host == null:
		return identities
	for child: Node in host.get_children():
		identities.append(child.get_instance_id())
	return identities
