# G2 balance-playtest — Tasks

- [x] **T00 HARD**：鎖 requirements/design/tasks、ownership、AC-032 external 邊界。
- [x] **T01 HARD/TDD**：Candidate typed DTO、codec、完整 TUNE inventory 與 fixed-rule guard。
- [x] **T02 HARD/TDD**：Bot observation/action/strategy 與 stable deterministic selection。
- [ ] **T03 HARD/TDD**：production full-expedition case driver、三幕 settlement 與 replay digest。
- [x] **T04 NORMAL/TDD**：BalanceBotReport v1 聚合、20pp/sample/invariant gate。
- [x] **T05 HARD/TDD**：PlaytestSessionReport v1 codec、atomic local writer、AppRoot terminal hook。
- [x] **T06 NORMAL**：wrapper 新增 BalancePlaytest suite、3k screening 與 30k final artifacts。
- [ ] **T07 HARD**：Windows provisional export preset、package script、offline/report smoke。
- [ ] **T08 HARD**：逐 AC fresh evidence、All、10k ExpeditionSoak、30k final、hash read-back。
- [ ] **T09 HARD**：兩份獨立 implementation review、finding closure 與文件回寫，停 Git gate。

依賴：T01→T02→T03→T04；T01→T05；T03/T04→T06；T05/T06→T07→T08→T09。
