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

---

# T25 Implementation Review(實作雙審)

## Round 1 — 2026-07-31(Claude reviewer)

3 High/6 Major/5 Low:H1 dismantle 出口 shop leak、H2 dismantle/exit 命令缺件、
H3 bootstrap fail-open、M1 exact payload/11 拒絕碼缺、M2 世代守衛缺、M3 ack 語意、
M4 nonce 可重現、M5 payload arity 放寬、M6 fail-closed 存疑、L1-L5。
原文:`.pipeline/content-production/reviews/t25-round1-claude-reviewer.md`。

## Round 2 — 2026-07-31/08-01(Claude + codex 第二意見)

- Claude:R1 的 H/M 全 CLOSED;新發現 N1(ack 可達性)/N2(result 顯示)/
  N3(catalog 未驅動 UI 文案+seal)/N4(誤導 field_path),L2 升建議修。
- codex:REQUEST_CHANGES — B1 NCR1↔transaction 未綁定、B2 node service
  resolution 未綁定+誤收 reward kind、B3 production 未接 codec2→3 migration
  port、B4 allowlist 隱含 identity/未遍歷引用面;Maj5 acceptance 誠實語意。
原文:`.pipeline/content-production/reviews/t25-round2-claude-reviewer.md`。

## Round 3 — 2026-08-01(closure)

| Reviewer | Verdict | 摘要 |
|---|---|---|
| Claude | APPROVED | B1-B4/N1-N4/L2/Maj5 全 CLOSED;L4 PARTIAL(建議項);R3-1~4 低度建議 |
| codex | B1/B2/B3 CLOSED;B4 NOT_CLOSED→由 886395b 關閉 | mapping「套用」語意:ALIAS 改寫全引用面、TOMBSTONE 移除、ledger-bound fail-closed;兩個繞過構造轉正向測試 |

議決記錄項(非必修,詳 PROGRESS.md 2026-08-01 決策):M6/L3/L5/N5/N6/R3-3/
emergency catalog 全量 keys/map payload digest 不重算。
Blocked(非審查缺陷,屬 T18A/資產 gate):AC-033、AC-038、REQ-PROD-001、
REQ-SCOPE-002,見 content-production-acceptance.json 的 blocked_row_ids。
最終證據:全 Gut 281 scripts/1091 tests 全綠、10k ExpeditionSoak exit 0、
-Suite All exit 0(acceptance verified=true、fully_closed=false)。
原文:`.pipeline/content-production/reviews/t25-round3-claude-reviewer.md`。
