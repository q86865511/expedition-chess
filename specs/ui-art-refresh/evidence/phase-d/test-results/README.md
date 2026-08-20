# Phase D test results

| 驗證 | tests | assertions | exit |
|---|---:|---:|---:|
| All GUT | 1510 | 41532 | 0 |
| finalized copy | 3 | 576 | 0 |
| accessibility | 14 | 1458 | 0 |
| content reseal／loc parity | 16 | 2574 | 0 |
| localization static gate | 20 | 312 | 0 |
| settings locale | 7 | 451 | 0 |
| in-run HUD | 157 | 5870 | 0 |
| combat inspection | 2 | 74 | 0 |
| theme | 10 | 147 | 0 |
| Smoke | 10 cases | — | 0 |

`all-runner-execution.json` 的 fresh All 執行時間為
2026-08-20T12:29:29Z～2026-08-20T12:47:30Z。runner-contract 中刻意驗證 assertion、
engine error、zero tests、infrastructure error 與 timeout 的 fixture 會回傳預期非零碼；
這些是 All runner 自測案例，整體 suite 與其後的 Smoke、GUT、Content、Canonical、Combat、
Expedition、ActEliminationGate、Spec 都依契約通過，最外層 `exit_code=0`。
