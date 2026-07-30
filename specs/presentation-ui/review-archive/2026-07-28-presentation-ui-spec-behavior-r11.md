# G2 presentation-ui Spec Review — Behavior R11

> Date: 2026-07-28
> Role: fresh read-only Codex reviewer
> Verdict: `NOT APPROVED — 2 unresolved findings`

## Findings

| ID | Severity | file:line | Failure scenario | Proposed fix |
|---|---|---|---|---|
| `G2-R11-B01` | Medium | `specs/presentation-ui/tasks.md:127,135,189,237` | T08 在 wave3 被要求完成 settings coordinator 呼叫、locale 重啟 round-trip、四 bus round-trip；但 concrete `SettingsApplicationCoordinator` 到依賴 T08 的 T12 才實作。依逐任務 red→green 規則，T08 不是無法轉綠，就是必須越權提前修改 T12 ownership，造成 wave／manifest 契約衝突。 | 將 T08 明確限定為注入式 settings UI component：只驗 draft、typed submit、錯誤顯示與焦點，使用 fake typed port。把 concrete coordinator、locale restart、四 bus/runtime apply 與 production wiring 全歸 T12；在 design test matrix 標出 component 與 integration evidence 的不同 owner。或調整依賴順序，使 concrete coordinator 先於 T08。 |
| `G2-R11-B02` | Medium | `specs/presentation-ui/requirements.md:70`; `specs/presentation-ui/design.md:735,780`; `specs/presentation-ui/tasks.md:87,137` | AC-070／R3 要求 decoded、opaque recovery 的取消、錯 token、run replacement、archive/save fault 都保留 byte-identical committed copy；目前 named matrix 只清楚鎖 crash residue，T08 只寫 recovery confirm。若 UI cancel 誤送 discard，或 wrong token 路徑先 archive/clear，既有具名測試仍可能全綠。 | 新增或擴充 named behavioral test，逐一覆蓋 decoded／opaque 的 cancel、wrong/stale/replaced token、archive fault、save fault；斷言零 clear、profile 不變、至少一份 committed copy 存活及重啟可恢復。明列 T06 repository/root owner 與 T08 confirmation UI component evidence。 |

## Coverage checklist

- R10 CLI ownership split：T01 bootstrap component、T04 facade/wrapper component、T05 allowlist
  parse/route/bind/integrated smoke，時序清楚。
- R10 Exit ownership split：T05 root signal/API/pending behavior；T08 button/production-host/
  fake-host smoke，無 AppRoot ownership 衝突。
- R9-B01 Exit lifecycle、R9-B02 `ABANDON_BOSS_RETRY` confirmation matrix、R9-B03
  `--combat-lab` production bootstrap/facade reuse 均已回寫。
- R1～R14 與 T00～T15 雙向追溯集合完整；例外是上述 settings wave 可執行性。
- 19 條 owning AC 數量、唯一列與 task mapping 正確；AC-070 fresh named evidence 有上述缺口。
- 其餘 boot/menu/start/continue、scene lease、RESULTS fallback、六組 results-action barrier、
  playback/backpressure、viewport/input、localization、accessibility 及 pre/post-commit failure
  未發現新的未決問題。

## Review limitation

指定的 `prompts/spec-review.md` 在 worktree、repo root 與使用者 `.claude` 目錄均不存在；本輪
依其餘指定 SDD、review-log、roadmap 與專案 review contract 執行。
