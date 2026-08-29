# 4K ladder encode + lossless cutter + lossless loop-extend to 5:30
# Put ffmpeg.exe (and ffprobe.exe if available) next to this script.
#
# Usage: double-click convert_4k_ladder.bat

[CmdletBinding()]
param(
    [string]$ScriptDir = "",
    [string]$InputDir = "",
    [string]$OutputDir = "",
    [string[]]$Extensions = @("*.mkv", "*.mp4", "*.mov", "*.webm", "*.hevc", "*.h265", "*.265", "*.ts", "*.m2ts", "*.m4v", "*.yuv", "*.y4m"),
    [switch]$Overwrite
)
