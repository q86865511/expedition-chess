# G2 balance-playtest — Tasks

- [x] **T00 HARD**：鎖 requirements/design/tasks、ownership、AC-032 external 邊界。
- [x] **T01 HARD/TDD**：Candidate typed DTO、codec、完整 TUNE inventory 與 fixed-rule guard。
- [x] **T02 HARD/TDD**：Bot observation/action/strategy 與 stable deterministic selection。
- [x] **T03 HARD/TDD**：production full-expedition case driver、三幕 settlement 與 replay digest。
  已交付：`application/balance/balance_production_case_driver.gd`；3k screening #2 gate PASS
  （見 `specs/balance-playtest/evidence-lock.md`）。
- [x] **T04 NORMAL/TDD**：BalanceBotReport v1 聚合、20pp/sample/invariant gate。
- [x] **T05 HARD/TDD**：PlaytestSessionReport v1 codec、atomic local writer、AppRoot terminal hook。
- [x] **T06 NORMAL**：wrapper 新增 BalancePlaytest suite、3k screening 與 30k final artifacts。
- [x] **T07 HARD**：Windows provisional export preset、package script、offline/report smoke。
  已交付：`export_presets.cfg` provisional preset、`tools/balance/package-rc.ps1`、
  `artifacts/rc/rc-evidence.json` 三 phase smoke。
- [ ] **T08 HARD**：逐 AC fresh evidence、All、10k ExpeditionSoak、30k final、hash read-back。
  依 `specs/balance-playtest/rewrite-plan.md` 附錄 D（2026-08-04 使用者裁決）第 2 點：
  「tasks.md T08 的大樣本 final 項按本裁決記為『延後至 Phase 2』，不視為未完成」——
  10k/30k full balance cohort 延後至 Phase 2；3k screening #2 gate PASS 已於 Phase 0
  完成並收尾（見 `specs/balance-playtest/evidence-lock.md`），但 30k final 本身尚未
  執行，故本項狀態維持未勾選（依裁決不計為 blocker）。
- [ ] **T09 HARD**：兩份獨立 implementation review、finding closure 與文件回寫，停 Git gate。
  Phase 0 雙審（reviewer A／B）已執行，兩份皆 NOT APPROVED（各 10 條 findings）；
  使用者裁決全修＋證據鎖定，findings 修復中，詳見
  `specs/balance-playtest/implementation-review.md`。

依賴：T01→T02→T03→T04；T01→T05；T03/T04→T06；T05/T06→T07→T08→T09。
