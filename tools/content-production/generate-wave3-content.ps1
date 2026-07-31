[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$packRoot = Join-Path $repoRoot 'content\packs\vertical_slice'
$utf8NoBom = New-Object Text.UTF8Encoding($false)

function Write-Utf8 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    [IO.File]::WriteAllText($Path, ($Text.Trim() + "`n"), $utf8NoBom)
}

function Set-UnitProductionRefs {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Token
    )
    $text = [IO.File]::ReadAllText($Path)
    $linesToRemove = @(
        '(?m)^schema_version = .*\r?\n?',
        '(?m)^ability_ref = .*\r?\n?',
        '(?m)^has_ability_ref = .*\r?\n?',
        '(?m)^presentation_ref = .*\r?\n?'
    )
    foreach ($pattern in $linesToRemove) {
        $text = [regex]::Replace($text, $pattern, '')
    }
    $insert = @"
schema_version = 2
ability_ref = &"ability.$Token"
has_ability_ref = true
presentation_ref = &"presentation.$Token"
"@
    $text = [regex]::Replace(
        $text,
        '(?m)^id = ',
        ($insert.TrimEnd() + "`n" + 'id = '),
        1
    )
    [IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}

$unitFiles = Get-ChildItem -LiteralPath (Join-Path $packRoot 'units') -Filter '*.tres' |
    Sort-Object Name
if ($unitFiles.Count -ne 44) {
    throw "Expected 44 UnitDef resources, found $($unitFiles.Count)."
}

foreach ($unitFile in $unitFiles) {
    $match = [regex]::Match(
        [IO.File]::ReadAllText($unitFile.FullName),
        'id = &"unit\.([^"]+)"'
    )
    if (-not $match.Success) {
        throw "Unable to read UnitDef id from $($unitFile.FullName)."
    }
    $token = $match.Groups[1].Value
    Set-UnitProductionRefs -Path $unitFile.FullName -Token $token

    $ordinalMatch = [regex]::Match($token, '_(\d+)$')
    $ordinal = if ($ordinalMatch.Success) {
        [int]$ordinalMatch.Groups[1].Value
    }
    else {
        0
    }
    $damage = if ($token.StartsWith('slice_monster_')) {
        32 + ($ordinal * 3)
    }
    else {
        48 + ($ordinal * 2)
    }

    $abilityText = @"
[gd_resource type="Resource" script_class="AbilityDef" format=3]

[ext_resource type="Script" path="res://content/definitions/ability_def.gd" id="1_ability"]

[resource]
script = ExtResource("1_ability")
schema_version = 1
start_mana = 0
max_mana = 50
target_rule = &"current_target"
cast_ticks = 30
effect_refs = Array[StringName]([&"effect.$token.primary"])
description_key = &"loc.ability_${token}_description"
id = &"ability.$token"
display_name_key = &"loc.ability_$token"
"@
    Write-Utf8 -Path (Join-Path $packRoot "abilities\$token.tres") -Text $abilityText

    $effectText = @"
[gd_resource type="Resource" script_class="EffectDef" load_steps=4 format=3]

[ext_resource type="Script" path="res://content/definitions/battle_operation_def.gd" id="1_battle"]
[ext_resource type="Script" path="res://content/definitions/damage_operation_def.gd" id="2_damage"]
[ext_resource type="Script" path="res://content/definitions/effect_def.gd" id="3_effect"]

[sub_resource type="Resource" id="Damage_primary"]
script = ExtResource("2_damage")
base = $damage
scaling = &"attack"
damage_type = &"physical"
target = &"target"

[resource]
script = ExtResource("3_effect")
schema_version = 2
content_role = &"ability_primary"
trigger = &"cast"
battle_operations = Array[ExtResource("1_battle")]([SubResource("Damage_primary")])
stacking = &"replace"
duration_ticks = 1
description_key = &"loc.effect_${token}_primary_description"
id = &"effect.$token.primary"
display_name_key = &"loc.effect_${token}_primary"
"@
    Write-Utf8 -Path (Join-Path $packRoot "unit_effects\$token.tres") -Text $effectText

    $presentationText = @"
[gd_resource type="Resource" script_class="UnitPresentationDef" format=3]

[ext_resource type="Script" path="res://content/definitions/unit_presentation_def.gd" id="1_presentation"]

[resource]
script = ExtResource("1_presentation")
schema_version = 1
portrait_path = "res://assets/production/portraits/$token.png"
sprite_frames_path = "res://assets/production/units/$token.tres"
board_icon_path = "res://assets/production/icons/board/$token.png"
ability_icon_path = "res://assets/production/icons/abilities/$token.png"
combat_vfx_refs = [&"effect.$token.primary"]
audio_cue_refs = [&"audio.combat_cast"]
id = &"presentation.$token"
display_name_key = &"loc.presentation_$token"
"@
    Write-Utf8 -Path (Join-Path $packRoot "unit_presentations\$token.tres") -Text $presentationText
}

$effectFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'content\packs') `
    -Recurse -Filter '*.tres' |
    Where-Object {
        [IO.File]::ReadAllText($_.FullName) -match 'script_class="EffectDef"'
    }
foreach ($effectFile in $effectFiles) {
    $text = [IO.File]::ReadAllText($effectFile.FullName)
    $idMatch = [regex]::Match($text, 'id = &"effect\.([^"]+)"')
    if (-not $idMatch.Success) {
        throw "Unable to read EffectDef id from $($effectFile.FullName)."
    }
    $descriptionKey = 'loc.effect_' + $idMatch.Groups[1].Value.Replace('.', '_') + '_description'
    $text = [regex]::Replace($text, '(?m)^schema_version = .*\r?\n?', '')
    $text = [regex]::Replace($text, '(?m)^description_key = .*\r?\n?', '')
    $insert = "schema_version = 2`ndescription_key = &`"$descriptionKey`""
    $text = [regex]::Replace(
        $text,
        '(?m)^id = ',
        ($insert + "`n" + 'id = '),
        1
    )
    [IO.File]::WriteAllText($effectFile.FullName, $text, $utf8NoBom)
}

$audioCueText = @'
[gd_resource type="Resource" script_class="AudioCueDef" format=3]

[ext_resource type="Script" path="res://content/definitions/audio_cue_def.gd" id="1_audio"]

[resource]
script = ExtResource("1_audio")
bus = &"SFX"
stream_path = "res://assets/production/audio/sfx/combat_cast.ogg"
loop = false
id = &"audio.combat_cast"
display_name_key = &"loc.audio_combat_cast"
'@
Write-Utf8 -Path (Join-Path $packRoot 'audio_cues\combat_cast.tres') -Text $audioCueText

for ($index = 0; $index -lt 12; $index++) {
    $suffix = $index.ToString('00')
    $safeGold = 18 + $index
    $riskyGold = 36 + ($index * 2)
    $hpCost = 4 + ($index % 4)
    $choiceText = @"
[gd_resource type="Resource" script_class="NodeChoiceSetDef" load_steps=7 format=3]

[ext_resource type="Script" path="res://content/definitions/run_operation_def.gd" id="1_run"]
[ext_resource type="Script" path="res://content/definitions/add_gold_operation_def.gd" id="2_gold"]
[ext_resource type="Script" path="res://content/definitions/drain_expedition_hp_operation_def.gd" id="3_drain"]
[ext_resource type="Script" path="res://content/definitions/node_choice_def.gd" id="4_choice"]
[ext_resource type="Script" path="res://content/definitions/node_choice_set_def.gd" id="5_set"]

[sub_resource type="Resource" id="Safe_gold"]
script = ExtResource("2_gold")
amount = $safeGold
claim_scope = &"once_per_node"

[sub_resource type="Resource" id="Risk_gold"]
script = ExtResource("2_gold")
amount = $riskyGold
claim_scope = &"once_per_node"

[sub_resource type="Resource" id="Risk_hp"]
script = ExtResource("3_drain")
amount = $hpCost
claim_scope = &"once_per_node"
operation_index = 1

[sub_resource type="Resource" id="Choice_safe"]
script = ExtResource("4_choice")
choice_id = &"choice.event_${suffix}.safe"
sort_order = 0
title_key = &"loc.choice_event_${suffix}_safe_title"
description_key = &"loc.choice_event_${suffix}_safe_description"
preview_key = &"loc.choice_event_${suffix}_safe_preview"
result_key = &"loc.choice_event_${suffix}_safe_result"
operations = Array[ExtResource("1_run")]([SubResource("Safe_gold")])
confirmation_required = true

[sub_resource type="Resource" id="Choice_risk"]
script = ExtResource("4_choice")
choice_id = &"choice.event_${suffix}.risk"
sort_order = 1
title_key = &"loc.choice_event_${suffix}_risk_title"
description_key = &"loc.choice_event_${suffix}_risk_description"
preview_key = &"loc.choice_event_${suffix}_risk_preview"
result_key = &"loc.choice_event_${suffix}_risk_result"
operations = Array[ExtResource("1_run")]([SubResource("Risk_gold"), SubResource("Risk_hp")])
confirmation_required = true

[resource]
script = ExtResource("5_set")
node_kind = &"event"
choices = Array[ExtResource("4_choice")]([SubResource("Choice_safe"), SubResource("Choice_risk")])
id = &"choice_set.event_$suffix"
display_name_key = &"loc.choice_set_event_$suffix"
"@
    Write-Utf8 -Path (Join-Path $packRoot "node_choices\event_$suffix.tres") -Text $choiceText

    $mapPath = Join-Path $packRoot "map_nodes\slice_event_$suffix.tres"
    $mapText = [IO.File]::ReadAllText($mapPath)
    $mapText = [regex]::Replace(
        $mapText,
        'generator_ref = &"[^"]+"',
        "generator_ref = &`"choice_set.event_$suffix`""
    )
    [IO.File]::WriteAllText($mapPath, $mapText, $utf8NoBom)
}

$restText = @'
[gd_resource type="Resource" script_class="NodeChoiceSetDef" load_steps=6 format=3]

[ext_resource type="Script" path="res://content/definitions/run_operation_def.gd" id="1_run"]
[ext_resource type="Script" path="res://content/definitions/heal_expedition_hp_operation_def.gd" id="2_heal"]
[ext_resource type="Script" path="res://content/definitions/node_choice_def.gd" id="3_choice"]
[ext_resource type="Script" path="res://content/definitions/node_choice_set_def.gd" id="4_set"]

[sub_resource type="Resource" id="Heal_20"]
script = ExtResource("2_heal")
amount = 20
claim_scope = &"once_per_node"

[sub_resource type="Resource" id="Choice_heal"]
script = ExtResource("3_choice")
choice_id = &"choice.rest.heal_20"
sort_order = 0
title_key = &"loc.choice_rest_heal_20_title"
description_key = &"loc.choice_rest_heal_20_description"
preview_key = &"loc.choice_rest_heal_20_preview"
result_key = &"loc.choice_rest_heal_20_result"
operations = Array[ExtResource("1_run")]([SubResource("Heal_20")])
confirmation_required = true

[sub_resource type="Resource" id="Choice_dismantle"]
script = ExtResource("3_choice")
choice_id = &"choice.rest.dismantle"
sort_order = 1
title_key = &"loc.choice_rest_dismantle_title"
description_key = &"loc.choice_rest_dismantle_description"
preview_key = &"loc.choice_rest_dismantle_preview"
result_key = &"loc.choice_rest_dismantle_result"
outcome_kind = 2
confirmation_required = true

[resource]
script = ExtResource("4_set")
node_kind = &"rest"
choices = Array[ExtResource("3_choice")]([SubResource("Choice_heal"), SubResource("Choice_dismantle")])
id = &"choice_set.rest"
display_name_key = &"loc.choice_set_rest"
'@
Write-Utf8 -Path (Join-Path $packRoot 'node_choices\rest.tres') -Text $restText

$treasureText = @'
[gd_resource type="Resource" script_class="NodeChoiceSetDef" load_steps=7 format=3]

[ext_resource type="Script" path="res://content/definitions/run_operation_def.gd" id="1_run"]
[ext_resource type="Script" path="res://content/definitions/add_gold_operation_def.gd" id="2_gold"]
[ext_resource type="Script" path="res://content/definitions/node_choice_def.gd" id="3_choice"]
[ext_resource type="Script" path="res://content/definitions/node_choice_set_def.gd" id="4_set"]

[sub_resource type="Resource" id="Gold_cache"]
script = ExtResource("2_gold")
amount = 45
claim_scope = &"once_per_node"

[sub_resource type="Resource" id="Choice_standard"]
script = ExtResource("3_choice")
choice_id = &"choice.treasure.standard"
sort_order = 0
title_key = &"loc.choice_treasure_standard_title"
description_key = &"loc.choice_treasure_standard_description"
preview_key = &"loc.choice_treasure_standard_preview"
result_key = &"loc.choice_treasure_standard_result"
has_reward_table_ref = true
reward_table_ref = &"reward_table.slice_standard"
outcome_kind = 3
confirmation_required = true

[sub_resource type="Resource" id="Choice_relic"]
script = ExtResource("3_choice")
choice_id = &"choice.treasure.relic"
sort_order = 1
title_key = &"loc.choice_treasure_relic_title"
description_key = &"loc.choice_treasure_relic_description"
preview_key = &"loc.choice_treasure_relic_preview"
result_key = &"loc.choice_treasure_relic_result"
has_reward_table_ref = true
reward_table_ref = &"reward_table.slice_relic"
outcome_kind = 3
confirmation_required = true

[sub_resource type="Resource" id="Choice_gold"]
script = ExtResource("3_choice")
choice_id = &"choice.treasure.gold"
sort_order = 2
title_key = &"loc.choice_treasure_gold_title"
description_key = &"loc.choice_treasure_gold_description"
preview_key = &"loc.choice_treasure_gold_preview"
result_key = &"loc.choice_treasure_gold_result"
operations = Array[ExtResource("1_run")]([SubResource("Gold_cache")])
confirmation_required = true

[resource]
script = ExtResource("4_set")
node_kind = &"treasure"
choices = Array[ExtResource("3_choice")]([SubResource("Choice_standard"), SubResource("Choice_relic"), SubResource("Choice_gold")])
id = &"choice_set.treasure"
display_name_key = &"loc.choice_set_treasure"
'@
Write-Utf8 -Path (Join-Path $packRoot 'node_choices\treasure.tres') -Text $treasureText

foreach ($mapping in @(
    @{ File = 'slice_rest.tres'; Ref = 'choice_set.rest' },
    @{ File = 'slice_treasure.tres'; Ref = 'choice_set.treasure' }
)) {
    $mapPath = Join-Path $packRoot ('map_nodes\' + $mapping.File)
    $mapText = [IO.File]::ReadAllText($mapPath)
    $mapText = [regex]::Replace(
        $mapText,
        'generator_ref = &"[^"]+"',
        ('generator_ref = &"' + $mapping.Ref + '"')
    )
    [IO.File]::WriteAllText($mapPath, $mapText, $utf8NoBom)
}

$bossPath = Join-Path $packRoot 'encounters\slice_boss_0.tres'
$bossText = [IO.File]::ReadAllText($bossPath)
if ($bossText -notmatch 'Resource_phase_two') {
    $bossText = $bossText.Replace(
        '[sub_resource type="Resource" id="Resource_wvclx"]',
        @'
[sub_resource type="Resource" id="Resource_phase_two"]
script = ExtResource("1_vhxv8")
phase_index = 1
hp_threshold_bps = 5000
source_spawn_key = "boss_0"
effect_refs = Array[StringName]([&"effect.slice_affix_01"])

[sub_resource type="Resource" id="Resource_wvclx"]
'@
    )
    $bossText = $bossText.Replace(
        'boss_phases = Array[ExtResource("1_vhxv8")]([SubResource("Resource_mnswc")])',
        'boss_phases = Array[ExtResource("1_vhxv8")]([SubResource("Resource_mnswc"), SubResource("Resource_phase_two")])'
    )
    [IO.File]::WriteAllText($bossPath, $bossText, $utf8NoBom)
}

Write-Output "Generated formal content for $($unitFiles.Count) units, 12 events, rest, treasure, and a multi-phase boss."
