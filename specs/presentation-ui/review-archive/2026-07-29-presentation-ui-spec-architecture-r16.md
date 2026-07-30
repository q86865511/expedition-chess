# R16 Architecture／Data Safety Implementation Review

Date: 2026-07-29
Verdict: `NOT APPROVED`
Unresolved: `2 High / 1 Medium`
Mode: fresh read-only reviewer；未修改檔案、未執行 Godot、未做 Git。

## G2-R16-A01 — High

Public split `ResultsFallbackNavigationPort.prepare_retry()`／`retry()` 仍可在
AppRoot guard 外發出 repository authority；production 雖改走 atomic
`retry_installed()`，舊 public surface 仍可被直接 root reentry 繞過。

- Anchors: `presentation/screens/results_fallback_navigation_port.gd:63-154`
- Fix: 移除／私有化 split API，只保留 root-owned atomic retry。
- Evidence: authority issue、CAS、repository release、candidate bind、route
  commit/failure 各 barrier 直接注入 AppRoot Camp/Menu/sibling retry。

## G2-R16-A02 — High

`WorldViewport` 目前沒有 production world child；formal routes 全掛在 UI
CanvasLayer。mapper 又把 UI scale 當整棵 canvas scale，與真 Canvas transform
不一致；現有 forward/inverse round-trip 不是實際 target hit-test。

- Anchors: `app/main.tscn:11-44`,
  `presentation/viewport/production_viewport_coordinator.gd:73-114`,
  `presentation/viewport/window_coordinate_mapper.gd:68-85`
- Fix: 真 world host/targets 掛入 SubViewport；mapper 對齊 live transform，
  UI hit 使用真 Control global transform。
- Evidence: 同一 AppRoot resize 五尺寸，真 framebuffer、tile/hotspot/control
  input event 與 target receiver。

## G2-R16-A03 — Medium

production combat inspection 沒填 `equipment_ids`，target 只在 enemy list
解析；跨陣營 target 會變 0。現有 spy DTO test 繞過真 session。

- Anchors: `presentation/run/run_presentation_session.gd:260-325`
- Fix: 從 clone-only committed combat projection完整建立雙方 identity、target、
  equipment/traits/statuses。
- Evidence: 真 session＋真 inspection port，驗六欄、clone isolation、
  zero dispatch、stale lease。

## Confirmed closed

- terminal durable save 後真 lease/session/writer revoke 與 application-local
  RESULTS seal 已落地。
- SaveRepository/settings single-flight 未發現新缺口。
- 39 manifests、151/151 references、134 unique paths均一致。
- runtime shutdown verbose 沒有 leaked Node/Control/Viewport，因此 stderr
  非空本身不列 finding。
