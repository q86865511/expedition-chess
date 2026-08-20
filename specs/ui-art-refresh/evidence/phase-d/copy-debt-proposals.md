# Phase D 內容文案裁決與定稿

能力數值依 production content 與 domain 公式逐筆核對。本檔保留原提案表，並記錄
2026-08-20 最終裁決：faction 六項採 A、role 六項保留直譯、羈絆英文不變；44 個技能
描述整批核可並已寫回 catalog。44 個編號單位名確定進入正式命名，但本批不改現值，
下一批才依 faction／role／cost／戰鬥定位／視覺稿提出每單位兩候選。

RUN_COMBAT 單位詳情目前消費同單位的 `loc.effect_*_primary` display key，因此同一份已核可
中英文描述亦機械同步到這 44 個既有 alias；沒有新增 key，也沒有另寫第二套文案。

## 12 羈絆正式風味命名

| key | 現行 zh_TW | 現行 en | 候選 A | 候選 B |
|---|---|---|---|---|
| `loc.trait_faction_arcane` | 奧術 | Arcane | 秘法同調 | 奧能祕契 |
| `loc.trait_faction_ember` | 燼 | Ember | 餘燼之盟 | 燼火誓約 |
| `loc.trait_faction_frost` | 霜 | Frost | 凜霜之裔 | 霜痕盟約 |
| `loc.trait_faction_iron` | 鐵 | Iron | 鐵誓同盟 | 鋼鐵意志 |
| `loc.trait_faction_shadow` | 影 | Shadow | 暮影之裔 | 幽影盟約 |
| `loc.trait_faction_verdant` | 翠蔭 | Verdant | 翠蔭之盟 | 森息共鳴 |
| `loc.trait_role_marksman` | 神射手 | Marksman | 鷹眼射手 | 破陣神射 |
| `loc.trait_role_mystic` | 秘術師 | Mystic | 秘法導師 | 靈脈術士 |
| `loc.trait_role_sentinel` | 哨衛 | Sentinel | 守陣哨衛 | 戍衛者 |
| `loc.trait_role_trickster` | 詭術師 | Trickster | 幻謀術士 | 詭道行者 |
| `loc.trait_role_vanguard` | 先鋒 | Vanguard | 破陣先鋒 | 衝鋒衛 |
| `loc.trait_role_warden` | 守望者 | Warden | 誓約守望 | 護界者 |

裁決結果：前六列 faction 採 A；後六列 role 保留現行直譯；英文十二列全部維持現值。

## 44 單位技能描述

裁決結果：下列 44 組 zh_TW／en 全數核可並已落地。

實作依據：每個 `content/packs/vertical_slice/unit_effects/*.tres` 都是 `target = target`、`damage_type = physical`、`scaling = attack`；`domain/battle/effects/effect_resolver.gd::_append_battle_operation` 的實際公式是 `base + source.attack`。因此提案不宣稱百分比、範圍傷害或未實作的附加效果。

| description key | base | 提案 zh_TW | proposed en |
|---|---:|---|---|
| `loc.ability_slice_monster_00_description` | 32 | 對目前目標造成「自身攻擊力＋32」點物理傷害。 | Deals physical damage equal to this unit's Attack + 32 to the current target. |
| `loc.ability_slice_monster_01_description` | 35 | 對目前目標造成「自身攻擊力＋35」點物理傷害。 | Deals physical damage equal to this unit's Attack + 35 to the current target. |
| `loc.ability_slice_monster_02_description` | 38 | 對目前目標造成「自身攻擊力＋38」點物理傷害。 | Deals physical damage equal to this unit's Attack + 38 to the current target. |
| `loc.ability_slice_monster_03_description` | 41 | 對目前目標造成「自身攻擊力＋41」點物理傷害。 | Deals physical damage equal to this unit's Attack + 41 to the current target. |
| `loc.ability_slice_monster_04_description` | 44 | 對目前目標造成「自身攻擊力＋44」點物理傷害。 | Deals physical damage equal to this unit's Attack + 44 to the current target. |
| `loc.ability_slice_monster_05_description` | 47 | 對目前目標造成「自身攻擊力＋47」點物理傷害。 | Deals physical damage equal to this unit's Attack + 47 to the current target. |
| `loc.ability_slice_monster_06_description` | 50 | 對目前目標造成「自身攻擊力＋50」點物理傷害。 | Deals physical damage equal to this unit's Attack + 50 to the current target. |
| `loc.ability_slice_monster_07_description` | 53 | 對目前目標造成「自身攻擊力＋53」點物理傷害。 | Deals physical damage equal to this unit's Attack + 53 to the current target. |
| `loc.ability_slice_monster_08_description` | 56 | 對目前目標造成「自身攻擊力＋56」點物理傷害。 | Deals physical damage equal to this unit's Attack + 56 to the current target. |
| `loc.ability_slice_monster_09_description` | 59 | 對目前目標造成「自身攻擊力＋59」點物理傷害。 | Deals physical damage equal to this unit's Attack + 59 to the current target. |
| `loc.ability_slice_monster_10_description` | 62 | 對目前目標造成「自身攻擊力＋62」點物理傷害。 | Deals physical damage equal to this unit's Attack + 62 to the current target. |
| `loc.ability_slice_monster_11_description` | 65 | 對目前目標造成「自身攻擊力＋65」點物理傷害。 | Deals physical damage equal to this unit's Attack + 65 to the current target. |
| `loc.ability_slice_player_00_description` | 48 | 對目前目標造成「自身攻擊力＋48」點物理傷害。 | Deals physical damage equal to this unit's Attack + 48 to the current target. |
| `loc.ability_slice_player_01_description` | 50 | 對目前目標造成「自身攻擊力＋50」點物理傷害。 | Deals physical damage equal to this unit's Attack + 50 to the current target. |
| `loc.ability_slice_player_02_description` | 52 | 對目前目標造成「自身攻擊力＋52」點物理傷害。 | Deals physical damage equal to this unit's Attack + 52 to the current target. |
| `loc.ability_slice_player_03_description` | 54 | 對目前目標造成「自身攻擊力＋54」點物理傷害。 | Deals physical damage equal to this unit's Attack + 54 to the current target. |
| `loc.ability_slice_player_04_description` | 56 | 對目前目標造成「自身攻擊力＋56」點物理傷害。 | Deals physical damage equal to this unit's Attack + 56 to the current target. |
| `loc.ability_slice_player_05_description` | 58 | 對目前目標造成「自身攻擊力＋58」點物理傷害。 | Deals physical damage equal to this unit's Attack + 58 to the current target. |
| `loc.ability_slice_player_06_description` | 60 | 對目前目標造成「自身攻擊力＋60」點物理傷害。 | Deals physical damage equal to this unit's Attack + 60 to the current target. |
| `loc.ability_slice_player_07_description` | 62 | 對目前目標造成「自身攻擊力＋62」點物理傷害。 | Deals physical damage equal to this unit's Attack + 62 to the current target. |
| `loc.ability_slice_player_08_description` | 64 | 對目前目標造成「自身攻擊力＋64」點物理傷害。 | Deals physical damage equal to this unit's Attack + 64 to the current target. |
| `loc.ability_slice_player_09_description` | 66 | 對目前目標造成「自身攻擊力＋66」點物理傷害。 | Deals physical damage equal to this unit's Attack + 66 to the current target. |
| `loc.ability_slice_player_10_description` | 68 | 對目前目標造成「自身攻擊力＋68」點物理傷害。 | Deals physical damage equal to this unit's Attack + 68 to the current target. |
| `loc.ability_slice_player_11_description` | 70 | 對目前目標造成「自身攻擊力＋70」點物理傷害。 | Deals physical damage equal to this unit's Attack + 70 to the current target. |
| `loc.ability_slice_player_12_description` | 72 | 對目前目標造成「自身攻擊力＋72」點物理傷害。 | Deals physical damage equal to this unit's Attack + 72 to the current target. |
| `loc.ability_slice_player_13_description` | 74 | 對目前目標造成「自身攻擊力＋74」點物理傷害。 | Deals physical damage equal to this unit's Attack + 74 to the current target. |
| `loc.ability_slice_player_14_description` | 76 | 對目前目標造成「自身攻擊力＋76」點物理傷害。 | Deals physical damage equal to this unit's Attack + 76 to the current target. |
| `loc.ability_slice_player_15_description` | 78 | 對目前目標造成「自身攻擊力＋78」點物理傷害。 | Deals physical damage equal to this unit's Attack + 78 to the current target. |
| `loc.ability_slice_player_16_description` | 80 | 對目前目標造成「自身攻擊力＋80」點物理傷害。 | Deals physical damage equal to this unit's Attack + 80 to the current target. |
| `loc.ability_slice_player_17_description` | 82 | 對目前目標造成「自身攻擊力＋82」點物理傷害。 | Deals physical damage equal to this unit's Attack + 82 to the current target. |
| `loc.ability_slice_player_18_description` | 84 | 對目前目標造成「自身攻擊力＋84」點物理傷害。 | Deals physical damage equal to this unit's Attack + 84 to the current target. |
| `loc.ability_slice_player_19_description` | 86 | 對目前目標造成「自身攻擊力＋86」點物理傷害。 | Deals physical damage equal to this unit's Attack + 86 to the current target. |
| `loc.ability_slice_player_20_description` | 88 | 對目前目標造成「自身攻擊力＋88」點物理傷害。 | Deals physical damage equal to this unit's Attack + 88 to the current target. |
| `loc.ability_slice_player_21_description` | 90 | 對目前目標造成「自身攻擊力＋90」點物理傷害。 | Deals physical damage equal to this unit's Attack + 90 to the current target. |
| `loc.ability_slice_player_22_description` | 92 | 對目前目標造成「自身攻擊力＋92」點物理傷害。 | Deals physical damage equal to this unit's Attack + 92 to the current target. |
| `loc.ability_slice_player_23_description` | 94 | 對目前目標造成「自身攻擊力＋94」點物理傷害。 | Deals physical damage equal to this unit's Attack + 94 to the current target. |
| `loc.ability_slice_player_24_description` | 96 | 對目前目標造成「自身攻擊力＋96」點物理傷害。 | Deals physical damage equal to this unit's Attack + 96 to the current target. |
| `loc.ability_slice_player_25_description` | 98 | 對目前目標造成「自身攻擊力＋98」點物理傷害。 | Deals physical damage equal to this unit's Attack + 98 to the current target. |
| `loc.ability_slice_player_26_description` | 100 | 對目前目標造成「自身攻擊力＋100」點物理傷害。 | Deals physical damage equal to this unit's Attack + 100 to the current target. |
| `loc.ability_slice_player_27_description` | 102 | 對目前目標造成「自身攻擊力＋102」點物理傷害。 | Deals physical damage equal to this unit's Attack + 102 to the current target. |
| `loc.ability_slice_player_28_description` | 104 | 對目前目標造成「自身攻擊力＋104」點物理傷害。 | Deals physical damage equal to this unit's Attack + 104 to the current target. |
| `loc.ability_slice_player_29_description` | 106 | 對目前目標造成「自身攻擊力＋106」點物理傷害。 | Deals physical damage equal to this unit's Attack + 106 to the current target. |
| `loc.ability_slice_player_30_description` | 108 | 對目前目標造成「自身攻擊力＋108」點物理傷害。 | Deals physical damage equal to this unit's Attack + 108 to the current target. |
| `loc.ability_slice_player_31_description` | 110 | 對目前目標造成「自身攻擊力＋110」點物理傷害。 | Deals physical damage equal to this unit's Attack + 110 to the current target. |

## 44 單位名稱：下一批提出候選

裁決為「進入正式命名」。下表保留裁決前盤點，44 個編號名本批仍維持現值；下一批依
單位 faction、role、cost、戰鬥定位與視覺稿各提兩個候選，未經下一次裁決不寫回 catalog。

| key | 現行 zh_TW | 現行 en | 本批狀態 |
|---|---|---|---|
| `loc.unit_slice_monster_00` | 怪物 01 | Monster 01 | 待決定是否命名 |
| `loc.unit_slice_monster_01` | 怪物 02 | Monster 02 | 待決定是否命名 |
| `loc.unit_slice_monster_02` | 怪物 03 | Monster 03 | 待決定是否命名 |
| `loc.unit_slice_monster_03` | 怪物 04 | Monster 04 | 待決定是否命名 |
| `loc.unit_slice_monster_04` | 怪物 05 | Monster 05 | 待決定是否命名 |
| `loc.unit_slice_monster_05` | 怪物 06 | Monster 06 | 待決定是否命名 |
| `loc.unit_slice_monster_06` | 怪物 07 | Monster 07 | 待決定是否命名 |
| `loc.unit_slice_monster_07` | 怪物 08 | Monster 08 | 待決定是否命名 |
| `loc.unit_slice_monster_08` | 怪物 09 | Monster 09 | 待決定是否命名 |
| `loc.unit_slice_monster_09` | 怪物 10 | Monster 10 | 待決定是否命名 |
| `loc.unit_slice_monster_10` | 怪物 11 | Monster 11 | 待決定是否命名 |
| `loc.unit_slice_monster_11` | 怪物 12 | Monster 12 | 待決定是否命名 |
| `loc.unit_slice_player_00` | 遠征棋士 01 | Expedition Unit 01 | 待決定是否命名 |
| `loc.unit_slice_player_01` | 遠征棋士 02 | Expedition Unit 02 | 待決定是否命名 |
| `loc.unit_slice_player_02` | 遠征棋士 03 | Expedition Unit 03 | 待決定是否命名 |
| `loc.unit_slice_player_03` | 遠征棋士 04 | Expedition Unit 04 | 待決定是否命名 |
| `loc.unit_slice_player_04` | 遠征棋士 05 | Expedition Unit 05 | 待決定是否命名 |
| `loc.unit_slice_player_05` | 遠征棋士 06 | Expedition Unit 06 | 待決定是否命名 |
| `loc.unit_slice_player_06` | 遠征棋士 07 | Expedition Unit 07 | 待決定是否命名 |
| `loc.unit_slice_player_07` | 遠征棋士 08 | Expedition Unit 08 | 待決定是否命名 |
| `loc.unit_slice_player_08` | 遠征棋士 09 | Expedition Unit 09 | 待決定是否命名 |
| `loc.unit_slice_player_09` | 遠征棋士 10 | Expedition Unit 10 | 待決定是否命名 |
| `loc.unit_slice_player_10` | 遠征棋士 11 | Expedition Unit 11 | 待決定是否命名 |
| `loc.unit_slice_player_11` | 遠征棋士 12 | Expedition Unit 12 | 待決定是否命名 |
| `loc.unit_slice_player_12` | 遠征棋士 13 | Expedition Unit 13 | 待決定是否命名 |
| `loc.unit_slice_player_13` | 遠征棋士 14 | Expedition Unit 14 | 待決定是否命名 |
| `loc.unit_slice_player_14` | 遠征棋士 15 | Expedition Unit 15 | 待決定是否命名 |
| `loc.unit_slice_player_15` | 遠征棋士 16 | Expedition Unit 16 | 待決定是否命名 |
| `loc.unit_slice_player_16` | 遠征棋士 17 | Expedition Unit 17 | 待決定是否命名 |
| `loc.unit_slice_player_17` | 遠征棋士 18 | Expedition Unit 18 | 待決定是否命名 |
| `loc.unit_slice_player_18` | 遠征棋士 19 | Expedition Unit 19 | 待決定是否命名 |
| `loc.unit_slice_player_19` | 遠征棋士 20 | Expedition Unit 20 | 待決定是否命名 |
| `loc.unit_slice_player_20` | 遠征棋士 21 | Expedition Unit 21 | 待決定是否命名 |
| `loc.unit_slice_player_21` | 遠征棋士 22 | Expedition Unit 22 | 待決定是否命名 |
| `loc.unit_slice_player_22` | 遠征棋士 23 | Expedition Unit 23 | 待決定是否命名 |
| `loc.unit_slice_player_23` | 遠征棋士 24 | Expedition Unit 24 | 待決定是否命名 |
| `loc.unit_slice_player_24` | 遠征棋士 25 | Expedition Unit 25 | 待決定是否命名 |
| `loc.unit_slice_player_25` | 遠征棋士 26 | Expedition Unit 26 | 待決定是否命名 |
| `loc.unit_slice_player_26` | 遠征棋士 27 | Expedition Unit 27 | 待決定是否命名 |
| `loc.unit_slice_player_27` | 遠征棋士 28 | Expedition Unit 28 | 待決定是否命名 |
| `loc.unit_slice_player_28` | 遠征棋士 29 | Expedition Unit 29 | 待決定是否命名 |
| `loc.unit_slice_player_29` | 遠征棋士 30 | Expedition Unit 30 | 待決定是否命名 |
| `loc.unit_slice_player_30` | 遠征棋士 31 | Expedition Unit 31 | 待決定是否命名 |
| `loc.unit_slice_player_31` | 遠征棋士 32 | Expedition Unit 32 | 待決定是否命名 |
