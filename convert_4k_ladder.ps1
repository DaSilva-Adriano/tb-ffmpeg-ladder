# 4K ladder encode + lossless cut (input/output) + lossless loop-extend to 5:30
# Put ffmpeg.exe (and ffprobe.exe if available) next to this script.
#
# Usage: double-click convert_4k_ladder.bat

[CmdletBinding()]
param(
    [string]$ScriptDir = "",
    [string]$InputDir = "",
    [string]$OutputDir = "",
    [string[]]$Extensions = @("*.mkv", "*.mp4", "*.mov", "*.webm", "*.hevc", "*.h265", "*.265", "*.ts", "*.m2ts", "*.m4v", "*.yuv", "*.y4m"),
    [switch]$Overwrite,
    [switch]$Include30Fps
)

$ErrorActionPreference = "Stop"

$TargetExtendSeconds = 330
$TargetExtendStamp = "00:05:30"
$script:YuvSize = "3840x2160"
$script:YuvPix  = "yuv420p"
$script:YuvFps  = "24"

$Ladder = @(
    @{ Name = "4k";    Width = 3840; Height = 2160; Crf = "18" }
    @{ Name = "1080p"; Width = 1920; Height = 1080; Crf = "20" }
    @{ Name = "720p";  Width = 1280; Height = 720;  Crf = "22" }
    @{ Name = "480p";  Width = 854;  Height = 480;  Crf = "23" }
    @{ Name = "360p";  Width = 640;  Height = 360;  Crf = "24" }
)

$here = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($here)) {
    if ($MyInvocation.MyCommand.Path) {
        $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    } else {
        $here = (Get-Location).Path
    }
}

foreach ($part in @(
    "convert_4k_ladder.helpers.ps1",
    "convert_4k_ladder.encode.ps1",
    "convert_4k_ladder.extend.ps1",
    "convert_4k_ladder.cutout.ps1",
    "convert_4k_ladder.crf18.ps1"
)) {
    $p = Join-Path $here $part
    if (-not (Test-Path $p)) {
        Write-Host "Missing $p" -ForegroundColor Red
        exit 1
    }
    . $p
}

$root = Get-ScriptDirectory
if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path $root)) {
    Write-Host "Cannot resolve the script folder." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($InputDir)) {
    $InputDir = Join-Path $root "input"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $root "output"
}

$ffmpeg = Join-Path $root "ffmpeg.exe"
$ffprobe = Join-Path $root "ffprobe.exe"
if (-not (Test-Path $ffmpeg)) {
    Write-Host "ffmpeg.exe not found next to the script." -ForegroundColor Red
    Write-Host "Expected:"
    Write-Host "  $ffmpeg"
    Write-Host "Full build: https://www.gyan.dev/ffmpeg/builds/"
    exit 1
}

Initialize-Folders

while ($true) {
    Write-Host ""
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host " 1) Encode ladder   (4K / 1080p / 720p / 480p / 360p)"
    Write-Host " 2) Cut master      (lossless, start / end, input/)"
    Write-Host " 3) Cut output      (lossless, multi-select, output/)"
    Write-Host " 4) Extend output   (copy-concat loop to 5:30)"
    Write-Host " 5) Upscale         (bicubic to 4K, CRF 12)"
    Write-Host " 6) CRF 18 control  (360p+1080p CRF 18 + Lanczos to 4K)"
    Write-Host " 7) Quit"
    Write-Host "==============================" -ForegroundColor Cyan
    $sel = (Read-Host "Choice").Trim()

    switch ($sel) {
        "1" { Invoke-EncodeLadder }
        "2" { Invoke-CutMaster }
        "3" { Invoke-CutOutputs }
        "4" { Invoke-ExtendShortOutputs }
        "5" { Invoke-Upscale720pBicubic4k }
        "6" { Invoke-Crf18LanczosControl }
        "7" { break }
        "q" { break }
        "Q" { break }
        default { Write-Host "Choose 1, 2, 3, 4, 5, 6 or 7." -ForegroundColor Yellow }
    }

    if ($sel -eq "7" -or $sel -eq "q" -or $sel -eq "Q") { break }
}

exit 0
