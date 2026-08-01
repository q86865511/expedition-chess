[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Repo
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath($Repo)
$sourcePath = Join-Path $PSScriptRoot 'production_audio_encoder.cs'
Add-Type -Path $sourcePath

$entries = [ProductionAudioEncoder]::Build($repoRoot)
$music = New-Object System.Collections.Generic.List[object]
$sfx = New-Object System.Collections.Generic.List[object]
$cueRoot = Join-Path $repoRoot 'content\packs\vertical_slice\audio_cues'
$utf8 = New-Object Text.UTF8Encoding($false)

foreach ($entry in $entries) {
    $relativePath = $entry.Path.Substring($repoRoot.Length).TrimStart('\').Replace('\', '/')
    $bus = if ($entry.IsMusic) { 'Music' } elseif ($entry.Token.StartsWith('ui_')) { 'UI' } else { 'SFX' }
    $record = [ordered]@{
        cue_id = 'audio.' + $entry.Token
        path = $relativePath
        sha256 = $entry.Sha256
        bus = $bus
        loop = [bool]$entry.IsMusic
        sample_rate = [int]$entry.SampleRate
        channels = [int]$entry.Channels
        frames = [long]$entry.Frames
        duration_seconds = [double]$entry.DurationSeconds
        container = 'OGG'
        codec = 'VORBIS'
        true_peak_dbfs = [double]$entry.TruePeakDbfs
        local_processing_seed = [int]$entry.LocalProcessingSeed
    }
    if ($entry.IsMusic) {
        $record.loop_seam_rms_dbfs = [double]$entry.LoopSeamRmsDbfs
        $music.Add($record)
    }
    else { $sfx.Add($record) }

    $cueText = @"
[gd_resource type="Resource" script_class="AudioCueDef" format=3]

[ext_resource type="Script" path="res://content/definitions/audio_cue_def.gd" id="1_audio"]

[resource]
script = ExtResource("1_audio")
bus = &"$bus"
stream_path = "res://$relativePath"
loop = $(([string][bool]$entry.IsMusic).ToLowerInvariant())
id = &"audio.$($entry.Token)"
display_name_key = &"loc.audio_$($entry.Token)"
"@
    [IO.File]::WriteAllText(
        (Join-Path $cueRoot ($entry.Token + '.tres')),
        $cueText.Replace("`r`n", "`n"),
        $utf8
    )
}

$inventory = [ordered]@{
    schema_version = 1
    slice = 'content-production'
    status = 'adopted'
    sample_rate = 48000
    channels = 2
    container = 'OGG'
    codec = 'VORBIS'
    encoder = [ordered]@{
        soundfile_version = '0.13.1'
        libsndfile_version = '1.2.2'
        wheel = 'soundfile-0.13.1-py2.py3-none-win_amd64.whl'
        wheel_sha256 = '1e70a05a0626524a69e9f0f4dd2ec174b4e9567f4d8b6c11d38b5c289be36ee9'
        python = '3.12.13'
        vorbis_quality = 0.5
        compression_level = 0.5
        native_encoder = 'libsndfile_x64.dll'
    }
    synthesis = [ordered]@{
        script = 'tools/content-production/generate-production-audio.ps1'
        python_reference = 'tools/content-production/generate-production-audio.py'
        local_seed_base = 1194475861
        music_seconds = 24
        loop_seam_window_ms = 50
        true_peak_oversample = 4
        music_recipe = 'periodic additive synthesis with deterministic 50ms loop closure'
        sfx_recipe = 'seeded tonal sweep plus shaped noise, deterministic stereo spread'
    }
    music = $music.ToArray()
    sfx = $sfx.ToArray()
}
$inventoryPath = Join-Path $repoRoot 'assets\production\audio\inventory.json'
[IO.File]::WriteAllText(
    $inventoryPath,
    ((($inventory | ConvertTo-Json -Depth 10) + "`n").Replace("`r`n", "`n")),
    $utf8
)
Write-Output "generated $($music.Count) loop music and $($sfx.Count) semantic SFX"
