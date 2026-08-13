# G2 內容完整切片 — 交付 Roadmap（四切片＋3.5 `difficulty-curve` 機制切片）

> 建立日期：2026-07-26｜狀態：執行中（content-production 已合併；balance-playtest 執行中）
> 架構基線：`docs/game-architecture/`、`docs/implementation-slices.md`
> 基準提交：`5ddf80a30481ee701ba90be48e0fd474bc8c2715`（S5 merged）
> 規格裁決：2026-07-26 使用者採用 presentation-ui R1 雙審全部 14 項修正建議
> 規格裁決：2026-07-26 使用者採用 presentation-ui R2 雙審全部 7 項修正建議
> 規格裁決：2026-07-26 使用者採用 presentation-ui R3 雙審全部 7 項修正建議
> 規格裁決：2026-07-26 使用者採用 presentation-ui R4 雙審全部 4 項修正建議
> 規格裁決：2026-07-26 使用者採用 presentation-ui R5 雙審全部 3 項修正建議
> 規格裁決：2026-07-26 使用者採用 presentation-ui R6 雙審全部 2 項修正建議
> 規格裁決：2026-07-26 使用者採用 presentation-ui R7 雙審唯一 1 項修正建議
> 規格 checkpoint：2026-07-26 使用者指示記錄 R8 `G2-R8-01` 後提交；不構成修正裁決或 SDD 核可
> 規格修訂：2026-07-28 `G2-R8-01` 已回寫 SDD 並完成一致性稽查；待 fresh R9 雙獨立複審
> 規格裁決：2026-07-28 使用者採用 R9 三項 named-test coverage 修正；待 fresh R10 雙獨立複審
> 規格裁決：2026-07-28 使用者採用 R10 兩項 AppRoot ownership／wave 修正；待 fresh R11 雙獨立複審
> 規格審查：2026-07-28 fresh R11 新增 3 項 Medium findings；待使用者裁決，TDD 硬停
> 規格裁決：2026-07-28 使用者採用 R11 三項 wave/test-evidence 修正；待 fresh R12 雙獨立複審
> 規格審查：2026-07-28 fresh R12 確認 R11 修正封閉，新增 4 項 Medium findings；待使用者裁決
> 工作交接：2026-07-28 使用者指定 R12 四項 findings 保留待修並交由 Claude；修訂後 fresh R13 雙審結果先落交接文件
> Gate override：2026-07-28 使用者指示審查先跳過並繼續本地 implementation；R12 unresolved、R13/Git gate 延後未取消
> Implementation closure：2026-07-30 R16 findings 全採納、fresh gates 全綠；使用者明示
> 不啟動 R17／不再次雙審，直接進 T15 文件與 Git handoff。Git 仍需另行確認。
> Merge closure：PR #5 `MERGED @ 9362e7d`；merge 後 UI findings 修正由
> PR #6 `MERGED @ 5e78ccf`。第二片由該最新 master 建立。
> Merge closure：PR #8 已合併至 `master@bf818fb`；第三片由該提交建立
> `codex/g2-balance-playtest`。舊稱「content-production 本地未提交」已失效。
> 規格裁決：2026-08-04 使用者裁決大樣本統計（10k/30k，規模屆時裁決）自
> balance-playtest 移至 Phase 2 平衡收斂後執行；本片以 3k screening #2 gate PASS
> （candidate `balance.g2.7d47fada8091`）作 screening 證據收尾。
> 規格裁決：2026-08-04 使用者採用 Phase 0~3 執行計畫（見 §9）；新增機制切片
> `difficulty-curve` 於第 3、4 片之間。

## 1. 目的與完成定義

G2 將已完成的 G1 灰盒系統，依序交付為正式 presentation、完整內容、可測平衡候選與
Windows release candidate。四個切片各自有 SDD、TDD、雙審、使用者裁決與獨立 PR；
後一片只能由前一片已合併的最新 `master` 建立。

G2 **只有**在第四片同時具備下列外部證據時才可標記完成：

- 指定最低規格 Windows 實機通過正常與壓力效能 Gate。
- 至少 30 名熟悉規則玩家、每人至少 3 局，合計至少 90 局有效匿名報告。
- 完成局中位數 45～60 分鐘，至少三種決策不同的構築有通關紀錄。
- 全部全域 AC、四片 artifact、migration matrix、原創性審查、雙審與 release gate 完整。

在上述證據齊備前，最多只能標示 `RC`，不得標示 `G2 complete`。

## 2. 切片、分支與依賴

| 順序 | 切片 | 分支 | 主要交付 | 前置 |
|---:|---|---|---|---|
| 1 | `presentation-ui` | `codex/g2-presentation-ui` | production facade、主選單、正式場景、設定、localization、視覺樣板 | `master@5ddf80a` |
| 2 | `content-production` | `codex/g2-content-production` | 原創內容、美術音訊、事件選擇、codec 3、save schema 4 | 第 1 片已合併 |
| 3 | `balance-playtest` | `codex/g2-balance-playtest` | 版本化 TUNE、3k screening harness＋candidate、匿名報告、Windows 可測 RC（大樣本統計移至 Phase 2） | 第 2 片已合併 |
| 3.5 | `difficulty-curve` | `codex/g2-difficulty-curve` | 幕間難度縮放、三幕 Boss 差異化、多敵遭遇、trait 門檻階梯、tier-1 池重整、challenge run-op 分流 | 第 3 片已合併 |
| 4 | `performance-release` | `codex/g2-performance-release` | CI/export、效能、G1→G2 bridge、90 場真人 Gate、最終 review | 第 3.5 片與 Phase 2 大樣本已完成 |

共同 Git 規則：代理不得 commit、push 或 merge；主迴圈在每片文件與證據同步後停下，
只在使用者確認後進行該片 commit／PR／merge。

## 3. 橫切 15 REQ 唯一 owner

`docs/implementation-slices.md` 的 15 條精確集合是 PROD(4)＋SCOPE(2)＋UX(5)＋QA(4)。
`HANDOFF.md` 的「UX/QA 15 REQ」只是簡稱；`REQ-CONTENT-001` 是額外 G2 依賴，不計入 15。

| Requirement owner | Owning requirements | 數量 | Closure 說明 |
|---|---|---:|---|
| `presentation-ui` | REQ-UX-001、REQ-UX-002、REQ-UX-003、REQ-UX-005 | 4 | 第 1 片建立正式證據；第 2 片文案／資產變更後重跑 gate |
| `content-production` | REQ-PROD-001、REQ-SCOPE-002、REQ-QA-001 | 3 | 完整內容、資產與匯出前 validator |
| `balance-playtest` | REQ-PROD-002、REQ-PROD-004 | 2 | 第 3 片負責候選與調校；真人樣本由第 4 片收口 |
| `performance-release` | REQ-PROD-003、REQ-SCOPE-001、REQ-UX-004、REQ-QA-002、REQ-QA-003、REQ-QA-004 | 6 | 最終離線、效能、追溯與 runner/release gate |
| **合計** | 無重複、無缺漏 | **15** | |

額外依賴：`REQ-CONTENT-001` 的 G2 owner 為 `content-production`，第四片重跑其 release gate。

## 4. 全域 AC-001～078 唯一 closure owner

此處的 owner 是 **G2 closure 證據責任**，不取代 S1～S5 的歷史實作 owner。每個 AC
只出現一次；其他切片若供應 component evidence，仍不得自行把該全域 AC 標為完成。

| Slice | 證據模式 | Global AC |
|---|---|---|
| `presentation-ui` | 正式 UI／UX 新證據或重證 | AC-004、AC-005、AC-006、AC-007、AC-017、AC-020、AC-024、AC-028、AC-029、AC-039、AC-044、AC-049、AC-055、AC-065、AC-070、AC-072、AC-075、AC-076、AC-077 |
| `content-production` | 正式內容／資產／codec 新證據或重證 | AC-015、AC-016、AC-018、AC-021、AC-022、AC-023、AC-033、AC-034、AC-038、AC-046、AC-047、AC-050、AC-051、AC-052、AC-057、AC-060、AC-067、AC-074 |
| `balance-playtest` | 最終候選 TUNE／統計重證 | AC-001、AC-002、AC-008、AC-009、AC-010、AC-011、AC-012、AC-013、AC-019、AC-030、AC-045、AC-048、AC-056、AC-059、AC-062 |
| `performance-release` | 新 release／migration／外部 Gate 證據 | AC-025、AC-026、AC-031、AC-032、AC-036、AC-037、AC-040、AC-042、AC-043、AC-053、AC-054、AC-071、AC-078 |
| `performance-release` | 無 G2 語意變更；最終 All／soak regression 聚合 | AC-003、AC-014、AC-027、AC-035、AC-041、AC-058、AC-061、AC-063、AC-064、AC-066、AC-068、AC-069、AC-073 |

計數檢查：presentation 19＋content 18＋balance 15＋performance 26＝78；重複 0、缺號 0。

### 跨片邊界

- AC-032：唯一 closure owner 為 `performance-release`；第三片只能產 RC、報告格式與
  provisional TUNE，不得提前標 PASS。
- AC-033：唯一 owner 為 `content-production`；第一片視覺樣板仍須保存原創性初審證據。
- AC-077：唯一 owner 為 `presentation-ui`；第二片正式潤飾 ContentDefinition 文案後必須重跑。
- AC-025／026：第二片提供 migration component evidence，第四片完成 schema matrix、
  G1→G2 bridge 與 byte-preserving fail-closed 證據。
- AC-078：唯一 owner 為 `performance-release`；第二片只提供 codec 2→3、schema 3→4
  與 migration fixture，不得提前宣稱完成強制 G2 rebase。
- presentation-ui 的 19 條 owning AC 必須逐條提供 fresh production evidence；既有 G1
  domain／灰盒 PASS 只能當 regression 輸入，不能單獨完成 G2 closure。

## 5. 共同 SDD／TDD／Review 管線

每片依序執行，不能跳過：

1. 建立 `specs/<slice>/requirements.md`，逐條寫可測驗收並取得使用者核可。
2. 建立 `design.md`，完成需求對應、公開介面、failure policy、版本策略與測試表，再核可。
3. 建立 `tasks.md`，標 HARD／NORMAL、TDD／免TDD、依賴與雙向覆蓋，再核可。
4. 由測試代理把對應案例翻成紅燈；保存完整輸出及 SHA-256 manifest。
5. 鎖定測試後，互不重疊的實作代理只改授權範圍；主迴圈負責整合。
6. fresh 執行針對性 suite、All 與該片 soak／QA；比對 manifest 雜湊。
7. 兩位獨立 reviewer 對照 requirements／design／tests／diff。任何新問題立即硬停，
   由使用者逐項裁決；未裁決不得修下一輪或進下一片。
8. 回寫 implementation review、roadmap ledger、`PROGRESS.md`、`HANDOFF.md`、
   `docs/implementation-slices.md` 與 `.pipeline`，等待使用者確認 Git。

Art／audio 可標免 TDD，但必須通過資產 inventory、尺寸／格式、引用、透明邊界、色彩可讀性、
重複度、原創性、provenance 及多解析度畫面 QA。未採用大型生成原稿不得進 Git。

## 6. 各片完成 Gate

### 6.1 presentation-ui

- production App 不再引用 `scripts/dev/` 或 `scenes/dev/`。
- 正式主選單、完整 scene shell、presentation facade、設定／音訊／localization 可運作。
- 720p／1080p／1440p、鍵盤焦點、150% UI、四種色覺模式與非色彩提示通過。
- 戰鬥 1×／2×／4×／pause 不改 canonical result、事件順序或 hash。
- 第一批視覺樣板完成：3 位不同費用玩家棋、1 怪物、1 Boss、營地一角、核心 UI。
- **樣板必須由使用者確認後，第二片才能量產美術。**

### 6.2 content-production

- 44 UnitDef 全有正式 AbilityDef／EffectDef；數量、分布、事件選擇與 tooltip 全部通過 gate。
- save schema 4、content codec 3、codec 2→3 allowlisted migration 與 `5ddf80a` fixture 完整。
- 正式 ContentDependencyPort 實際驗 asset path／localization key；production 無 dev fake。
- 完整 runtime PNG／OGG、atlas、prompt／seed／處理參數及 provenance 已審。

### 6.3 balance-playtest（Phase 0 收尾 gate，2026-08-04 修訂）

- 全部 TUNE 轉為有版本候選（candidate id 由 tune_digest 衍生、失敗候選 immutable 留存）。
- 3k screening（1,000 shared seeds × 3 bot 策略）gate PASS：economy 勝場 ≥50、
  無 build 選取率超次名 20 個百分點、replay 抽驗 150/150 零 drift。
- 產出匿名 `PlaytestSessionReport v1`、Windows 可攜 ZIP、SHA-256 與 provisional RC。
- AC-032 保持 `PENDING_EXTERNAL`。
- 大樣本統計與「三條決策路線穩定通關」移至 6.3b（2026-08-04 使用者裁決；
  理由：Act 2/3 難度曲線為機制缺失，修復前的大樣本數字必然作廢）。

### 6.3b Phase 2 平衡收斂 gate（原 6.3 大樣本要求移入）

- 於 `difficulty-curve` 合併後執行 TUNE 迭代迴圈，每輪 3k screening 驗證。
- 收斂判準：三策略勝率皆落於 45~60% 帶、無任一 build 選取率超次名 20 個百分點、
  三幕皆有淘汰率（敗局不集中單一節點）、勝局血量有分佈（非滿血通關）。
- 收斂後執行大樣本統計（10k 或 30k seeds，規模與 runner 分片上限 16→24 屆時由
  使用者裁決）作為正式平衡基線；至少三條決策路線有穩定通關樣本。

### 6.4 performance-release

- Windows CI、固定 Godot 4.7 SHA、vendored GUT、export preset、離線完整遠征 smoke 皆通過。
- 最低規格實機：正常戰鬥 60 FPS、64 實體壓力場景 ≥55 FPS、tick p99 ≤8ms、
  queue 不持續成長且峰值 ≤4096。
- G1→G2 root generation 強制 rebase 與 signed committed-object bridge 通過 migration matrix；
  任一驗證失敗皆 byte-preserving fail-closed。
- 至少 30 人／90 場真人報告通過產品時長與三構築 Gate。
- 全域 78 AC、15 橫切 REQ、四片 implementation review 與雙審證據完整。

## 7. Completion ledger

| Slice | SDD | Implementation | Review | External gate | Git |
|---|---|---|---|---|---|
| `presentation-ui` | COMPLETE | T00–T15 COMPLETE; 19 AC PASS | R16 history＋merge-after-review findings closed | T13 USER APPROVED; final repair baseline Gut 1000/1000 | PR #5 MERGED @ 9362e7d；PR #6 MERGED @ 5e78ccf |
| `content-production` | COMPLETE | T00–T27 COMPLETE；acceptance 21＋1 全 PASS | T25 三輪雙審＋T18A 全批獨立人工採納 CLOSED | 44 adopted／14 rejected retained；Gut 281/1093；10k soak；All exit 0；fully_closed=true | PR #8 MERGED @ bf818fb |
| `balance-playtest` | COMPLETE | driver 正式鏈路／candidate／3k screening #2 gate PASS；Phase 0 收尾雙審雙 APPROVED | Phase 0 雙審閉環 CLOSED（含 BP-SI-007 修正） | AC-032 維持 PENDING_EXTERNAL；大樣本移 Phase 2（2026-08-04 裁決） | **PR #9 MERGED @ 24edea9** |
| `difficulty-curve` | IN PROGRESS（2026-08-04 起） | T01–T09 COMPLETE；3k screening fresh gate PASS；All 1,193/1,193；10k soak 10,000/10,000 | T11 NOT STARTED（雙審待執行） | — | 分支 `codex/g2-difficulty-curve` |
| `performance-release` | NOT STARTED | NOT STARTED | NOT STARTED | minimum PC＋90 games pending | not created |

## 8. 固定假設

- 發行平台只有 Windows 10／11 64-bit 離線可攜版。
- 正式輸入為滑鼠＋鍵盤；完整控制器支援不在 G2。
- 使用者負責分發測試 ZIP、回收匿名 JSON、提供符合規格的最低 PC。
- Codex 負責程式、內容、美術、音訊、分析、修正與證據整理。

## 9. Phase 0~3 執行計畫（2026-08-04 使用者裁決）

以「先修機制、再平衡輪迴」為原則排序；大樣本統計延後至平衡收斂後執行。

### Phase 0 — balance-playtest 收尾（已完成，2026-08-04，PR #9 MERGED @ 24edea9）

1. tier2+ 單位入樣補證（3k #2 報告無直接欄位，自 per-case 資料補確認）。
2. Part D 證據鏈：RC 重打包、start→save/load→terminal/abandon→report 全鏈路 smoke、
   source manifest、export 排除與 PCK inventory。
3. NUL 警告修正合入（`run_state_validator.gd` 的 `String.chr(0)` 分隔符，已另立任務）。
4. 文件回寫（PROGRESS、HANDOFF、evidence-index、implementation-slices）。
5. 兩位獨立 fresh reviewer 重審 → 使用者確認 → commit／PR／merge。

### Phase 1 — `difficulty-curve` 機制切片（Phase 0 合併後，spec 三件套流程）

解除平衡迴圈的結構性天花板，對應 `specs/balance-playtest/spec-issues.md`：

- 幕間難度縮放與三幕 Boss 差異化（`slice_boss_1/2` 引用機制）、多敵遭遇編成（BP-SI-004）。
- trait 門檻階梯化——2/4/6 隻遞增效果（BP-SI-005）。
- tier-1 池構成重整（shadow 選取率 0.16% 的結構性問題）。
- challenge run-op 分流與 global source lifecycle 矛盾正解（BP-SI-001/002）。
- balance runner 逐幕快照與 stable ID 可觀測性（BP-SI-006，可提前隨 Phase 0 順做）。

**完成狀態（2026-08-06）**：六項工作（T01～T09）全落地，BP-SI-001／004／005 與
BP-SI-006 (i)(ii) 已 RESOLVED；BP-SI-002 明示不做、續 OPEN。3k screening fresh gate
PASS（candidate `balance.g2.041458b08bb5`、`gate_reasons=[]`、3,000/3,000 terminal、
150/150 replay 零 drift；`act_curve` 顯示 act1／act3 皆有淘汰，跨幕梯度已生效）；
fresh All（Gut 1,193/1,193）與 10k ExpeditionSoak（10,000/10,000 passed）皆綠。
詳細證據見 `specs/difficulty-curve/evidence-index.md`；T11 雙審待執行。

### Phase 2 — 平衡迭代迴圈（Phase 1 合併後）

- TUNE 迭代：XP 性價比、verdant、單位數值、affix 強度；每輪改值 → 3k screening
  （約一晚，全自動）→ 分析 → 再調。
- 收斂判準見 §6.3b；達標後跑大樣本（10k/30k × 24 分片，規模與 runner 上限屆時裁決）
  作正式平衡基線，完成原 6.3 移入 6.3b 的全部要求。

### Phase 3 — 其後

- `performance-release`（既有第 4 片，§6.4 不變）；AC-032 外部工具鏈於此收口。
- 內容擴充（單位／遺物／事件充實池子）與後續呈現層迭代依 backlog 排程。

## 10. UI 線（與 Phase 0~3 並行，交 Codex）

UI／美術／中文化整修自成一條線，分支 `codex/g2-ui-art-refresh-b`，不佔用 Phase 0~3 的平衡工作序列。

| 階段 | 範圍 | 狀態 |
|---|---|---|
| Phase A | 可玩性止血（P0 五項） | ✅ 已合併 PR #11 → `master@823869a`（2026-08-07） |
| Phase B（1、2 項） | 全域 Theme `.tres`、內嵌 Noto Sans TC、縮放契約 | ✅ 已落地至 B1R3 |
| Phase B（第 3 項，局內） | 局內四 route 版面 | 🔄 **改由 `in-run-hud` 承接**（見下） |
| Phase B（第 3 項，局外） | 主選單／營地／設施／圖鑑／設定／結算 視覺重設計 | ⏸ 待局內完成後排 |
| Phase C | 美術資產接線（44 組 sprite／音訊） | ⏸ 未開始 |
| Phase D | 中文化收尾（字型內嵌後走查、gate 增補） | ⏸ 未開始 |

### `in-run-hud` 局內 HUD 重製（2026-08-09 使用者裁決）

三件套位於 `specs/in-run-hud/`，另附 `layout-reference-1920.json`。

- **範圍**：局內四個 route 全面重製；UI 設計基準 1280×720 → **1920×1080**（支援 2560×1440）；
  棋盤與單位移至世界層 3/4 投影；新增 ESC 系統選單；棋子與裝備拖曳（含合成）並保留鍵盤等價路徑。
- **裁決**：`ui-art-refresh` Phase B1R3 的視覺樣板不再作為基線，局內直接以新基準重新設計；
  局外畫面本片只做基準遷移的機械調整。
- **架構規格影響**：新增 `REQ-UX-006`、`AC-080`~`AC-082`、`DEC-015`，
  修訂 §10.1／10.2／10.3／10.4／10.6 並新增 §10.7；§14 矩陣與 manifest 已同步（`-Suite Spec` exit 0）。
- **分工**：實作交 Codex；唯一例外 `T01`（備戰期單位屬性預覽 API，domain 唯讀查詢）由 Claude 執行。
- **待 Codex plan 階段裁決**：世界層維持 640×360 或提升 960×540（規格建議前者，
  因後者在 2560×1440 為 2.667× 非整數縮放且需重生成全部 44 組資產）。
- **已知阻擋**：`RUN_COMBAT` 首幀 transcript exhausted 使戰鬥畫面無法實機截圖，
  `T22` 必須先於 `T23` 完成。
