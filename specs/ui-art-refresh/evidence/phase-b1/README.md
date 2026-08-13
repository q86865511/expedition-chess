# ui-art-refresh Phase B1 驗收證據

## 結論

Phase B1 樣板已完成並停在視覺核可閘門。營地與備戰共有 12 張 zh_TW 實機截圖，
涵蓋 1280×720／1920×1080 與 100%／125%／150%；另有備戰「開始戰鬥」的
`focus_high` 缺角焦點框、設定 activation probe 的 before／after 截圖、文字 log 與
machine-readable report。B2 尚未開始。

最終 `tools/run-tests.ps1 -Suite All` 為 exit 0：304 scripts、1211/1211 tests、
25010 assertions、0 failures、0 errors。摘要見 `all-tests-summary.json`。

## 隔離 Windows profile

所有成功的 Godot import、GUT、完整 All 與實機截圖都經以下 wrapper 執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run-isolated-ui-evidence.ps1 -Mode AllTests

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\run-isolated-ui-evidence.ps1 -Mode Evidence
```

wrapper 在啟動 Godot 前將環境變數固定為：

- `APPDATA=artifacts/ui-art-refresh/phase-b1/profile/AppData/Roaming`
- `LOCALAPPDATA=artifacts/ui-art-refresh/phase-b1/profile/AppData/Local`

清理 profile 前，腳本會將兩個路徑解析成絕對路徑並驗證它們都位於
`artifacts/ui-art-refresh/phase-b1/profile/` 下；不符合即拒絕執行。該目錄由
`.gitignore` 排除，不會寫入真實使用者設定。

開工初期曾直接呼叫一次 headless import，未帶隔離環境；當時 filesystem sandbox
拒絕對真實 APPDATA 的所有寫入，該次沒有產生或修改使用者設定。發現後，所有成功
驗證一律改走上述 wrapper。

## 工具鏈與字型

- Godot：`4.7.stable.official`
- GUT：`9.7.1`
- UI 字型：Google Fonts `ofl/notosanstc/NotoSansTC[wght].ttf`
- repo 檔名：`assets/fonts/noto-sans-tc/NotoSansTC-wght.ttf`
- SHA-256：`864727d210d54f2537bbe23b3a839436c3992af72de9322af5270897246bd44f`
- 授權：SIL Open Font License 1.1；同目錄保存 `OFL.txt`

## 截圖矩陣

營地：

- `camp-720p-ui100.png`、`camp-720p-ui125.png`、`camp-720p-ui150.png`
- `camp-1080p-ui100.png`、`camp-1080p-ui125.png`、`camp-1080p-ui150.png`

備戰：

- `prepare-720p-ui100.png`、`prepare-720p-ui125.png`、`prepare-720p-ui150.png`
- `prepare-1080p-ui100.png`、`prepare-1080p-ui125.png`、`prepare-1080p-ui150.png`

焦點：`focus-prepare-start.png`。

`evidence-report.json` 讀回 15/15 張圖的實際尺寸、SHA-256 與非全黑檢查，
`issues=[]`。人工檢視 720p 三種 scale、1080p 兩端 scale、焦點與 activation
前後圖：top／left／center／right／bottom 都留在安全區，150% 下沒有跨區重疊；
ItemList 超出列數時使用自身捲軸，未把內容畫到相鄰區域。焦點框會在 Container
重新排版後持續追蹤實際按鈕矩形，四角缺口清楚可見。

## B1-4：設定 activation probe 根因與證據

根因是舊 typography probe 對所有 locale 都只建立 CJK required set。英文可見文字
沒有 CJK codepoint，因此 `required_glyph_count=0`；即使 SystemFont 實測 bounds 為正，
仍固定回報 `ACCESSIBILITY_REQUIRED_GLYPH_MISSING`，最後被映射成「已生效但畫面未更新」。
只加入內嵌字型不能修正空集合判斷，因此 policy 同時改成 locale-aware visible-glyph
probe：zh_TW 驗必要 CJK 與實際文字，en 驗實際可見字元。

- `activation-before-fault-injection.png`：以同一 source code 注入真實
  `SettingsApplicationResult.committed_presentation_failure`，證明真正 post-commit
  activation failure 仍會顯示本地化回退訊息。
- `activation-after-real-apply.png`：真實 AppRoot／SettingsApplicationPort 在 Windows
  將 RUN_COMBAT 套用 en＋125%；結果 `ok=true`、`committed=true`、
  `presentation_ok=true`、`source_code=""`。
- `activation-before.log`／`activation-after.log`：人可讀摘要。
- `activation-before-after.json`：完整 machine-readable before／after report；修正後
  `font_source=res.font.noto_sans_tc`、`fallback_used=false`、`readable=true`、
  `missing_glyphs=[]`。

after 截圖中的 RUN_COMBAT 仍是 Phase B2 尚未鋪 Theme 的既有 production 畫面；該圖
只驗 activation 訊息是否消失，不作本階段視覺樣板核可依據。

## 測試紀錄

第一次完整 All（2026-08-07T10:52:27Z～11:10:39Z）揭露兩個 assertion：R12 舊測試
仍要求 bundled font 產生 per-control override；R15 為避免樣板溢出時誤把非樣板按鈕
寬度也固定。修正為 Theme 字型不加 override（SystemFont fallback 才加），以及只有
B1 responsive shell 讓 Container 管理寬度；R12 與 R15 各自重跑 exit 0。

最終完整 All（2026-08-07T11:13:55Z～11:30:48Z）exit 0。原始本機輸出位於
`artifacts/test/runner-execution.json`、`artifacts/test/gut.xml`、
`artifacts/test/gut.godot.log`；可提交摘要為 `all-tests-summary.json`。
