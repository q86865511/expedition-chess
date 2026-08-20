# catalog.v2 `.translation` 產物政策

裁決：保留為 **Godot CSV importer 的本機建置產物**，不把 `.translation` 納入版本庫或 runtime localization authority。

- `localization/catalog.v2.csv.import` 宣告 `catalog.v2.zh_TW.translation` 與 `catalog.v2.en.translation` 為 `csv_translation` 的 `dest_files`；Godot import 可重建兩檔。
- `.gitignore:13` 的 `*.translation` 已涵蓋兩檔；`git ls-files --error-unmatch` 對兩檔皆無追蹤結果。
- production bootstrap 只讀 `res://localization/catalog.v2.csv.raw`，並以 `LOCALIZATION_CATALOG_SHA256` fail-closed 驗證。
- production `app/`、`presentation/`、`services/`、`tools/` 沒有引用兩個具名 `.translation` 路徑。
- 因兩檔是可再生快取，repository 不保存其 bytes 或 SHA；權威鏈是 `localization_catalog.gd` → exporter 產生 byte-identical CSV/raw → bootstrap raw SHA。

這個選擇避免把平台／Godot importer 版本相關的衍生檔當成文案來源，也不需要刪除每次 editor import 都會重建的本機檔案。
