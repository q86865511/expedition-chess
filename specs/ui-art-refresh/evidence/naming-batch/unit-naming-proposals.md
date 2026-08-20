# 44 單位正式風味命名候選

> 狀態：純提案，等待使用者逐列裁決；本批不寫回 `localization/catalog.v2.csv`。
>
> 依據：`content/packs/vertical_slice/units/*.tres` 的 trait、cost 與攻擊型態，
> `content/packs/vertical_slice/encounters/*.tres` 的遭遇身分，以及
> `assets/production/provenance/*.json` 與 adopted portrait／source sheet 的實際外觀。
> 候選 1 偏重外觀與職能辨識，候選 2 偏重陣營語感與幻想風味；兩者同等有效，未預選勝者。

## 命名提案

| key | faction/role/cost | 現行名 | 候選1(zh/en) | 候選2(zh/en) | 一句命名理由 |
|---|---|---|---|---|---|
| `loc.unit_slice_monster_00` | 無陣營／近戰／非商店 | 怪物 01／Monster 01 | 根牙野豬／Roottusk Boar | 苔木獠獸／Mosswood Tusker | 木根獠豬的近戰輪廓對應根牙與苔木語彙，且普通遭遇與第一幕 Boss 隨從定位保留基礎威脅感。 |
| `loc.unit_slice_monster_01` | 無陣營／遠程／非商店 | 怪物 02／Monster 02 | 瓶花蟹／Pitcher Crab | 噴籽鉗獸／Seedspitter | 瓶狀食蟲花背甲與噴籽巨鉗直接支撐兩名，並兼顧普通、精英及第一幕 Boss 隨從的遠程威脅。 |
| `loc.unit_slice_monster_02` | 無陣營／術式遠程／非商店 | 怪物 03／Monster 03 | 稜光母體／Prism Matriarch | 裂輝晶母／Riftglass Monarch | 浮空稜晶水母與內旋光核需要異形而非人名，母體與晶母的份量也符合第一幕主 Boss 身分。 |
| `loc.unit_slice_monster_03` | 無陣營／近戰／非商店 | 怪物 04／Monster 04 | 熔甲巨獸／Lavashell Brute | 地火磐獸／Magma Bastion | 熔岩縫隙、玄武岩甲殼與近戰巨爪共同形成沉重壓迫感，對應二星的第二幕主 Boss。 |
| `loc.unit_slice_monster_04` | 無陣營／遠程／非商店 | 怪物 05／Monster 05 | 冰冠梟皇／Icequill Sovereign | 凜翼災梟／Frostwing Calamity | 冰晶冠羽與發射羽針的梟獸外形支撐冰翼語彙，皇與災的稱號則給足第三幕主 Boss 份量。 |
| `loc.unit_slice_monster_05` | 無陣營／術式遠程／非商店 | 怪物 06／Monster 06 | 闇燭蛞蝓／Gloomwax Slug | 淵蠟爬獸／Waxdeep Crawler | 黑液蛞蝓、背燭與紫焰獨眼形成詭異術式輪廓，名稱維持第三幕 Boss 隨從而非主體的威脅層級。 |
| `loc.unit_slice_monster_06` | 無陣營／近戰／非商店 | 怪物 07／Monster 07 | 廢鐵爐甲／Scrapfurnace Beetle | 鉚殼火蟲／Rivetback Scarab | 鉚釘殼、爐口顎與活塞足把廢鐵甲蟲的近戰定位說清楚，也能承接精英與第二幕 Boss 隨從身分。 |
| `loc.unit_slice_monster_07` | 無陣營／遠程／非商店 | 怪物 08／Monster 08 | 弩臂螳螂／Boltarm Mantis | 赤棘獵蟲／Thornshot Stalker | 弩形前肢與紅尖棘刺是遠程辨識核心，獵蟲語感則補強精英及第二幕 Boss 隨從的追殺感。 |
| `loc.unit_slice_monster_08` | 無陣營／術式遠程／非商店 | 怪物 09／Monster 09 | 晶燈洞蛾／Lanternmoth | 礦翼明蛾／Orewing Moth | 洞蛾的礦塵翅與琥珀燈腹提供晶燈意象，術式遠程與第二幕 Boss 隨從定位亦不會被誤讀成人形。 |
| `loc.unit_slice_monster_09` | 無陣營／近戰／非商店 | 怪物 10／Monster 10 | 骨冠泥魁／Bonecrown Brute | 沼拳巨怪／Mirefist Ogre | 骨角冠、苔拳與泥沼身軀突出二星近戰重擊者，足以支撐第三幕 Boss 隨從中的高威脅席位。 |
| `loc.unit_slice_monster_10` | 無陣營／遠程／非商店 | 怪物 11／Monster 11 | 齒脊箭豬／Gearspine Porcupine | 鋸羽鐵獸／Sawquill Beast | 齒輪脊刺與銅製低伏獸身明示金屬箭豬的遠程攻擊，名字份量保持在第三幕 Boss 隨從層級。 |
| `loc.unit_slice_monster_11` | 無陣營／術式遠程／非商店 | 怪物 12／Monster 12 | 星籠觸妖／Starcage Horror | 虛焰星魷／Voidflame Squid | 星幕觸腕、籠狀頭部與綠色虛焰構成術式異形，兩名皆帶第三幕 Boss 隨從所需的末幕威脅感。 |
| `loc.unit_slice_player_00` | 秘法同調＋翠蔭之盟／先鋒／1費 | 遠征棋士 01／Expedition Unit 01 | 晶苔衛／Gemmoss Guard | 森晶鎚士／Grovehammer | 一費秘法／翠蔭先鋒以盾鎚近戰承擔護甲向前排，晶苔與森晶同時扣合晶石、苔披風和雙陣營。 |
| `loc.unit_slice_player_01` | 翠蔭之盟＋餘燼之盟／神射手／1費 | 遠征棋士 02／Expedition Unit 02 | 燼藤弩／Embervine Arbalist | 葉火獵手／Leafspark Hunter | 一費翠蔭／餘燼神射手以藤木燼晶弩遠程輸出，樸實獵手語感適合低費雙陣營單位。 |
| `loc.unit_slice_player_02` | 餘燼之盟＋凜霜之裔／秘術師／1費 | 遠征棋士 03／Expedition Unit 03 | 冰焰使／Frostfire Adept | 燼霜巫／Cinderfrost Mystic | 一費餘燼／凜霜秘術師操使懸浮冰火雙球，兩名都以簡潔對偶呈現術式遠程與雙溫外觀。 |
| `loc.unit_slice_player_03` | 凜霜之裔＋鐵誓同盟／哨衛／1費 | 遠征棋士 04／Expedition Unit 04 | 霜鐵衛／Frostiron Guard | 破冰盾兵／Icebreak Bulwark | 一費凜霜／鐵誓哨衛以巨型鉚鐵塔盾近戰承傷，霜鐵與破冰語彙兼顧雙陣營及護盾定位。 |
| `loc.unit_slice_player_04` | 鐵誓同盟／詭術師／1費 | 遠征棋士 05／Expedition Unit 05 | 齒輪客／Chakram Tinker | 詭環機兵／Feintwheel Gunner | 一費鐵誓詭術師用齒環發射器遠程輸出，偏步構裝輪廓讓齒輪客與詭環機兵保有低費靈巧感。 |
| `loc.unit_slice_player_05` | 暮影之裔／守望者／1費 | 遠征棋士 06／Expedition Unit 06 | 幽燈守／Gloamlight Warden | 鎖月獄卒／Moonchain Gaoler | 一費暮影守望者以籠燈、月杖與幽鏈作術式遠程防線，守與獄卒都呼應魔抗型守護定位。 |
| `loc.unit_slice_player_06` | 秘法同調／先鋒／1費 | 遠征棋士 07／Expedition Unit 07 | 稜晶衛／Facetshield | 鳴晶鬥士／Resonant Vanguard | 一費秘法先鋒持稜晶盾與音叉鎚近戰增護甲，清楚的晶體與共鳴語彙維持低費但有陣營辨識度。 |
| `loc.unit_slice_player_07` | 暮影之裔／神射手／1費 | 遠征棋士 08／Expedition Unit 08 | 暮棘弓手／Duskthorn Archer | 枝影獵手／Branchshade Hunter | 一費暮影神射手以種莢長弓遠程增攻，暗暮枝影語彙能包住實際樹棘外觀而不誤標翠蔭陣營。 |
| `loc.unit_slice_player_08` | 餘燼之盟／秘術師／1費 | 遠征棋士 09／Expedition Unit 09 | 窯環侍／Kilnring Acolyte | 燼爐巫／Emberkiln Mystic | 一費餘燼秘術師由陶窯面具與環繞香爐施放遠程術式，侍與巫的簡稱保留低費施法者層級。 |
| `loc.unit_slice_player_09` | 凜霜之裔／哨衛／1費 | 遠征棋士 10／Expedition Unit 10 | 雪履衛／Snowshoe Guard | 冰鉤戍兵／Icehook Sentinel | 一費凜霜哨衛以雪履、冰盾和救援鉤刃近戰護隊，樸實戍衛用語對應開戰護盾定位。 |
| `loc.unit_slice_player_10` | 鐵誓同盟／詭術師／2費 | 遠征棋士 11／Expedition Unit 11 | 銅籌客／Coinwheel Rogue | 機運槍手／Chancework Gunner | 二費鐵誓詭術師是持籌幣遠程連發器的賭運構裝，銅籌與機運比一費齒輪兵更具個性但未過度尊貴。 |
| `loc.unit_slice_player_11` | 暮影之裔／守望者／2費 | 遠征棋士 12／Expedition Unit 12 | 蝕鐘僧／Eclipse Monk | 暮鳴守／Gloambell Keeper | 二費暮影守望者以黑鐘、骨面與符盾維持遠程術式防線，蝕與暮鳴提升神祕感並呼應魔抗向羈絆。 |
| `loc.unit_slice_player_12` | 秘法同調／先鋒／2費 | 遠征棋士 13／Expedition Unit 13 | 星環衛／Orrery Guard | 彗盾戰士／Comet Bulwark | 二費秘法先鋒的四臂、星環盔與彗盾塑造更完整的近戰護甲戰士，份量高於一費晶衛。 |
| `loc.unit_slice_player_13` | 翠蔭之盟／神射手／2費 | 遠征棋士 14／Expedition Unit 14 | 菇冠吹手／Sporepipe Scout | 菌林斥候／Mycelial Ranger | 二費翠蔭神射手以蕈傘披風、孢袋與長吹管遠程增攻，兩名都維持小型林地斥候的收藏感。 |
| `loc.unit_slice_player_14` | 餘燼之盟／秘術師／2費 | 遠征棋士 15／Expedition Unit 15 | 熔鏈先知／Molten Oracle | 赤鱗巫／Cinderscale Seer | 二費餘燼秘術師是持熔鏈火球的長頸赤鱗先知，名字比一費窯侍更有儀式份量並符合術式遠程。 |
| `loc.unit_slice_player_15` | 凜霜之裔／哨衛／2費 | 遠征棋士 16／Expedition Unit 16 | 冰甲水手／Icecarapace Sailor | 霜錨衛／Frostanchor Guard | 二費凜霜哨衛以蟹甲、舷窗盾與錨鎚近戰承傷，水手與錨衛都保留非人形海獸特色。 |
| `loc.unit_slice_player_16` | 鐵誓同盟／詭術師／2費 | 遠征棋士 17／Expedition Unit 17 | 磁軌匠／Lodestone Tinker | 紅線機師／Redcoil Gunner | 二費鐵誓詭術師以磁力手槍、長腳與紅纜提升攻速型遠程節奏，工匠語感符合中低費構裝。 |
| `loc.unit_slice_player_17` | 暮影之裔／守望者／2費 | 遠征棋士 18／Expedition Unit 18 | 蛾燈葬士／Mothlight Reaper | 暮翼守墓／Duskwings Keeper | 二費暮影守望者具有蛾翼、墓衣與燈鐮的遠程術式輪廓，葬士與守墓同時連結陰影語感及防護職責。 |
| `loc.unit_slice_player_18` | 秘法同調／先鋒／3費 | 遠征棋士 19／Expedition Unit 19 | 星圖重衛／Starchart Bulwark | 天儀戰將／Astrolabe Marshal | 三費秘法先鋒以星圖重甲、天儀盾與權杖近戰護隊，重衛與戰將建立高於二費星環衛的階層。 |
| `loc.unit_slice_player_19` | 翠蔭之盟／神射手／3費 | 遠征棋士 20／Expedition Unit 20 | 葦弓獵手／Reedbow Hunter | 沼潮神射／Miretide Archer | 三費翠蔭神射手用葦製魚叉弓在沼澤遠程增攻，沼潮語彙比低費林地斥候更有地域與份量。 |
| `loc.unit_slice_player_20` | 餘燼之盟／秘術師／3費 | 遠征棋士 21／Expedition Unit 21 | 爐扇舞者／Furnace Dancer | 熾環術士／Brazier Mystic | 三費餘燼秘術師以雙火盆扇和白熱裙襬旋舞施放遠程術式，舞者與術士兼顧鮮明輪廓及中費儀式感。 |
| `loc.unit_slice_player_21` | 凜霜之裔／哨衛／3費 | 遠征棋士 22／Expedition Unit 22 | 海象盾衛／Walrus Guard | 冰橇鎚將／Sledhammer Captain | 三費凜霜哨衛的海象面具、雪橇盾與方冰鎚形成重裝近戰，鎚將稱號拉開與二費蟹甲水手的層級。 |
| `loc.unit_slice_player_22` | 鐵誓同盟／詭術師／3費 | 遠征棋士 23／Expedition Unit 23 | 發條信使／Clockwork Courier | 迴簧快手／Springback Ace | 三費鐵誓詭術師以發條回力器和前傾郵袋輪廓高速遠程輸出，信使與快手強調攻速型機動節奏。 |
| `loc.unit_slice_player_23` | 暮影之裔／守望者／3費 | 遠征棋士 24／Expedition Unit 24 | 黑鏡守騎／Blackmirror Knight | 碎光獄衛／Shardlight Warden | 三費暮影守望者以黑鏡塔形焦器與浮游碎片構成遠程術式防線，守騎與獄衛提升中費單位的冷峻份量。 |
| `loc.unit_slice_player_24` | 秘法同調／先鋒／4費 | 遠征棋士 25／Expedition Unit 25 | 晶甲龜衛／Crystal Tortoise | 稜堡重鎚／Prism Bastion | 四費秘法先鋒是低伏晶龜外骨骼與稜堡撞鎚的近戰重坦，名稱保留獸形並建立高費堡壘感。 |
| `loc.unit_slice_player_25` | 翠蔭之盟／神射手／4費 | 遠征棋士 26／Expedition Unit 26 | 蜂巢獵手／Hivebow Ranger | 蜜弩名手／Honeybolt Deadeye | 四費翠蔭神射手以蜂巢弩、寬網面罩與蜜蠟裝具遠程增攻，名手語感使其高於沼澤獵手。 |
| `loc.unit_slice_player_26` | 餘燼之盟／秘術師／4費 | 遠征棋士 27／Expedition Unit 27 | 煙爐鍊金／Smokeforge Alchemist | 蝕霧術師／Caustic Savant | 四費餘燼秘術師攜玻璃蒸餾杖、煤煙與蝕性霧氣遠程施法，鍊金與術師稱號提供高費專精份量。 |
| `loc.unit_slice_player_27` | 凜霜之裔／哨衛／4費 | 遠征棋士 28／Expedition Unit 28 | 寒潛重衛／Frostdiver Guard | 極地潛將／Polar Dreadnought | 四費凜霜哨衛以冰窗潛水服、圓盾與短冰斧近戰承傷，重衛與潛將凸顯高費極地堡壘感。 |
| `loc.unit_slice_player_28` | 鐵誓同盟／詭術師／4費 | 遠征棋士 29／Expedition Unit 29 | 鋼索舞槍／Wiregun Dancer | 纜影客／Steelcord Duelist | 四費鐵誓詭術師以雙纜線手槍和鋼帶舞步高速遠程輸出，舞槍與決鬥者比中費信使更精銳。 |
| `loc.unit_slice_player_29` | 暮影之裔／守望者／5費 | 遠征棋士 30／Expedition Unit 30 | 鴉獄典守／Raven Gaoler | 鎖碑冥衛／Obelisk Warden | 五費暮影守望者披鴉羽、戴柵面並鎖縛黑碑遠程施術，典守與冥衛給足最高費階的禁錮權威。 |
| `loc.unit_slice_player_30` | 秘法同調／先鋒／5費 | 遠征棋士 31／Expedition Unit 31 | 天碑巨像／Runestone Colossus | 星垣巨靈／Starwall Colossus | 五費秘法先鋒是浮盾、巨拳與星紋石塊構成的近戰巨像，兩名皆呈現最高費護甲核心的宏大份量。 |
| `loc.unit_slice_player_31` | 翠蔭之盟／神射手／5費 | 遠征棋士 32／Expedition Unit 32 | 冠林翔弓／Canopy Windbow | 花翼神獵／Petalwing Archer | 五費翠蔭神射手以花盤弓、葉翼披風與林冠滑翔姿態遠程增攻，翔弓與神獵建立最高費收藏感。 |

## 裁決閘門

- 請逐列選擇候選 1、候選 2，或另提修訂方向。
- 未經裁決，不得把任何候選寫入 localization catalog、content resource 或 runtime 程式。
- 本文件不改變任何 faction、role、cost、encounter 或戰鬥數值的 canonical 定義。
