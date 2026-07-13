# 實作切片計劃 (Implementation Slices)

> 架構規格 → 功能切片 → specs 三件套 → `/pipeline` 的**銜接橋樑**。
> 本文件只做規劃,不含實作;規則的單一事實來源仍是 `game-architecture/`。

## 目的

`game-architecture/` 是整份遊戲藍圖(74 個 REQ、一份大規格)。specs 三件套(`requirements`/`design`/`tasks`)是**功能級**的,一次只規格化並實作一個功能。本文件把 74 個 REQ 切成幾個**可獨立實作、可獨立驗收**的功能切片,並定義每片如何走三件套與 `/pipeline`,作為架構規格與實作之間的橋樑。

## 切片藍圖

切片名為 kebab-case,即未來 `specs/<切片名>/` 的目錄名。REQ 前綴對齊來自 §14 追溯矩陣。

| 切片 | 目錄名 | 範圍(§ 對應) | 對齊 REQ 前綴（數量） | 獨立驗收載體(§11) |
|---|---|---|---|---|
| **S1 決定論地基** | `foundation-core` | common/Stable ID、RngService 具名流、ContentRegistry 編譯快照、SaveService、AppRoot/RunSession、RunController copy-validate-save-swap(§8、§9) | TECH(6)、DATA(8)、RNG(2)、SAVE(6)、CONTENT(1) = 23 | `rng_stream_isolation`、存檔原子/遷移 fixture |
| **S2 最小戰鬥閉環** | `combat-core` | 棋盤 5.1、人口 5.2、棋子升星 5.3、敵情 5.5、自動戰鬥 5.6、時限/結果 5.7、遭遇 5.13、效果解析 §8.10 | BOARD(4)、UNIT(2)、COMBAT(6)、ENEMY(2)、EFFECT(2) = 16 | `merge_and_pool`、`simultaneous_death`、`path_tie` |
| **S3 經濟與遠征結算** | `economy-expedition` | 商店經濟 5.9、遠征 HP/戰敗 5.8、戰後三選一 5.12、核心循環 §4 | RUN(5)、ECON(4)、REWARD(2) = 11 | `economy_basic`、`boss_retry` |
| **S4 構築增量** | `build-systems` | 羈絆 5.4、裝備鍛造 5.10、遺物 5.11 | TRAIT(2)、ITEM(2)、RELIC(1) = 5 | `trait_snapshot`、`item_binding` |
| **S5 局外成長** | `meta-progression` | 營地/指揮官/解鎖 第7章 | META(4) = 4 | 營地存檔 + 對應 AC 子集 |
| *(橫切,不單獨成片)* | — | 產品定位/範圍 §2-3、UI 呈現 §10、測試 §11 隨各片增量 | PROD(4)、SCOPE(2)、UX(5)、QA(4) = 15 | 各片帶自己的 fixture + AC 子集 |

合計 23+16+11+5+4+15 = 74 REQ,與 §14 追溯矩陣一對一。

備註:核心循環 RUN(§4 流程編排)歸 S3;RunController 的交易管線(§8 TECH)是 S1 地基,兩者不同。CONTENT(內容驗證器)歸 S1 的 ContentRegistry 編譯期驗證。

## 對應 G0/G1/G2 門檻(§3.2)

- **G0 灰盒核心** ≈ S1 + S2 + S3 + S4 精簡版 + 1 Boss,固定種子可重現、兩種構築擊敗 Boss。
- **G1 全系統切片** ≈ 再加 S5、完整 S4、3 幕與存檔/局外解鎖。
- **G2 內容完整** = 32 完整美術 + 全 UI + 全內容,通過所有 AC 與外部複檢。

## 建議實作順序

`foundation-core → combat-core → economy-expedition → build-systems → meta-progression`。

理由:S1 是所有系統的依賴地基且風險最高(決定論、canonical hash、交易管線),先鎖死;S2+S3 合起來即可玩通一局遠征(達 G0 骨架);S4 深化構築;S5 補局外。UX/QA 橫切隨各片增量,不獨立成片。

## 每片如何走 specs 三件套(銜接流程)

決定實作某片 `<切片名>` 時:

1. 進 plan mode,啟動 spec 流程(`/spec` 或自然語言)。
2. **澄清**:AskUserQuestion 一次問完該片的核心情境、範圍邊界與明確不做、關鍵邊界情況、非功能約束。
3. 依模板逐段起草,每段 AskUserQuestion 停點核可:
   - `requirements` — EARS 需求 + 可測驗收,**直接引用** `game-architecture/` 對應 REQ 為權威來源,只補「這一片實作到什麼程度、驗收標準」,不重述規則。
   - `design` — 技術設計 + 需求對應表(覆蓋該片每條需求)。
   - `tasks` — HARD/NORMAL + 對應 R# + 驗收 + 依賴,雙向覆蓋檢查。
4. ExitPlanMode 總核可 → 落檔 `specs/<切片名>/{requirements,design,tasks}.md`,檔頭標 `狀態：已核可（日期）`。
5. 建議以 Codex `/spec-review` 對三件套做第二審。
6. `/pipeline <切片名>` 執行實作與雙審;tasks 勾選由 pipeline 收尾回寫。

## 狀態

- S1 `foundation-core`：已完成；三件套位於 `specs/foundation-core/`，完整 headless gate 通過。
- S2 `combat-core`：下一個建議切片，尚未建立三件套或程式實作。
- S3–S5：維持規劃階段。
