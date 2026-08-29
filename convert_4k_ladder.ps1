# 4K ladder encode + lossless cutter + lossless loop-extend to 5:30
# Put ffmpeg.exe (and ffprobe.exe if available) next to this script.
#
# Usage: double-click convert_4k_ladder.bat
# Ladder outputs: HEVC Main 8-bit 4:2:0 (yuv420p) in MP4 hvc1.

[CmdletBinding()]
param(
    [string]$ScriptDir = "",
    [string]$InputDir = "",
    [string]$OutputDir = "",
    [string[]]$Extensions = @("*.mkv", "*.mp4", "*.mov", "*.webm", "*.hevc", "*.h265", "*.265", "*.ts", "*.m2ts", "*.m4v", "*.yuv", "*.y4m"),
    [switch]$Overwrite
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
