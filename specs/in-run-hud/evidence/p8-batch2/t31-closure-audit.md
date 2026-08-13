# in-run-hud T31 closure audit

日期：2026-08-13
接線前 baseline：`23c7666fdfaf80da5f35088da81c2f386bbe75d1`

## 結論

- 產品 finding：**0**。
- `IRH-REQ-001`～`IRH-REQ-017`：**PASS 17／PARTIAL 0／BLOCKED 0**。
- T31 的最後缺口 `IRH-REQ-007` dynamic summon 已由 pinned battle-rules template
  → session clone-out → lease-protected supply port → `RunCombatScreen` →
  `WorldBoardSummonAuthority` → `CombatWorldEventProjection` → production
  `WorldBoardRenderer` 單一路徑閉合。
- 正式內容目前沒有 summon effect，無法自然觸發實機截圖；依交付說明以 typed fixture
  驅動正式 renderer。缺模板、缺 sprite、非法模板或缺供給仍 fail closed，不虛構資料。

## 最後接線與 focused 證據

- `tests/unit/in_run_hud/test_world_board_summon_authority.gd`（Claude 契約測試，未修改）：
  5／5、78 assertions、exit 0。
- `tests/unit/in_run_hud/test_run_combat_screen_summon_authority_wiring.gd`：
  2／2、15 assertions、exit 0；驗證有權威可形成正式 renderer sprite body，以及供給
  缺席時維持 unrenderable。
- 原始 focused 摘錄：`t31-summon-renderer-focused.txt`。

## 17 項需求 evidence index

| Requirement | closure evidence |
|---|---|
| IRH-REQ-001 | 1920×1080 reference contract、layout metrics lexical gate、三尺寸 evidence |
| IRH-REQ-002 | UI 100／125／150 reflow token、九組矩陣、scale rebuild report |
| IRH-REQ-003 | 四 route 共用 `InRunHudShell` 與 route-local mount tests |
| IRH-REQ-004 | ESC overlay、settings port injection、focus trap、雙確認 tests |
| IRH-REQ-005 | combat pause capture/restore、settlement guard、canonical digest tests |
| IRH-REQ-006 | dedicated InputMap actions、input priority tests |
| IRH-REQ-007 | world projection／renderer／overlay tests＋summon authority 5/5＋screen renderer seam 2/2 |
| IRH-REQ-008 | board draft adapter、typed before→after preview、drag/button canonical equivalence |
| IRH-REQ-009 | component→component forge preview、exactly-once confirm、drag/button equivalence |
| IRH-REQ-010 | InputEvent-only buy→W deploy→equip→combat E2E、focus graph contract |
| IRH-REQ-011 | quote-owned economy HUD、five-tier odds、MAX、16 SHOP error mappings |
| IRH-REQ-012 | canonical shop offer cards、tier/star non-color cues、9 shop-tier images |
| IRH-REQ-013 | inactive/active trait authority、members/owned cue、safe-area popover tests |
| IRH-REQ-014 | prepare/combat typed inspector、authoritative sell quote、conditional confirmation |
| IRH-REQ-015 | deterministic progress states、localized accessibility copy、transition banner |
| IRH-REQ-016 | battle-source unit stats preview contract、board/bench clone-only tests |
| IRH-REQ-017 | fresh current-source All exit 0；345 scripts、1428/1428、38825 asserts；Spec 4092/0 |

逐項程式、測試與限制明細以
`specs/in-run-hud/evidence/p7-final/irh-requirements-manifest.md` 為正式台帳。

## 視覺矩陣 read-back

- `evidence-report.json`：`ok=true`、`exit_code=0`、146／146、`issues=[]`；SHA-256
  `6BB13FC1EAC9D8F429731C1A41C3CD508E4E3F7D52F00F00B7A36EDF1EBDC5D7`。
- `prepare`／`combat`／`map`／`reward` 各 9 cases，涵蓋 1280×720、1920×1080、
  2560×1440 × UI 100／125／150，共 36 張。
- 36 張逐檔 SHA-256 與 report 一致，PNG signature 與 IHDR 尺寸逐檔正確。
- 實圖 read-back 抽查每個 route 的最嚴苛 1280×720@150；必要操作與主要資訊區仍在安全畫面內。
- REWARD 九圖為使用者已接受的正式 screen typed `PendingRewardState.CHOOSING` fixture；
  非自然流程證據，限制持續明示於 `reward-evidence-source.json`。

## Fresh gate

- `-Suite All`：2026-08-13T09:02:43Z～09:18:57Z，exit 0。
- GUT：345 scripts、1428／1428 passing、38825 assertions、0 failures／errors／orphans。
- Spec：4092 cases、`passed=true`、`failures=[]`。
- tasks／manifest／PROGRESS 回填後另跑 `-Suite Spec`：4092 cases、0 failures、exit 0。
- 完整摘錄與 artifact hashes：`t31-all-suite-output.txt`。
