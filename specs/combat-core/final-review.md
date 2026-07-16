# S2 `combat-core` 最終獨立複檢紀錄

> 複檢者：Codex（與實作階段分離的 requirements 對照輪次）
> 日期：2026-07-16
> 判準：`requirements.md` 的 S2-AC-001–018、`design.md`、主架構 §5／§8／§9／§11
> 注意：這不是 Claude 外部複檢報告，也不取代使用者安排的外部 review。

## 結論

| 等級 | 開啟 | 已修正 |
|---|---:|---:|
| Blocker | 0 | 0 |
| Major | 0 | 7 |
| Minor | 0 | 1 |
| Question | 0 | 0 |

最終 verdict：`PASS`。所有實作複檢 finding 均有對應 regression test；正式完成仍以 `-Suite All`、`-Suite Soak -SeedCount 10000` 與 `combat-acceptance.json` 讀回結果為準。

## 已關閉 finding

| ID | 原等級 | 對應需求 | 失敗情境 | 修正與證據 |
|---|---|---|---|---|
| S2-REV-001 | Major | S2-AC-010／REQ-COMBAT-003 | 同一傷害波次逐筆改 health，後續事件看見非 wave-start 狀態，overkill／killer 可能漂移 | 引入 typed `BattleDamageRequest/Outcome` 與共享 final-health wave；`test_damage_wave_uses_shared_final_health_and_deterministic_killer` |
| S2-REV-002 | Major | S2-AC-009／REQ-COMBAT-002 | 施法 resolve 或 fizzle 後同 tick 再執行普攻／移動 | 保存 `last_main_action_tick` 並在 action phase 阻擋第二次主行動；完整 battle-simulation regression 通過 |
| S2-REV-003 | Major | S2-AC-011／REQ-COMBAT-005 | overtime 在一般行動後才套用，可能先被攻擊改變結果 | overtime 固定在 phase 1 建立並於普通 action 前處理死亡；`test_overtime_starts_at_1200_and_forces_result_before_hard_limit` |
| S2-REV-004 | Major | S2-AC-010／REQ-EFFECT-001 | kill/death trigger 產生事件早於 death event，破壞固定 mini-sequence | death/fizzle event 先 materialize，trigger operation 延至下一 FIFO wave；simultaneous-death 與 event codec regression 通過 |
| S2-REV-005 | Major | S2-AC-013／REQ-EFFECT-001 | stacking 四語意或 duration 到期缺乏 exact ordering／事件 | 新增 `BattleTimedStackResolver`、applied sequence 與 expire events；四個 stacking testcase 及完整矩陣通過 |
| S2-REV-006 | Major | S2-AC-006／S2-AC-014 | summon ID、max-active、entity budget 或 failure precedence 依 runtime 順序漂移 | BSI1 typed ID、per-source serial、固定 failure precedence、collision fatal 與 rollback；summon/encounter/effect tests 通過 |
| S2-REV-007 | Major | S2-AC-007／S2-AC-010 | 初始棋子普攻 presentation profile 由射程猜測，`magic_projectile` authoring 無法生效 | `UnitBattleSnapshot.basic_attack_profile` 納入 setup v2 canonical bytes、save JSON 與 validator；v1 golden 不變；`test_v2_round_trip_hash_envelope_and_v1_golden_compatibility`、`test_initial_unit_attack_event_uses_hashed_presentation_profile` |
| S2-REV-008 | Minor | S2-AC-008／S2-AC-015 | entity spawn 與來源 tie-break 的局部排序沒有共用 comparator | 固定 player→enemy、cell→ID 與 source category rank；canonical event/result golden 及 deterministic replay tests 通過 |

## 邊界確認

- `BattleSimulation`／`EffectResolver` 為純 `RefCounted` domain；runner 的 `SceneTree` 僅是 headless 執行入口。
- gameplay entropy 只來自 versioned PCG32 combat stream；沒有 Godot `rand*`。
- `RecordBattleResultCommand` 只提交 `battle_result_pending`；S2 未扣遠征 HP、未發收入／獎勵、未提交 proposal。
- `ShopService`、正式羈絆／裝備／遺物來源、完整遠征 soak 與最低規格 60 FPS 仍是明列 downstream。
- repository 未新增 Claude review report，也未執行 commit、push、merge 或發布。
