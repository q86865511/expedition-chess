# G2 balance-playtest — Fresh evidence index

> 本表只記錄本分支 fresh 執行結果。Phase 0 runtime source commit 為
> `6b072f8be1be39f5ee0644e5b2d7ab4d4960756e`；`source-manifest.json` SHA-256 為
> `345bb6c4f3c1a06b64dc346110832fb4e26792b8a5f6f75ef4922b222bd40b26`。
> `AC-032` 是第四切片外部 Gate，第三切片固定為 `PENDING_EXTERNAL`；bot wall time
> 不列為真人時長證據。

| Global AC | 本切片重證 | Fresh evidence | 狀態 |
|---|---|---|---|
| AC-001 | 三幕合法路徑、每幕七節點與三個 Boss | `artifacts/test/balance-playtest-screening.json`：3,000/3,000 terminal、完整 21-node route proof、gate PASS；`artifacts/rc/final-all-evidence.json` | PASS |
| AC-002 | 10k map seeds 無斷路 | `artifacts/rc/expedition-soak-evidence.json`：10,000 seeds／10,000 cases／0 failures | PASS |
| AC-008 | overtime 唯一 terminal result | `artifacts/rc/final-all-evidence.json`：Combat＋GUT，9 steps 全綠 | PASS |
| AC-009 | 普通戰敗結算 | `artifacts/rc/final-all-evidence.json`：battle settlement cases | PASS |
| AC-010 | Boss 敗退、重載與 retry | `artifacts/rc/final-all-evidence.json`：Boss retry／settlement integration | PASS |
| AC-011 | 首次節點收入／利息／連勝 | `artifacts/rc/final-all-evidence.json`：income／node-entry integration | PASS |
| AC-012 | 每幕二連敗補助 exactly-once | `artifacts/rc/final-all-evidence.json`：settlement stipend cases | PASS |
| AC-013 | 卡池、候選、持有守恆 | `artifacts/rc/expedition-soak-evidence.json`：10,000 pool-conservation checks；final All | PASS |
| AC-019 | 戰敗不產生獎勵 | `artifacts/rc/final-all-evidence.json`：battle settlement／reward integration | PASS |
| AC-030 | 10k full-headless invariant gate | 3k screening #2 gate PASS；`artifacts/rc/expedition-soak-evidence.json` 提供 10k map/economy regression。依 `rewrite-plan.md` 附錄 D 與 `g2-roadmap.md` §9，10k/30k full balance cohort 延後 Phase 2，不於 Phase 0 冒充完成 | PARTIAL / DEFERRED_PHASE2 |
| AC-045 | 全地圖路徑合法 | `artifacts/rc/expedition-soak-evidence.json`：10k topology／0 failures | PASS |
| AC-048 | 資源、商店、升星、出售守恆 | final All economy commands＋10k soak 的 40,000 build operations | PASS |
| AC-056 | 人口 12 與 setup 前拒絕 | `artifacts/rc/final-all-evidence.json`：population／board validation | PASS |
| AC-059 | proposal 失敗丟棄、勝利一次提交 | `artifacts/rc/final-all-evidence.json`：battle settlement／claim_scope integration | PASS |
| AC-062 | 164 XP、跨級 overflow、9 級停用 | `artifacts/rc/final-all-evidence.json`：XP command integration | PASS |
| AC-032 | 30 人／90 場、真人 45–60 分鐘 | `artifacts/rc/rc-evidence.json` 與兩份 `report-samples/` 只證明匿名報告收集工具；外部真人 Gate 尚未執行 | PENDING_EXTERNAL |

## Phase 0 final read-back

- Frozen 3k #2：`artifacts/test/balance-playtest-screening.json`，SHA-256
  `810d36a31f756f500307de26f7ede36f2e0c21290767121a7aef9f0e665f3717`；
  candidate `balance.g2.7d47fada8091`、3,000/3,000 terminal、150/150 replay 零 drift、
  0 failure、economy 1,000 wins、dominance 15.8pp、gate `PASS`。本次只讀引用，
  收尾前後 hash 不變，未重跑或覆寫。
- Tier 2+：`artifacts/test/balance-phase0-tier2plus-evidence.json`；兩來源完全一致，
  tier 1～5 selections 為 52,723／264／12／1／0，tier 2+ 合計 277 selections、
  230 cases、13 units。只宣稱 tier 2+ 確實入樣，tier 5 明列為 0。
- NUL 等價：`artifacts/test/balance-phase0-nul-replay-equivalence.json`；8 個獨立程序、
  24/24 terminal、24/24 `replay_digest` 對 frozen 3k 一致、0 mismatch、seed 0
  三 replay 零 drift、`Unexpected NUL character` 0。
- Targeted GUT：`artifacts/test/balance-phase0-targeted-gut-evidence.json`；balance
  24 tests／136 assertions、node receipt 13／38、meta progression 216／1,147，
  三組皆 exit 0、failures/errors/orphans 全為 0。
- NUL 修正後第一輪完整 All：`artifacts/test/balance-phase0-all-pre-freeze-evidence.json`；
  9 steps、GUT 1,125 tests／22,217 assertions、0 failures/errors/orphans、NUL warning 0。
- Final source manifest：`artifacts/rc/source-manifest.json`；commit
  `6b072f8be1be39f5ee0644e5b2d7ab4d4960756e`、Godot
  `4.7.stable.official.5b4e0cb0f`，All／soak／RC 三個 wrapper 均內嵌同一 manifest SHA。
- Final All：`artifacts/rc/final-all-evidence.json`；9 steps、GUT 1,126 tests／
  22,224 assertions、0 failures/errors/orphans，19 logs 的 NUL warning 合計 0。
- ExpeditionSoak：`artifacts/rc/expedition-soak-evidence.json`；10,000 seeds／
  10,000 cases／10,000 pool checks、64 deterministic replays、40,000 build operations、
  `failures=[]`。
- RC：`artifacts/rc/rc-evidence.json`；三個實際匯出 EXE 程序 exit 0，start→save→
  restart/load→natural RESULTS→第二 run→restart/abandon 全通過；兩份 report outcome
  為 `victory`／`abandoned`，皆通過 codec read-back。
- PCK／ZIP：`artifacts/rc/pck-inventory.json` 為 2,988 files、固定 candidate 恰一份、
  `addons/gut/`、`tests/`、`specs/`、`tools/` 禁入數 0；ZIP 頂層恰四檔，
  SHA-256 `004441c15163b8d99bbc1f180adb0df6b42c2b62b111c6e7898cd8c9f8eadd87`。
- 總摘要：`artifacts/rc/phase0-final-evidence-summary.json`。Phase 0 證據收尾完成，
  但切片仍為 `NOT APPROVED / FINDINGS OPEN`，等待兩位 fresh reviewer 與使用者確認。
