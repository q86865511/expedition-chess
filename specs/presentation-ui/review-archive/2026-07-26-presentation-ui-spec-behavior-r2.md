# presentation-ui 規格行為審查 R2

結論：**R2 不核可進 TDD**。R1 17 個原始 finding 合併後 14 項中，13 項已修；
opaque recovery digest 仍互相矛盾，另有 2 個新的高嚴重度行為缺口。

修復總表：

- 行為 R1：PUI-01 FIXED、02 FIXED、03 FIXED、04 FIXED、**05 NOT FIXED**、06 FIXED、07 FIXED、08 FIXED。
- 架構 R1：PUI-01 FIXED、**02 NOT FIXED（同一 opaque 項）**、03 FIXED、04 FIXED、05 FIXED、06 FIXED、07 FIXED、08 FIXED、09 FIXED。
- 合併 14 項：facade、pre/post commit、19 AC、四 bus、敵我提示、pointer、settings exact/future、prepared capability、atomic route、playback、typed clone、ownership、T00 均 FIXED；opaque recovery NOT FIXED。
- 覆蓋核對：R1～R14 皆有 task；T00～T15 Covers 非空；owning AC matrix 為 19/19、無重複且與 roadmap 集合一致。現階段僅是預定 fresh evidence，尚未誤標實作 PASS。

| 類型／嚴重度 | 檔案:行號 | 可重現失敗情境 | 建議 |
|---|---|---|---|
| R1 未修／高 | `design.md:117-120,348-350,460`；`tasks.md:57-59` | design 一處定義 opaque token 為「run bytes SHA-256」，其餘要求 full file／committed-bytes digest。照前者實作會漏掉 profile-only committed-file 變更；照後者驗證 run digest 則合法 token 永遠不匹配。 | 全文統一為完整 committed file bytes SHA-256；run identity 不可解析時只以此 digest 比對與命名 archive。 |
| 新／高 | `requirements.md:62,78`；`design.md:62-72,144-154`；`tasks.md:70-80` | 無 active run 時按 Start 只進 CAMP；SDD 沒有任何正式 Camp intent/API/task 驗收會 dispatch `StartExpeditionCommand`。T08/T09 可全綠但玩家仍無法建立 run、進地圖。 | 新增 typed Camp start intent/result，涵蓋 commander/challenge、具名拒絕、原子提交及 CAMP→RUN route；指定 T08/T05 owner 與紅燈。 |
| 新／高 | `requirements.md:132-133,153-161`；`design.md:359-360`；`tasks.md:24-35` | settings 先持久化並 swap，之後 audio/theme/locale 才套用；若 UI bus 缺失，磁碟與 SettingsSnapshot 已是新值，但 audio 保留舊值，形成持久化的部分套用。T02、T03 分開測仍可各自通過。 | 增加跨 consumer two-phase apply：所有 adapter 先 preflight，settings commit 後只做不可失敗 apply；補整合 fault test。 |
