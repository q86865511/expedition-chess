# Phase D accessibility localization migration

## 25-key reseal mapping

| key | zh_TW | en | 來源 |
| --- | --- | --- | --- |
| `accessibility.combat.rule_probe` | 戰鬥規則：護盾破裂後，敵方會進入第二階段。 | Battle rule: after the shield breaks, the enemy enters phase two. | 內嵌表 |
| `accessibility.combat.state_summary` | 動態：%s　閃光：%s　粒子：%s　傷害數字：%s | Motion: %s  Flash: %s  Particles: %s  Damage numbers: %s | 內嵌表 |
| `accessibility.combat.rule_information` | 規則資訊會同時使用文字、圖示與圖樣提示。 | Rules use text, icons, and pattern cues together. | 內嵌表 |
| `accessibility.combat.pattern_cue` | [///] 傷害　[!] 危險 | [///] Damage  [!] Danger | 內嵌表 |
| `accessibility.combat.motion` | 動態效果 | Motion effects | 內嵌表 |
| `accessibility.combat.flash` | 閃光效果 | Flash effects | 內嵌表 |
| `accessibility.combat.particles` | 粒子效果 | Particle effects | 內嵌表 |
| `accessibility.combat.damage_event` | [傷害\|%s] %s %d → %s | [Damage\|%s] %s %d -> %s | 內嵌表 |
| `accessibility.combat.damage_sample_1` | [DMG] 128 | [DMG] 128 | 內嵌表 |
| `accessibility.combat.damage_sample_2` | [DMG] 64 | [DMG] 64 | 內嵌表 |
| `accessibility.combat.damage_sample_3` | [DMG] 32 | [DMG] 32 | 內嵌表 |
| `accessibility.state.full` | 完整 | Full | 內嵌表 |
| `accessibility.state.reduced` | 減少 | Reduced | 內嵌表 |
| `accessibility.semantic.ally` | [A] 我方 | [A] Ally | 內嵌表 |
| `accessibility.semantic.enemy` | [E] 敵方 | [E] Enemy | 內嵌表 |
| `accessibility.semantic.trait` | [T] 特性 | [T] Trait | 內嵌表 |
| `accessibility.semantic.rarity` | [*] 稀有度 | [*] Rarity | 內嵌表 |
| `accessibility.semantic.danger` | [!] 危險 | [!] Danger | 內嵌表 |
| `accessibility.semantic.damage` | [DMG] 傷害 | [DMG] Damage | 內嵌表 |
| `accessibility.allegiance.ally` | [A] 我方 | [A] Ally | text_key（機械沿用 `accessibility.semantic.ally`） |
| `accessibility.allegiance.enemy` | [E] 敵方 | [E] Enemy | text_key（機械沿用 `accessibility.semantic.enemy`） |
| `accessibility.bond.active` | [T] 特性 | [T] Trait | text_key（機械沿用 `accessibility.semantic.trait`） |
| `accessibility.rarity.legendary` | [*] 稀有度 | [*] Rarity | text_key（機械沿用 `accessibility.semantic.rarity`） |
| `accessibility.damage.arcane` | [DMG] 傷害 | [DMG] Damage | text_key（機械沿用 `accessibility.semantic.damage`） |
| `accessibility.danger.lethal` | [!] 危險 | [!] Danger | text_key（機械沿用 `accessibility.semantic.danger`） |

後六個 key 原先只有 `AccessibilitySemanticTokens.text_key` 引用，沒有自己的值表；本次不創作新文案，逐項複用既有同類 semantic cue 字串。未來若要細分「啟用羈絆／傳說／奧術／致命」等語意，應另立文案裁決，不混入這次機械遷移。

## 殘留處理：保留薄轉接

`production_accessibility_localization.gd` 保留為薄轉接，原因是 production accessibility consumer 已依賴其中的 key 常數、`resolve()` 與 `semantic()` API。檔內雙語 `_VALUES` 已移除；正式 catalog 由 host 注入，未注入時只使用既有 sealed emergency catalog。因此值的唯一來源是 `LocalizationCatalog`，同時不需要擴大修改呼叫端或改動 consumer 契約。

## Gate 補強

靜態 gate 除既有 localization resolve 呼叫外，也將 dictionary 中的 `"text_key": &"…"` 視為程式引用。測試包含一個 catalog 缺漏的 accessibility `text_key` fixture，必須回報 `PUI_LOCALIZATION_REFERENCE_MISSING`；一般 stable ID 仍不會被誤判。
