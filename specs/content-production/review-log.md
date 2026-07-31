# G2 content-production — SDD review log

> Gate：SDD｜最多三輪｜reviewer唯讀

## Round 1 — 2026-07-31

| Reviewer | Verdict | Blocker | Major |
|---|---:|---:|---:|
| architecture / data safety | NOT APPROVED | 3 | 3 |
| content / behavior / assets | NOT APPROVED | 0 | 8 |

### Decision table

| Finding（去重） | Severity | Decision | Spec change |
|---|---|---|---|
| Codec 3無唯一canonical schema | Blocker | ADOPT | design §1加入tuple、magic、resource schema、全部field/kind/list-set與dispatch |
| Schema 4 wire未decision-complete | Blocker | ADOPT | design §6加入snapshot/resolution exact key、range、sequence/idempotence |
| CGM2/CGR2/allowlist/mapping未逐byte定義 | Blocker | ADOPT | design §6加入CME2/CMR2/CGM2/CGR2 preimage、traversal與fault matrix |
| stale confirmation typed chain不足 | Major | ADOPT | design §5加入snapshot/intent/command exact fields、digest與named errors |
| choice receipt及拆解服務state machine缺失 | Major | ADOPT | requirements R4、design §5加入receipt與三種outcome/exit語意 |
| localization fail-closed boot contract缺失 | Major | ADOPT | design §4加入typed loader result/error與emergency邊界 |
| Unit→ability→effect graph可能重複套用 | Major | ADOPT | requirements R2、design §3鎖唯一cast graph與validator mutation |
| 5×5 source無法產240 frames | Major | ADOPT | requirements R8、design §7定義每action格內四向與star衍生 |
| asset/audio validator無exact門檻 | Major | ADOPT | requirements R9、design §7加入格式、尺寸、品質、bus與schema門檻 |
| originality/adoption無人工gate | Major | ADOPT | requirements R10、tasks T18A加入獨立adoption review |
| REQ-CONTENT-001/Boss phase無owner | Major | ADOPT | requirements R3、tasks T12/T24與traceability補owner |
| 18 AC摘要弱化原Given/When/Then | Major | ADOPT | requirements R13改為上游原文三欄 |
| final/逐wave regression不足 | Minor/Major | ADOPT | tasks T26與Wave checkpoint列全suite、artifact/hash/read-back |
| fallback/locale tooltip漂移 | Minor | ADOPT | design §4加入同源parity與locale_generation rebuild |

Round 1沒有reviewer衝突、public contract外擴或產品範圍擴張；以上均屬既核可
需求的decision-completeness修正。修訂後送Round 2。

## Round 2 — 2026-07-31

| Reviewer | Verdict | Blocker | Major |
|---|---:|---:|---:|
| architecture / data safety | NOT APPROVED | 2 | 1 |
| content / behavior / assets | NOT APPROVED | 0 | 4 |

| Finding（去重） | Severity | Decision | Spec change |
|---|---|---|---|
| Choice receipt沒有唯一持久化owner/NCR1不exact | Blocker | ADOPT | design §5/§6加入run ledger、ack command、exact wire/preimage/retention |
| CGM2 enums/absent target/L10N2/golden仍不唯一 | Blocker | ADOPT | design §6加入ordinals、conditional bytes、L10N2與完整golden hex |
| Localization request/construction可TOCTOU或繞過 | Major | ADOPT | design §4加入immutable bytes+digest request與sealed factories |
| Rest dismantle誤沿用耗材command | Major | ADOPT | design §5加入service-authorized free dismantle command |
| Multi-phase Boss只有red owner | Major | ADOPT | tasks T13加入authoring/preview/effect-order green責任 |
| Asset reject無retry且reviewer寫狀態 | Major | ADOPT | R10/design §7/tasks T18/T18A分離attempt ledger、唯讀decision、retry與adopted inventory |

Round 2仍無reviewer衝突或範圍擴張。修訂後送最終Round 3；若仍有Blocker/Major，
依gate規則停止，不進Wave 1。

## Round 3 — 2026-07-31

| Reviewer | Verdict | Blocker | Major |
|---|---:|---:|---:|
| architecture / data safety | APPROVED | 0 | 0 |
| content / behavior / assets | APPROVED | 0 | 0 |

兩位reviewer均完成最終read-back；架構reviewer另獨立重算CME2、L10N2、CGM2、
CGR2 golden SHA-256並一致。SDD gate關閉，可進Wave 1。
