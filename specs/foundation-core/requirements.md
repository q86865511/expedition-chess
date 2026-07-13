# S1 `foundation-core` 功能需求

> 狀態：`Approved / Implementation gate passed`
> 建立日期：2026-07-13
> 權威規格：[文件集入口](../../docs/game-architecture-spec.md) · [切片藍圖](../../docs/implementation-slices.md)
> 同組文件：[技術設計](design.md) · [實作任務](tasks.md)

## 1. 文件契約

本文件不複製或改寫主體架構規則。每個 `REQ-*` 的完整語意、數字與失敗行為，均以連結的權威章節及[第 14 章追溯矩陣](../../docs/game-architecture/10-traceability-matrix.md#section-14)為準；此處只鎖定 S1 的交付邊界、可觀察驗收與後續切片 owner。

S1 只有在下列條件同時成立時才可由 `Draft / Pending review` 改為 `Approved`：

1. 三件套經獨立複檢且沒有 `Blocker` 或 `Major`。
2. 下列 23 個需求均有 S1 驗收、設計對應與 tasks owner。
3. 標為 deferred 的架構 AC 仍保留原 owner，不得以 foundation fixture 假稱端對端通過。
4. 實作不引入 ShopService、BattleSimulation、EffectResolver 的假成功 stub。

## 2. 目標與邊界

### 2.1 S1 必須交付

- 可 headless 啟動的 Godot 4.7 專案、常駐 `Main/AppRoot`、最小 presentation 容器與允許的五個 Autoload。
- 決定性基礎：stable ID、`U64Bits`、RuntimeKeyCodec v1、PCG32 具名 stream、canonical BattleSetup codec 與 golden vectors。
- Authoring Resource、registry-owned catalog generation、具 manifest digest 的 `ContentRef`、無共享集合 view、S1 全 invariant 內容驗證器。
- 明確 DTO、`ResolutionState` tagged union、版本化 JSON codec、migration、原子存檔與 fault-injectable storage port。
- App／Run 狀態機及 RunController 的 copy-validate-save-swap 交易管線。
- GUT、content、canonical、spec contract、smoke runner 與可重現 artifact；不建立無實質驗證的 soak／戰鬥結果 runner。

### 2.2 S1 明確不做

- 戰鬥 tick、AI、鎖敵、尋路、傷害、效果套用與 BattleResult 計算。
- 商店、收入、XP、有限卡池、升星、羈絆、裝備、遺物與獎勵的 gameplay command。
- 三幕地圖、正式遠征內容、局外營地、正式 UI、美術、平衡與 playtest。
- G0／G1／G2 完整通關、10,000-seed gameplay soak 或效能宣告。

### 2.3 鎖定工具鏈指紋

| 元件 | 鎖定版本 | 鎖定 SHA-256 |
|---|---|---|
| Godot | `4.7.stable.official` | `b2ca888d5115a6cedee564764a2ee494a625f2ec2edbabd010fe33c9a88a6bf8` |
| GUT | `9.7.1` | tree SHA-256 `94cfb2346fa189bb358a499179161cabf6c3602485ce7f592683d5d3bb7f18d2` |

版本字串、SHA 任一不符或依賴來源為浮動版，`S1-AC-001` 必須失敗；不得用「可相容版本」替代上述精確指紋。

## 3. 架構 AC 覆蓋契約

本切片涉及的 global AC 固定分成三個互斥集合；三件套與 runner report 必須輸出並驗證同一集合，不得自行升降級：

- **F（S1 必須完整通過，15）**：`AC-025`、`AC-026`、`AC-036`、`AC-039`、`AC-040`、`AC-051`、`AC-052`、`AC-054`、`AC-055`、`AC-063`、`AC-064`、`AC-068`、`AC-069`、`AC-070`、`AC-078`。
- **X（S1 必須通過明列的 foundation 子驗收，但 global AC 保留 downstream gate，7）**：`AC-016`、`AC-027`、`AC-034`、`AC-047`、`AC-065`、`AC-073`、`AC-075`。
- **D（S1 不得宣稱通過，11）**：`AC-007`、`AC-020`、`AC-023`、`AC-024`、`AC-035`、`AC-041`、`AC-046`、`AC-058`、`AC-066`、`AC-072`、`AC-076`。

集合大小必須為 `15/7/11`、聯集 33 個且交集為空。S1 完成 gate 是：F 全數通過；X 的 S1 子驗收全數通過且保留 downstream owner；D 全數維持 deferred 且沒有 pass artifact。D owner 固定為：`007→S2`、`020→S3`、`023→S5`、`024→S2＋橫切 UI`、`035→S2/S3`、`041→S2/S3`、`046→S3/S4`、`058→S3`、`066→S2/S3/S4`、`072→S3/S4`、`076→S2/S3/S4`。X 的 `AC-075` 由 S1 驗證 authoring/view/catalog/setup-input 隔離，canonical BattleResult 由 S2 收尾。

## 4. S1 驗收需求

下表的「架構 AC／owner」採 `S1`、`S2 combat-core`、`S3 economy-expedition`、`S4 build-systems`、`S5 meta-progression`。`S1 部分`表示只驗證 foundation 契約，端對端 Then 仍由列出的 downstream owner 負責。

### 4.1 技術需求（6）

| S1 驗收 | 權威需求 | S1 交付邊界 | 可測驗收 | 架構 AC／owner |
|---|---|---|---|---|
| **S1-AC-001** | [REQ-TECH-001](../../docs/game-architecture/05-technical-architecture.md#section-8) | 鎖定引擎、GDScript、GUT、vendor 來源與雜湊；提供無本機絕對路徑的執行 wrapper。 | toolchain checker 對核定版本／雜湊回 0；任一版本、雜湊或浮動來源改動回 2；headless import 與最小場景 smoke 成功。 | AC-036：S1 完整。 |
| **S1-AC-002** | [REQ-TECH-002](../../docs/game-architecture/05-technical-architecture.md#section-8) | 實作 AppStateMachine 與 RunController transition gate；只提供狀態轉移基礎，不提供節點 gameplay。 | 矩陣內轉移成功且存檔後才生效；矩陣外轉移、presentation 直接寫 view 均被具名錯誤拒絕。 | AC-039：**F**。 |
| **S1-AC-003** | [REQ-TECH-003](../../docs/game-architecture/05-technical-architecture.md#section-8) | S1 跨模組 API 全部採具名 request／result／DTO 與 typed collection；JSON Dictionary 限於 codec 內。 | static API scanner 對公開參數、回傳、signal、集合元素掃描；加入未型別化 domain Dictionary fixture 時回 2。 | AC-054：**F**；AC-076：**D→S2/S3/S4**。 |
| **S1-AC-004** | [REQ-TECH-004](../../docs/game-architecture/05-technical-architecture.md#section-8) | RunController 統一使用 copy-validate-save-swap，canonical state 僅由 RunSession 持有。 | command 成功只 swap 一次；validation、tmp write、final read-back 失敗時 state、serial、RNG counter、事件皆 byte-equivalent 不變；修改 view 不影響 state。 | AC-039：**F**；AC-065：**X→S3 gameplay command**。 |
| **S1-AC-005** | [REQ-TECH-005](../../docs/game-architecture/05-technical-architecture.md#section-8) | 建立五個核定 Autoload，實例名與型別名固定分離。 | 掃描 `project.godot` 與全部 `class_name`；任何重名、額外 gameplay singleton 或遺漏均回 2。 | AC-068：S1 完整。 |
| **S1-AC-006** | [REQ-TECH-006](../../docs/game-architecture/05-technical-architecture.md#section-8) | S1 的 ContentRegistry、PinnedCatalogReceiptPort、RunController、SaveRepository、RngService 每個可失敗 API 都回具名錯誤；只有 `try_resolve` 可 nullable。 | 對合法與每種 failure fixture 呼叫，確認 error code／context 完整且零 partial mutation；公開 API 掃描拒絕其他 silent-null／assert-only 契約。 | AC-076：**D→S2/S3/S4**；S1 只驗自己的服務契約。 |

### 4.2 資料需求（8）

| S1 驗收 | 權威需求 | S1 交付邊界 | 可測驗收 | 架構 AC／owner |
|---|---|---|---|---|
| **S1-AC-007** | [REQ-DATA-001](../../docs/game-architecture/05-technical-architecture.md#section-8) | 建立權威清單中的 ContentDefinition Resource 與 typed operation subresource；UnitDef 明確保存移速、三個星級倍率、基本攻擊 profile 與商店條件；consumer 只經 registry。 | 合成 `.tres` 可載入、編譯及解析；UnitDef 缺上述任一欄、星級缺/重複或倍率越界均回固定錯誤；static scan 找到 UI/domain 直接 preload 內容 Resource 或重複規則常數時回 2。 | AC-024：**D→S2＋橫切 UI**；AC-047：**X→後續正式內容**；AC-075：**X→S2 canonical BattleResult**。 |
| **S1-AC-008** | [REQ-DATA-002](../../docs/game-architecture/05-technical-architecture.md#section-8) | 建立 S1 所列 runtime DTO、具名 result/error、exact field/type/nullability schema 與 deep-copy contract。 | 每個 DTO 經 SaveJsonCodec round-trip 後值等價；unknown/missing/duplicate field 失敗；static/dependency scan 證明不含 Node、Resource、Callable、Object ID 或 SceneTree path。 | AC-040：S1 對 S1 DTO 完整，後續新增 DTO 增量重跑。 |
| **S1-AC-009** | [REQ-DATA-003](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | 實作 stable ID regex、alias/tombstone catalog 及 schema 0→1 fixture。 | 合法 ID 通過；非法、重用、alias cycle 失敗；alias fixture 資料守恆且二次 migration 不變。非必要圖鑑 tombstone 必須安全載入、保留資料並在二次 migration 不再改變；active run 當前棋子／遺物等必要內容 tombstone 必須隔離 run、保留 Profile 與原檔且不得猜測替代。 | AC-025、AC-026、AC-051、AC-052：S1 完整。 |
| **S1-AC-010** | [REQ-DATA-004](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | `RosterState` 是 board、bench、inventory、overflow、五遺物槽唯一序列化 owner；RunViewState 只投影。 | 含全部容器的 round-trip 值一致；codec 拒絕頂層重複欄位；修改 view nested collection 不影響 canonical。 | AC-055：S1 完整；S4 對實際裝備／遺物流程重跑。 |
| **S1-AC-011** | [REQ-DATA-005](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | 實作 BattleSetupInputs、EncounterPreviewSnapshot、CanonicalBattleCodec v1 與 builder；有效單位 stats 含移速；不實作模擬。 | 已提交 preview + 合法 synthetic 備戰 fixture：改玩家站位或有效移速後 hash 改變，只改 EconomyState 的 shop refresh index 後 hash 不變；敵方永遠逐欄等於 preview；inputs 不含 seed/hash，combat seed 在 hash 後派生。 | AC-064：**F**；AC-041：**D→S2/S3**。 |
| **S1-AC-012** | [REQ-DATA-006](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | ContentSnapshotState 為不可變純 DTO；load 先以 persisted selection probe 重建 pinned generation，再分離 profile/run 狀態並隔離不相容 run。 | fresh registry 只有 full latest 時，若相同 packs仍在，必須從 raw enabled/config/table IDs重建相同 filtered digest並載入 run；未安裝/selection-digest mismatch時 profile 可用、run=`incompatible_preserved`、原檔不改；取消放棄零 mutation，確認放棄先封存且只清 run。 | AC-070、AC-078：**F**；AC-023：**D→S5**。 |
| **S1-AC-013** | [REQ-DATA-007](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | 實作 RuntimeKeyCodec v1、六種 per-kind typed builder/schema、SHA-256、run/node golden vectors、唯一性與 serial guard；每個持久 key 同存 typed tuple 與 digest，production 不開放 raw token-array constructor。 | `run/node/reservation_owner/transaction/effect_claim/settlement_receipt` 逐 kind 驗欄位數、tag 與順序；run/node golden bytes／digest 完全相同；RunState/MapNodeState round-trip 後仍能逐欄重建 tuple；其餘 kind 有 positive 與 wrong-count/tag/order negative fixture；property suite 拒絕重複 tuple/key、digest mismatch、欄位竄改、serial rollback／overflow；retry 重用原 tuple。 | AC-073：**X→S2/S3/S5 實際來源流程**。 |
| **S1-AC-014** | [REQ-DATA-008](../../docs/game-architecture/05-technical-architecture.md#section-8) | BOOT 將 Resource 編譯為 canonical catalog generation；run selection 另編譯 filtered pinned generation；ContentRef 必含 digest；registry 同時保留 A/B。 | snapshot enabled IDs 恰等於其 generation active entry-index 全集，config/table IDs為子集；selection缺依賴或 receipt/digest不一致失敗；fresh process 可從 persisted typed selection 重建 filtered generation，不嘗試由 digest 反推。A/B 含同 stable ID 異值：pinned run handle 只 resolve A、明確 latest/CAMP handle 只 resolve B；重載仍為 A；缺 digest API 不存在；移除 A 只標 run incompatible 而不 fallback B；修改 view/authoring Resource 不改 A 的 current catalog、manifest digest 或 canonical BattleSetup inputs。 | AC-078：**F**；AC-075：**X→S2 canonical BattleResult**；AC-024：**D→S2＋橫切 UI**。 |

### 4.3 亂數需求（2）

| S1 驗收 | 權威需求 | S1 交付邊界 | 可測驗收 | 架構 AC／owner |
|---|---|---|---|---|
| **S1-AC-015** | [REQ-RNG-001](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | 實作 `map/shop/reward/combat` 命名 stream 派生、snapshot 與持久版本／seed／counter。 | 增加 map raw draws 後 synthetic shop/reward/combat stream 的前 N 個輸出與 snapshot 不變；derive 不消耗父或其他 stream。 | AC-027：**X→S2/S3 實際 consumers**；AC-007：**D→S2**；AC-041：**D→S2/S3**；AC-064：**F**。 |
| **S1-AC-016** | [REQ-RNG-002](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | 逐位實作 U64、PCG32、FNV-1a、SplitMix64、rejection sampling 與 16-hex codec。 | 兩組 PCG golden、bounded vector、counter 及 U64 helper 邊界逐位相同；另對 `run_seed`、四個 stream 各自的 `state/inc/counter`、`next_run_serial`、`next_transaction_serial`、`next_unit_serial`、`next_item_serial` 每一欄逐欄 round-trip `0/2^53-1/2^53/2^53+1/2^63/2^64-1`，JSON 恰為 16-lowercase-hex String、不得為 number。任何非法 hex／bound回具名錯誤且不耗 stream。 | AC-063：S1 完整。 |

### 4.4 存檔需求（6）

| S1 驗收 | 權威需求 | S1 交付邊界 | 可測驗收 | 架構 AC／owner |
|---|---|---|---|---|
| **S1-AC-017** | [REQ-SAVE-001](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | 實作 schema v1 JSON、tmp read-back、main/backup rotation、final read-back 與 restore。 | 正常、首次、main+backup、backup-only、partial write 與損毀 main fixture 都符合 committed-copy invariant：交易開始已有 committed copy 時任一 fault/crash 後仍至少一份有效；首次存檔提交前失敗可維持零 committed，但不得接受 tmp/半檔，成功後 main 必須有效。bytes 為 UTF-8 JSON，u64 為 16-hex。 | AC-026、AC-069：S1 完整。 |
| **S1-AC-018** | [REQ-SAVE-002](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | S1 只提供可保存的 BattleSetup／Resolution/PendingReward／receipt DTO 與 retry identity，不實作戰鬥或獎勵結算。 | 對 `idle`、`combat_pending`、`battle_result_pending`、`reward_pending` 各建立 fixture，連續執行 `save→load→retry→save→load`；每輪的 seed、candidate、reservation、transaction、claim、receipt tuple/digest 與 canonical bytes 等值，serial/counter 不前進且不產生任何新 key。 | AC-020、AC-058：**D→S3**；AC-066：**D→S2/S3/S4**；AC-035：**D→S2/S3**；AC-046：**D→S3/S4**。 |
| **S1-AC-019** | [REQ-SAVE-003](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | 建立 schema 0→1、alias、tombstone 保留 fixture 與逐版 migration registry。 | schema 0 僅補 `hash_version=1`；重跑 byte-equivalent；parse failure source schema為typed unknown，合法schema 0為typed known(0)；缺 migration step 回具名錯誤且不覆寫來源。 | AC-025、AC-051、AC-052：S1 完整；未來 schema owner 必須增量擴充。 |
| **S1-AC-020** | [REQ-SAVE-004](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | RunController 提供 commit-before-present publish boundary；S1 以 typed test command 驗證。 | SaveResult 成功前沒有 view/event；各 fault point後重載只見舊 state；成功後只發布一次新 view。 | AC-065：**X→S3 gameplay command**；AC-046：**D→S3/S4**。 |
| **S1-AC-021** | [REQ-SAVE-005](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | `ResolutionState` 以四個具型別 payload subclass 表示，PendingRewardState 單一路徑串行 stage／phase。 | codec 拒絕未知 kind、多 payload、平行 pending boolean、非法 stage/phase；四種合法 payload round-trip。 | AC-035：**D→S2/S3**；AC-066：**D→S2/S3/S4**；AC-072：**D→S3/S4**；S1 負責表示法。 |
| **S1-AC-022** | [REQ-SAVE-006](../../docs/game-architecture/06-data-rng-and-save.md#section-9) | SaveRepository 以 `Mutex.try_lock()` 短鎖保護 repository-wide `_operation_in_progress` flag，讓 save/load/repair 互斥；fake 以 `operation kind + logical path + occurrence` 對每個 directory/exists/open/read/write/flush/close/rename/quarantine/restore/remove 呼叫 fault injection。 | 跨/same-thread 的 save→save、save→load、load→save、repair-load→save 第二請求都回具名 busy error；每個 port invocation 可注入且穩定失敗，無交錯、tmp/corrupt 不成 committed。 | AC-026、AC-069：**F**。 |

### 4.5 內容需求（1）

| S1 驗收 | 權威需求 | S1 交付邊界 | 可測驗收 | 架構 AC／owner |
|---|---|---|---|---|
| **S1-AC-023** | [REQ-CONTENT-001](../../docs/game-architecture/04-content-and-meta-progression.md#section-6) | 完整實作[第 11.2 節](../../docs/game-architecture/08-testing-and-acceptance.md#section-11) invariant；以合成完整切片 fixture 驗證，不交付正式內容。 | valid fixture 回 0；逐項破壞 ID、引用、數量、費用分布、標籤、配方、門檻、challenge、權重、解鎖、人口、effect/intent 等 invariant，各自回規格鎖定 error ID 與 2。baseline 三個 +1 來源計出 12 與 per-side 壓測下限 16；第四個 +1 重算為 13／17。summon operation 必須有有限 `max_active_per_source`，召喚目標不得再含 summon 且圖無循環；最大同時實體數為「玩家起始與有界召喚＋最大遭遇起始與有界召喚」，entity 壓測下限為 `max(64, computed maximum)`；缺 bound／循環各有 mutation。S1 只計算報告，不執行實戰壓測。 | AC-016、AC-034、AC-047：**X**；分別由 S4、S2、後續正式內容收尾。 |

## 5. 跨切片驗收保留規則

- S1 的 synthetic fixture 只證明 codec、validator 與 transaction substrate 可運作，不代表正式遊戲內容或 gameplay Then 已存在。
- `AC-007`、`AC-035` 由 S2 接上真正 BattleSimulation 後才可完整勾選；`AC-041` 由 S2/S3 接上戰鬥與真實商店／板凳 command；`AC-064` 已由 S1 synthetic canonical setup gate 完整驗收。
- `AC-020`、`AC-046`、`AC-058`、`AC-066`、`AC-072` 由 S3（涉及裝備／遺物時再由 S4）完成 gameplay transaction。
- `AC-016` 由 S4 的正式配方內容完成；S1 只驗證 21 組 invariant。
- `AC-023` 的局外解鎖端由 S5 完成；`AC-078` 已由 S1 以明確 pinned/latest handle 完整驗收。
- `AC-075` 在 S1 只通過 authoring/view/catalog/setup-input 隔離 fixture；S2 接上 BattleSimulation 後才驗 canonical BattleResult 不變。
- 後續新增任何跨模組 API、DTO、schema 或內容型別，都必須重跑 S1 static、migration、canonical 與 no-partial-mutation suites。

## 6. 完成定義

S1 可宣稱完成的必要條件如下：

1. [tasks.md](tasks.md) 中非 deferred 任務全部勾選且每項附實際命令證據。
2. 23 個 `REQ-*` 均由至少一個通過的 `S1-AC-*` 覆蓋，且 global AC 集合機器檢查結果恰為 F=15、X=7、D=11：F 全 pass、X 的明列 S1 子驗收全 pass 且 downstream 保留、D 全 deferred 且無 pass artifact。
3. headless import、typed parse、GUT、content validation、canonical、spec contract、save fault injection 與 smoke 全部回 0 並產生 artifact。
4. 失敗 fixture 回 2、runner infrastructure failure 回 3、外部 timeout 回 124；不得把缺少 runner 或 fixture 當通過。
5. 本切片沒有戰鬥、經濟、構築、正式 UI、正式內容或 G0 可玩性完成宣告。
