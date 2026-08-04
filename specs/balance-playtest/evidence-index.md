# G2 balance-playtest — Fresh evidence index

> 本表只記錄本分支 fresh 執行結果。`AC-032` 是第四切片外部 Gate，第三切片固定為
> `PENDING_EXTERNAL`；bot wall time 不列為真人時長證據。

| Global AC | 本切片重證 | Fresh evidence | 狀態 |
|---|---|---|---|
| AC-001 | 三幕路徑與 Boss 拓樸 | `balance-measure-{primary-seed1,replay-seed0}.json`：三策略真實 21-node／formal settlement 路徑；3k screening #2 gate PASS（candidate `balance.g2.7d47fada8091`，2026-08-04）為現行 screening 證據，Phase 0 收尾時刷新本表 | PARTIAL |
| AC-002 | 10k map seeds 無斷路 | `expedition-soak.json`，10,000 seeds／0 failures | PASS |
| AC-008 | overtime 唯一 terminal result | fresh All：Combat runner＋GUT battle simulation | PASS |
| AC-009 | 普通戰敗結算 | fresh All GUT `test_battle_settlement_commands.gd` | PASS |
| AC-010 | Boss 敗退、重載與 retry | fresh All GUT battle settlement／Boss retry integration | PASS |
| AC-011 | 首次節點收入／利息／連勝 | fresh All GUT income／node-entry integration | PASS |
| AC-012 | 每幕二連敗補助 exactly-once | fresh All GUT settlement stipend cases | PASS |
| AC-013 | 卡池＋候選＋持有守恆 | `expedition-soak.json` 10k pool checks＋All GUT | PASS |
| AC-019 | 戰敗不產生獎勵 | fresh All GUT battle settlement／reward integration | PASS |
| AC-030 | 10k full headless invariant gate | full-expedition driver 單 seed 三策略已 terminal；3k screening #2 已 PASS；10k invariant gate 依 2026-08-04 使用者裁決延後至 Phase 2（`specs/g2-roadmap.md` §9） | PARTIAL |
| AC-045 | 全地圖路徑合法 | `expedition-soak.json` 10k topology | PASS |
| AC-048 | 資源、商店、升星、出售守恆 | fresh All GUT economy commands＋10k `expedition-soak.json` | PASS |
| AC-056 | 人口 12 與 setup 前拒絕 | fresh All GUT population／board validation | PASS |
| AC-059 | proposal 失敗丟棄、勝利一次提交 | fresh All GUT battle settlement／claim_scope integration | PASS |
| AC-062 | 164 XP、跨級 overflow、9 級停用 | fresh All GUT XP command integration | PASS |
| AC-032 | 30 人／90 場、真人 45–60 分鐘 | `PlaytestSessionReport v1` 與 provisional RC 僅提供收集工具 | PENDING_EXTERNAL |

## Artifact read-back

- `artifacts/test/balance-measure-primary-seed1.json`：三策略各一個非 replay case；primary
  75.571／9.379／81.998 秒，平均 55.649 秒，三者 terminal、無 driver failure。
- `artifacts/test/balance-measure-replay-seed0.json`：三策略各一個 deterministic sampled
  replay；primary 平均 57.209 秒、replay 平均 57.890 秒、0 drift。
- 合併六筆 primary 平均 56.429 秒；套 5% replay 後有效估計 59.323 秒/case。
  3,000 cases 單程序理想估計 49.44 小時；此為校準前基準，不作最終分片裁決。
- `artifacts/test/balance-calibration.json`：完成使用者核可的 8-shard／24-case 校準；
  primary 24/24、replay 3/3、0 drift、0 failed seed，所有 shard 均有 per-case proof 且
  綁 source freeze `716e9a324aae2f95c493ada5fde7ea4e390ad10507bc1bd7db9d4d1e4b3ec477`、
  candidate `balance.g2.5e5e8c4e9b70`。primary 平均 64.402 秒、replay 平均
  71.149 秒，相對 56.429 秒單程序基準 slowdown 14.13%，量化裁決為 `USE_8_SHARDS`。
- `artifacts/test/balance-playtest-screening.json` 目前是 **2-seed／2-shard 聚合器 smoke**，
  不是正式 3k：6/6 cases、3/3 deterministic replay、0 drift，source/candidate 一致；
  Gate 僅因每策略未達 500 terminal／50 wins 而預期 FAIL。正式 3k 執行時會原子覆寫此檔。
- `specs/balance-playtest/candidates/balance.g2.5e5e8c4e9b70.json`：append-only candidate；
  tune digest `5e5e8c4e9b7008c54cb1d3e7fc3bc44478d36e7df90b2d9a799b54791bf75b9f`。
- 舊 `balance-playtest-screening.json`／`balance-playtest.json` 使用代表戰鬥 driver，
  已由 rewrite review 撤銷，不得作本輪 Gate 證據。
- `artifacts/test/expedition-soak.json`：10,000 seeds，PASS。
- `artifacts/test/runner-execution.json`：fresh All Gate（待最終保存，避免被單 suite wrapper 覆寫）。
- `artifacts/rc/ExpeditionChess-g2-rc1-win64.zip(.sha256)`：fresh-profile offline boot PASS；互動式開始／存讀／完成或放棄／report smoke 尚未執行。
- `artifacts/test/balance-phase0-tier2plus-evidence.json`：frozen 3k #2 的兩來源統計一致，tier2+ 確實入樣（277 selections／230 cases／13 units）；tier5 為 0 selections，不宣稱每一個高階 tier 均已入樣。
