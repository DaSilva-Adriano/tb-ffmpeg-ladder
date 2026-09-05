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

function Get-ScriptDirectory {
    if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
        return $ScriptDir.TrimEnd("\")
    }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }
    if ($MyInvocation.MyCommand.Path) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }
    if ($MyInvocation.MyCommand.Definition) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Definition)
    }
    return (Get-Location).Path
}

function Test-TimeStamp([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    $value = $value.Trim()
    if ($value -match '^\d+(\.\d+)?$') { return $true }
    if ($value -match '^\d+:[0-5]?\d:[0-5]?\d(\.\d+)?$') { return $true }
    if ($value -match '^\d+:[0-5]?\d(\.\d+)?$') { return $true }
    return $false
}

function ConvertTo-FileSafeStamp([string]$value) {
    return (($value.Trim() -replace ':', '_') -replace '\.', '_')
}

function Get-InputVideos {
    $list = @()
    foreach ($ext in $Extensions) {
        $list += Get-ChildItem -LiteralPath $InputDir -File -Filter $ext -ErrorAction SilentlyContinue
    }
    return @($list | Sort-Object Name | Select-Object -Unique)
}

function Get-DurationSeconds([string]$path) {
    if (-not (Test-Path $ffprobe)) { return $null }
    try {
        $dur = & $ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $path 2>$null
        if ([string]::IsNullOrWhiteSpace($dur)) { return $null }
        return [double]$dur
    } catch {
        return $null
    }
}

function Get-DurationString([string]$path) {
    $sec = Get-DurationSeconds $path
    if ($null -eq $sec) { return "" }
    $ts = [TimeSpan]::FromSeconds($sec)
    return ("{0:00}:{1:00}:{2:00}" -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)
}

function Get-OutputVideos {
    $list = @()
    foreach ($ext in $Extensions) {
        $list += Get-ChildItem -LiteralPath $OutputDir -File -Filter $ext -ErrorAction SilentlyContinue
    }
    return @($list | Sort-Object Name | Select-Object -Unique)
}

function Test-Y4mFile([string]$path) {
    return ([IO.Path]::GetExtension($path).ToLowerInvariant() -eq ".y4m")
}

function Test-RawYuvFile([string]$path) {
    return ([IO.Path]::GetExtension($path).ToLowerInvariant() -eq ".yuv")
}

function Read-Default([string]$prompt, [string]$current) {
    $value = (Read-Host "$prompt [$current]").Trim()
    if ($value -eq "") { return $current }
    return $value
}

function Get-RawVideoInputArgs([string]$path) {
    if (Test-Y4mFile $path) { return @() }
    if (-not (Test-RawYuvFile $path)) { return @() }

    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    $size = $script:YuvSize
    $pix  = $script:YuvPix
    $fps  = $script:YuvFps
    if ($name -match '(\d{3,5})x(\d{3,5})') { $size = $Matches[1] + "x" + $Matches[2] }
    if ($name -match '(yuv\w+|nv12|nv21|p010le)') { $pix = $Matches[1] }
    if ($name -match '(\d{2,3})\s*fps') { $fps = $Matches[1] }

    Write-Host ""
    Write-Host "Raw .yuv has no header. FFmpeg needs the format of:" -ForegroundColor Yellow
    Write-Host "  $path"
    $size = Read-Default "Resolution WxH" $size
    $pix  = Read-Default "Pixel format (yuv420p / yuv420p10le / yuv422p / nv12)" $pix
    $fps  = Read-Default "Frame rate" $fps

    if ($size -notmatch '^\d{3,5}x\d{3,5}$') {
        throw "Invalid resolution '$size'. Use 3840x2160."
    }
    if ($fps -notmatch '^\d+(\.\d+)?$') {
        throw "Invalid frame rate '$fps'."
    }

    $script:YuvSize = $size
    $script:YuvPix  = $pix
    $script:YuvFps  = $fps

    return @("-f", "rawvideo", "-pix_fmt", $pix, "-s:v", $size, "-r", $fps)
}

function ConvertTo-ConcatPath([string]$path) {
    return ($path -replace '\\', '/') -replace "'", "'\\''"
}

function Select-InputVideos {
    param(
        [object[]]$Files,
        [switch]$AllowAll,
        [string]$Heading = "Files in input:"
    )

    if ($Files.Count -eq 0) { return @() }

    Write-Host ""
    Write-Host $Heading -ForegroundColor Cyan
    for ($i = 0; $i -lt $Files.Count; $i++) {
        $dur = Get-DurationString $Files[$i].FullName
        if ($dur) {
            Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $Files[$i].Name, $dur)
        } else {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $Files[$i].Name)
        }
    }
    if ($AllowAll) {
        Write-Host "  [A] All of the above"
    }

    $prompt = if ($AllowAll) { "File number (A = all)" } else { "File number" }
    $choice = (Read-Host $prompt).Trim()
    if ($choice -eq "") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return @()
    }
    if ($AllowAll -and $choice -match '^[Aa]$') {
        return @($Files)
    }
    if ($choice -notmatch '^\d+$') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return @()
    }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $Files.Count) {
        Write-Host "Invalid number." -ForegroundColor Red
        return @()
    }
    return @($Files[$idx])
}

function Initialize-Folders {
    if (-not (Test-Path $InputDir)) {
        New-Item -ItemType Directory -Path $InputDir | Out-Null
        Write-Host "Created $InputDir"
    }
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null | Out-Null
}

function Get-VideoFrameRate([string]$path) {
    if (Test-RawYuvFile $path) {
        try { return [double]$script:YuvFps } catch { return $null }
    }
    if (-not (Test-Path $ffprobe)) { return $null }
    try {
        $raw = & $ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nokey=1:noprint_wrappers=1 $path 2>$null
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $raw = $raw.Trim()
        if ($raw -match '^(\d+)\s*/\s*(\d+)$') {
            $den = [double]$Matches[2]
            if ($den -eq 0) { return $null }
            return [double]$Matches[1] / $den
        }
        if ($raw -match '^\d+(\.\d+)?$') { return [double]$raw }
        return $null
    } catch {
        return $null
    }
}

function Get-FpsLadder([double]$srcFps, [bool]$include30Fps) {
    $list = @()
    $rounded = [int][Math]::Round($srcFps)
    if ($srcFps -gt 60.05) {
        $list += [pscustomobject]@{ Fps = 60; Suffix = "-60fps" }
    } else {
        $list += [pscustomobject]@{ Fps = $null; Suffix = "-${rounded}fps" }
    }
    if ($include30Fps -and $srcFps -gt 30.05) {
        $list += [pscustomobject]@{ Fps = 30; Suffix = "-30fps" }
    }
    if ($srcFps -gt 24.05) {
        $list += [pscustomobject]@{ Fps = 24; Suffix = "-24fps" }
    }
    return @($list)
}

function Read-Include30FpsLadder {
    if ($Include30Fps) {
        Write-Host "30 fps ladder: yes (-Include30Fps)" -ForegroundColor Cyan
        return $true
    }

    Write-Host ""
    Write-Host "Sources above 30 fps can also produce a 30 fps version of every resolution."
    $ans = (Read-Host "Generate 30 fps ladder? [Y/N]").Trim()
    if ($ans -match '^[Yy](es)?$') {
        Write-Host "30 fps ladder: yes" -ForegroundColor Cyan
        return $true
    }

    Write-Host "30 fps ladder: skipped" -ForegroundColor Yellow
    return $false
}

function Get-VideoFilter([int]$width, [int]$height, $fps) {
    $vf = "scale=${width}:${height}:flags=lanczos,format=yuv420p"
    if ($null -ne $fps) { $vf += ",fps=$fps" }
    return $vf
}

function Invoke-EncodeLadder {
    $suffixPattern = '[-_](4k|1080p|720p|480p|360p|2160p)(-\d+fps)?$'
    $files = @(Get-InputVideos | Where-Object { $_.BaseName -notmatch $suffixPattern })

    if ($files.Count -eq 0) {
        Write-Host "No source videos found in $InputDir" -ForegroundColor Yellow
        return
    }

    $files = @(Select-InputVideos -Files $files -AllowAll)
    if ($files.Count -eq 0) { return }

    $include30Fps = Read-Include30FpsLadder

    $logPath = Join-Path $OutputDir ("convert_log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
    "Started $(Get-Date -Format o)" | Tee-Object -FilePath $logPath
    "mode:   encode ladder" | Tee-Object -FilePath $logPath -Append
    "30fps:  $(if ($include30Fps) { 'yes' } else { 'no' })" | Tee-Object -FilePath $logPath -Append
    "ffmpeg: $ffmpeg" | Tee-Object -FilePath $logPath -Append
    "input:  $InputDir" | Tee-Object -FilePath $logPath -Append
    "output: $OutputDir" | Tee-Object -FilePath $logPath -Append
    "" | Tee-Object -FilePath $logPath -Append

    $ok = 0
    $skip = 0
    $fail = 0
    $index = 0

    foreach ($file in $files) {
        $index++
        $name = $file.BaseName -replace '[-_](4k|uhd|2160p)(-\d+fps)?$', ''
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $file.BaseName }

        $rawArgs = @(Get-RawVideoInputArgs $file.FullName)
        $srcFps = Get-VideoFrameRate $file.FullName
        if ($null -eq $srcFps) { $srcFps = 24 }
        $fpsLadder = @(Get-FpsLadder $srcFps $include30Fps)

        $jobs = @()
        foreach ($step in $Ladder) {
            foreach ($rate in $fpsLadder) {
                $tag = "{0}{1}" -f $step.Name, $rate.Suffix
                $outPath = Join-Path $OutputDir ("{0}-{1}.mp4" -f $name, $tag)
                if ($Overwrite -or -not (Test-Path $outPath)) {
                    $jobs += [pscustomobject]@{
                        Name   = $tag
                        Width  = $step.Width
                        Height = $step.Height
                        Crf    = $step.Crf
                        Fps    = $rate.Fps
                        Path   = $outPath
                    }
                }
            }
        }

        Write-Host ""
        Write-Host "[$index/$($files.Count)] $($file.Name)  ($([Math]::Round($srcFps, 3)) fps)" -ForegroundColor Cyan

        if ($jobs.Count -eq 0) {
            $msg = "SKIP already exists: ${name}-4k/-1080p-XXfps.mp4"
            Write-Host $msg -ForegroundColor Yellow
            $msg | Tee-Object -FilePath $logPath -Append | Out-Null
            $skip++
            continue
        }
        $ffArgs = @(
            $(if ($Overwrite) { "-y" } else { "-n" }),
            "-hide_banner"
        ) + $rawArgs + @(
            "-i", $file.FullName
        )

        if ($jobs.Count -eq 1) {
            $j = $jobs[0]
            $ffArgs += @(
                "-vf", (Get-VideoFilter $j.Width $j.Height $j.Fps),
                "-map", "0:v:0", "-map", "0:a?",
                "-c:v", "libx265", "-pix_fmt", "yuv420p", "-profile:v", "main",
                "-crf", $j.Crf, "-preset", "medium",
                "-tag:v", "hvc1", "-movflags", "+faststart",
                "-c:a", "copy",
                $j.Path
            )
        } else {
            $labels = @()
            $filters = @()
            for ($i = 0; $i -lt $jobs.Count; $i++) {
                $labels += "s$i"
                $filters += ("[s{0}]{1}[v{0}]" -f $i, (Get-VideoFilter $jobs[$i].Width $jobs[$i].Height $jobs[$i].Fps))
            }
            $split = "[0:v]split={0}{1}" -f $jobs.Count, (($labels | ForEach-Object { "[$_]" }) -join "")
            $ffArgs += @("-filter_complex", ($split + ";" + ($filters -join ";")))
            for ($i = 0; $i -lt $jobs.Count; $i++) {
                $j = $jobs[$i]
                $ffArgs += @(
                    "-map", "[v$i]", "-map", "0:a?",
                    "-c:v", "libx265", "-pix_fmt", "yuv420p", "-profile:v", "main",
                    "-crf", $j.Crf, "-preset", "medium",
                    "-tag:v", "hvc1", "-movflags", "+faststart",
                    "-c:a", "copy",
                    $j.Path
                )
            }
        }

        $msg = "ENCODE $($jobs.Name -join ', ')"
        Write-Host $msg
        $msg | Tee-Object -FilePath $logPath -Append | Out-Null

        & $ffmpeg @ffArgs
        $code = $LASTEXITCODE

        $allOk = $code -eq 0
        foreach ($j in $jobs) {
            if (-not (Test-Path $j.Path)) { $allOk = $false }
        }

        if ($allOk) {
            $msg = "OK $name"
            Write-Host $msg -ForegroundColor Green
            $msg | Tee-Object -FilePath $logPath -Append | Out-Null
            $ok++
        } else {
            $msg = "FAIL $name (ffmpeg exit $code)"
            Write-Host $msg -ForegroundColor Red
            $msg | Tee-Object -FilePath $logPath -Append | Out-Null
            $fail++
        }
    }

    Write-Host ""
    $summary = "Done. ok=$ok skip=$skip fail=$fail  log=$logPath"
    Write-Host $summary -ForegroundColor Cyan
    $summary | Tee-Object -FilePath $logPath -Append | Out-Null
}
