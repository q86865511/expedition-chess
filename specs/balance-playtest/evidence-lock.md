# G2 balance-playtest — Phase 0 3k screening #2 證據鎖定（evidence-lock）

> 建立於 2026-08-04，因應 Phase 0 收尾雙審（reviewer A／B）F04／B-01 findings。
> 目的：3k screening #2 的 gate 證據無法由本分支任一 commit 重算（見下方「已知限制」），
> 改以本檔記錄的 SHA-256 值作為證據鏈的鎖定點。以下雜湊值全數以
> `Get-FileHash -Algorithm SHA256` 在本機工作樹現場實算（2026-08-04），未抄用任何
> 先前簡報或 artifact 內嵌數字。

## 一、關鍵證據 SHA-256 清單

| 檔案 | SHA-256（大寫十六進位，`Get-FileHash` 原生輸出） |
|---|---|
| `artifacts/test/balance-playtest-screening.json` | `810D36A31F756F500307DE26F7EDE36F2E0C21290767121A7AEF9F0E665F3717` |
| `artifacts/test/balance-screening-source-freeze.json` | `D7D03FCB0892CAF2521012D6E2533B01978E6C8B9F6487F537F56B6275194280` |
| `artifacts/test/balance-screening-shard-00.json` | `2E96D0597CC9522FFACF2D9DA9DADF1F2C00EA8AEC85B6D1E750B880C02DC771` |
| `artifacts/test/balance-screening-shard-01.json` | `8157CA7A1153C9284A15B31770BEE39D35695B32BC2066BAA0C938B2A19FE8CD` |
| `artifacts/test/balance-screening-shard-02.json` | `5FF3381A9C66665624E8317787F361887A7BDB391072AFFD934D1AE416E9A09C` |
| `artifacts/test/balance-screening-shard-03.json` | `6BE7644A60E6C7485BABC6C0F81CD289F2002A04F80BC889A78877F3BD015069` |
| `artifacts/test/balance-screening-shard-04.json` | `6559A41F1A15C2E9CD59491117ABD0291A3A767918A96A5B3EB041F5F971EBC0` |
| `artifacts/test/balance-screening-shard-05.json` | `9379AC7B6F6528809B5538C168E0D7214B90BD118E8BBE381BFE14467CABCDF1` |
| `artifacts/test/balance-screening-shard-06.json` | `12503CB25AFD30E413766C135C173E7551115C7B8E1B05A6F7CEF457073B5563` |
| `artifacts/test/balance-screening-shard-07.json` | `4FEBE1917E2875AE1D750B739012D2BCAEE2345468722883EB19C71CE2D09015` |
| `artifacts/test/balance-screening-shard-08.json` | `3F91C0AFE902F1ABA5E5D737DA446CFE8E45548FAC281EB0ABAB6DA758ECFA2C` |
| `artifacts/test/balance-screening-shard-09.json` | `BB9C26D672CD315E9D576E8E0DFA2E302BEA9559067D3732888B76F7973C3D80` |
| `artifacts/test/balance-screening-shard-10.json` | `75CD4B1BB590894709C6E7D48163F5A9FC5BE9C6717BD135398FD2289E05B576` |
| `artifacts/test/balance-screening-shard-11.json` | `9EDC697936B7200E7F76524DF549D6AC4C84CA75023ABDEDEA4F43AE4D592909` |

重算指令：`Get-FileHash <path> -Algorithm SHA256`（PowerShell 內建，無外部依賴）。

## 二、gate 摘要（自 `balance-playtest-screening.json` 現場讀值）

- `candidate_id`：`balance.g2.7d47fada8091`
- `tune_digest`：`7d47fada8091a79a68a2c50a4d63c5d57e0752d0bac7776b30230717a6f8dea4`
- `manifest_digest`：`923c6c11fddc0d1684f1f1f0da92a0990a922aef7ef1a2a30c93a92f90a00a60`
- `source_freeze_digest`：`5982d579a02d7efe06318aa6135305db827b660255b1e38ccc7b57c070220758`
- `git_head`（frozen 時的工作樹 HEAD 記錄，非 clean commit——見下方限制 (a)）：
  `bf818fb36e3ff5badde3e8d1615f6d21b81cc653`
- `gate_mode`：`screening`；`gate`：`PASS`；`gate_reasons`：`[]`（空陣列）
- 三策略終局統計（`strategies[]`，各 1,000 cases，1,000/1,000 terminal）：
  - `tempo`：wins `662`
  - `economy`：wins `1000`
  - `synergy`：wins `554`
- Build 選用 dominance（`BALANCE_BUILD_SELECTION_DOMINANCE` 判準：
  `domain/balance/balance_bot_report.gd:346-360` 最高選用率與次高選用率之差）：
  `trait_faction_verdant` 41.43%（selected 1243/3000）減 `trait_faction_frost` 25.66%
  （selected 770/3000）＝ 15.77 個百分點（四捨五入 15.8pp），低於 `DOMINANCE_BPS`
  （20.00pp）門檻，未觸發 `BALANCE_BUILD_SELECTION_DOMINANCE`。
- Replay 等價：`replay_validation.sampled_case_count = 150`、
  `replay_validation.drift_case_ids = []`（150/150 零 drift）。
- `failed_seeds`：`[]`（空陣列，0 failure）。

## 三、已知限制

1. **3k screening #2 產生於 dirty 工作樹**：`source-manifest.json`（final All／RC 用）
   的 `git_commit` 是 `6b072f8`，但本次 3k screening 的 `balance-screening-source-freeze.json`
   記錄 `git_head` 為 `bf818fb`（即 `master` 分支頂端，非本分支任何一個 commit）。
   Reviewer A（F04）逐檔比對 freeze 清單（4,216 檔）與其審查時的工作樹，發現 24 檔
   內容不同、2 檔已不存在，其中含 runtime 相關檔案（`app/app_root.gd`、
   `domain/run/run_state_validator.gd` 等）。因此 `source_freeze_digest`
   （`5982d579…0758`）**無法從本分支任何一個 commit checkout 後重算得出**——它只綁定
   「3k screening #2 執行當下的磁碟狀態」，不是可重現的原始碼快照。本檔的 SHA-256
   清單就是承認這一點之後的替代鎖定手段：不主張「可由 commit 重建」，只主張
   「這些位元組現在確實是這些雜湊值」。
2. **原始 54MB screening artifact 與 12 個 shard json 不入版控**：`.gitignore:23` 排除
   `artifacts/test/*`。體積與產出頻率不適合版控；一旦本機工作樹被清空，這些檔案即
   永久不可由 repo 重新取得，只能靠本檔記錄的雜湊與摘要值追溯內容，無法覆核原始
   byte-level 資料。
3. **Phase 2 將於乾淨 HEAD 重建基線**：依 `rewrite-plan.md` 附錄 D，10k/30k
   full balance cohort 延後至 Phase 2 執行；屆時應在乾淨（non-dirty）工作樹上重新
   `source-freeze`，产出可被目前分支任一 commit 重算的 digest，取代本檔鎖定的
   dirty-tree 快照。
4. **後續 driver 修正會改變未來 replay digest**：`application/balance/balance_production_case_driver.gd`
   的 `world_digest` 寫入順序等問題（見 reviewer B 的 B-06 finding）若在後續任務修正，
   將改變之後所有 cohort 的 `canonical_replay_digest`／`replay_validation` 內部雜湊。
   本檔第二節記錄的 `canonical_replay_digest`（`98a6916a4a790581a054e57af4bf2f7f16884b746888610ad83893291cbaa968`，
   見 `balance-playtest-screening.json`）僅對 3k screening #2 這一份被凍結的版本有效，
   不代表修正後的 driver 會重現相同 digest；未來重跑不應以此值作為回歸基準。
5. **BP-SI-007 修復改變同 seed 戰局結果（2026-08-04 追記）**：8 個 RNG 池排序點由
   interned 指標序改為字典序（`StableNameSort`，使用者授權之 domain 修正，見
   `spec-issues.md` BP-SI-007）。這不只改 digest——同 seed 的地圖佈局、商店 offer、
   戰局勝負自此與 3k #2 不同。**3k #2 的所有統計數字（勝率、dominance、資源曲線）
   不得作為修復後版本的回歸對照組**；其 gate PASS 僅證明「該凍結版本通過 screening
   判準與儀器有效性檢驗」。Phase 2 基線以修復後的乾淨 HEAD 重建。
