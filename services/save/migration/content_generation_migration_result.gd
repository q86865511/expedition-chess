class_name ContentGenerationMigrationResult
extends RefCounted

var ok: bool
var target_receipt: PinnedCatalogBuildReceipt
var migration_receipt: RefCounted
## 成功時由 codec 2→3 port 附上的套用計畫;呼叫端據此改寫 raw run 的引用面。
## V1(codec 1→2)路徑由 transcoder 重建 catalog,不產生 plan,維持 null。
var plan: ContentGenerationMigrationPlan
var error: ContentGenerationMigrationError

static func success(
	p_target_receipt: PinnedCatalogBuildReceipt,
	p_migration_receipt: RefCounted,
	p_plan: ContentGenerationMigrationPlan
) -> ContentGenerationMigrationResult:
	return ContentGenerationMigrationResult.new(
		true, p_target_receipt, p_migration_receipt, null, p_plan
	)

static func failure(p_error: ContentGenerationMigrationError) -> ContentGenerationMigrationResult:
	return ContentGenerationMigrationResult.new(false, null, null, p_error, null)

func _init(
	p_ok: bool,
	p_target_receipt: PinnedCatalogBuildReceipt,
	p_migration_receipt: RefCounted,
	p_error: ContentGenerationMigrationError,
	p_plan: ContentGenerationMigrationPlan
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_target_receipt != null and p_migration_receipt != null,
		p_target_receipt == null and p_migration_receipt == null and p_plan == null
	)
	ok = p_ok
	target_receipt = p_target_receipt.deep_clone() if p_target_receipt != null else null
	migration_receipt = p_migration_receipt.deep_clone() if p_migration_receipt != null else null
	plan = p_plan.deep_clone() if p_plan != null else null
	error = p_error.deep_clone() if p_error != null else null
