# S3 `economy-expedition` 最終獨立複檢

> 日期：2026-07-22
> 審查方式：主代理外的獨立 spec reviewer 與 implementation reviewer；兩者唯讀、不修改、不 commit

## 最終 verdict

| Gate | 輪次 | Blocker | Major | Minor | Verdict |
|---|---:|---:|---:|---:|---|
| T00R 規格複檢 | 5 | 0 | 0 | 0 | PASS |
| T11B 實作複檢 | 5 | 0 | 0 | 0 | PASS |

T11B 第五輪原回報有一項 acceptance evidence mapping 建議；主線已在產生最終 artifact 前把卡池耗盡的 unit-only event fallback 測試加入 S3-AC-011，因此最終可執行狀態為 Minor 0。

## 複檢驅動的主要修正

- 戰鬥 node 使用 pinned EncounterCompiler preview；merchant／event／treasure／rest 具正式持久化出口，不會停死於 PREPARE。
- 新增不可逆 RESULTS terminal，涵蓋 HP 歸零、Boss 放棄與第三幕 Boss 最終獎勵。
- phase／resolution 與 reservation owner↔offer↔pool aggregate 由 RunStateValidator 雙向驗證。
- RewardTableDef／receipt reward_table_ids、typed conditions、standard／relic／event fallback 與 unit-only event pool-exhausted policy均納入 content/runtime contract。
- 菁英 standard→relic、refresh、event unit grant 與各 reward subphase具 save-failure／crash-load 證據。
- 10k soak 改驗完整 21 層拓樸、全相鄰層 edge、reservation ledger 與 artifact freshness。
- 最終 artifact read-back 發現舊 Expedition runner 在 script error 後留下假綠 artifact；已改走正式 `RunController` save/reload transaction seam，並讓自製 runner script error 或 S3 acceptance 缺證直接使 `All` 非零。

## 證據規則

最終完成證據：`-Suite All` exit 0（GUT 228 tests／3681 assertions；Spec 3170 cases）、`ExpeditionSoak -SeedCount 10000` exit 0（10,000 checks／64 replays）、`expedition-acceptance.json` 的 `evidence_verified=true` 與 S3-AC-001～011 之 11／11 pass；提交前另執行 staged diff read-back。
