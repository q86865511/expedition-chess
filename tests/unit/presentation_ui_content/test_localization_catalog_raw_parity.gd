extends GutTest

## G2 balance-playtest 收尾 review B-03 修正防回歸。
##
## app/content/project_content_bootstrap.gd 的 runtime checksum 讀取的是
## `localization/catalog.v2.csv.raw`(byte-identical 副本,PCK 內 csv_translation
## importer 不保留原始 CSV bytes),但畫面顯示用的 Translation resource 仍由
## `localization/catalog.v2.csv` 產生。兩檔若漂移:
## (a) 若同步更新 LOCALIZATION_CATALOG_SHA256,boot 會 DIGEST_MISMATCH 失敗;
## (b) 若未更新該常數,遊戲畫面靜默沿用舊文案(bootstrap 讀 .raw,不讀 .csv)。
## 這個測試斷言兩檔 SHA-256 相等,守住
## tools/content-production/export-localization-catalog.gd 必須同步寫出兩檔的
## 導出契約。

const CSV_PATH := "res://localization/catalog.v2.csv"
const RAW_PATH := "res://localization/catalog.v2.csv.raw"


func test_csv_and_raw_localization_catalog_are_byte_identical() -> void:
	assert_true(
		FileAccess.file_exists(CSV_PATH),
		"tracked localization/catalog.v2.csv must exist"
	)
	assert_true(
		FileAccess.file_exists(RAW_PATH),
		"tracked localization/catalog.v2.csv.raw must exist"
	)
	if not FileAccess.file_exists(CSV_PATH) or not FileAccess.file_exists(RAW_PATH):
		return

	var csv_hash := FileAccess.get_sha256(CSV_PATH)
	var raw_hash := FileAccess.get_sha256(RAW_PATH)
	assert_eq(
		raw_hash,
		csv_hash,
		(
			"catalog.v2.csv.raw must be a byte-identical copy of catalog.v2.csv "
			+ "(export-localization-catalog.gd must write both files together); "
			+ "csv=%s raw=%s" % [csv_hash, raw_hash]
		)
	)


func test_raw_localization_catalog_matches_pinned_bootstrap_digest() -> void:
	# app/content/project_content_bootstrap.gd 的 LOCALIZATION_CATALOG_SHA256 是
	# runtime boot 期實際驗證的值。這裡不硬編該常數(避免測試與production常數各自
	# 漂移互相掩護),改為動態讀取 bootstrap 原始碼裡的常數宣告,確認它與目前 .raw
	# 檔實際內容一致——三方(csv, raw, 常數)缺一不同就會在這裡或上一個測試曝光。
	const BOOTSTRAP_PATH := "res://app/content/project_content_bootstrap.gd"
	assert_true(FileAccess.file_exists(BOOTSTRAP_PATH))
	if not FileAccess.file_exists(BOOTSTRAP_PATH):
		return
	var source := FileAccess.get_file_as_string(BOOTSTRAP_PATH)
	var marker := "LOCALIZATION_CATALOG_SHA256: String = \\\n\t\""
	var start := source.find(marker)
	assert_true(start >= 0, "could not locate LOCALIZATION_CATALOG_SHA256 declaration")
	if start < 0:
		return
	start += marker.length()
	var end := source.find("\"", start)
	assert_true(end > start, "could not parse LOCALIZATION_CATALOG_SHA256 value")
	if end <= start:
		return
	var pinned_hash := source.substr(start, end - start)
	var raw_hash := FileAccess.get_sha256(RAW_PATH)
	assert_eq(
		raw_hash,
		pinned_hash,
		"catalog.v2.csv.raw content must match the pinned bootstrap SHA-256"
	)
