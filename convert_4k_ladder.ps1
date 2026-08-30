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
        [switch]$AllowAll
    )

    if ($Files.Count -eq 0) { return @() }

    Write-Host ""
    Write-Host "Files in input:" -ForegroundColor Cyan
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

function Invoke-EncodeLadder {
    $suffixPattern = '[-_](4k|1080p|720p|480p|360p|2160p)$'
    $files = @(Get-InputVideos | Where-Object { $_.BaseName -notmatch $suffixPattern })

    if ($files.Count -eq 0) {
        Write-Host "No source videos found in $InputDir" -ForegroundColor Yellow
        return
    }

    $files = @(Select-InputVideos -Files $files -AllowAll)
    if ($files.Count -eq 0) { return }

    $logPath = Join-Path $OutputDir ("convert_log_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
    "Started $(Get-Date -Format o)" | Tee-Object -FilePath $logPath
    "mode:   encode ladder" | Tee-Object -FilePath $logPath -Append
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
        $name = $file.BaseName -replace '[-_](4k|uhd|2160p)$', ''
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $file.BaseName }

        $jobs = @()
        foreach ($step in $Ladder) {
            $outPath = Join-Path $OutputDir ("{0}-{1}.mp4" -f $name, $step.Name)
            if ($Overwrite -or -not (Test-Path $outPath)) {
                $jobs += [pscustomobject]@{
                    Name   = $step.Name
                    Width  = $step.Width
                    Height = $step.Height
                    Crf    = $step.Crf
                    Path   = $outPath
                }
            }
        }

        Write-Host ""
        Write-Host "[$index/$($files.Count)] $($file.Name)" -ForegroundColor Cyan

        if ($jobs.Count -eq 0) {
            $msg = "SKIP already exists: ${name}-4k/-1080p/-720p/-480p/-360p.mp4"
            Write-Host $msg -ForegroundColor Yellow
            $msg | Tee-Object -FilePath $logPath -Append | Out-Null
            $skip++
            continue
        }

        $rawArgs = @(Get-RawVideoInputArgs $file.FullName)
        $ffArgs = @(
            $(if ($Overwrite) { "-y" } else { "-n" }),
            "-hide_banner"
        ) + $rawArgs + @(
            "-i", $file.FullName
        )

        if ($jobs.Count -eq 1) {
            $j = $jobs[0]
            $ffArgs += @(
                "-vf", ("scale={0}:{1}:flags=lanczos,format=yuv420p" -f $j.Width, $j.Height),
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
                $filters += ("[s{0}]scale={1}:{2}:flags=lanczos,format=yuv420p[v{0}]" -f $i, $jobs[$i].Width, $jobs[$i].Height)
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

function Invoke-CutMaster {
    $files = @(Get-InputVideos)
    if ($files.Count -eq 0) {
        Write-Host "No videos found in $InputDir" -ForegroundColor Yellow
        return
    }

    $picked = @(Select-InputVideos -Files $files)
    if ($picked.Count -eq 0) { return }
    $src = $picked[0]
    Write-Host "Selected: $($src.Name)" -ForegroundColor Cyan
    Write-Host "Times: 00:01:30  or  90  or  1:30"
    Write-Host "Lossless copy: cut may start on the nearest keyframe (usually < 2s)."

    do {
        $start = (Read-Host "Start").Trim()
        if (-not (Test-TimeStamp $start)) {
            Write-Host "Bad start time. Examples: 00:01:15 or 75" -ForegroundColor Yellow
        }
    } while (-not (Test-TimeStamp $start))

    do {
        $end = (Read-Host "End").Trim()
        if (-not (Test-TimeStamp $end)) {
            Write-Host "Bad end time. Examples: 00:03:00 or 180" -ForegroundColor Yellow
        }
    } while (-not (Test-TimeStamp $end))

    $rawArgs = @(Get-RawVideoInputArgs $src.FullName)
    $stem = $src.BaseName -replace '[-_](4k|uhd|2160p)$', ''
    if ([string]::IsNullOrWhiteSpace($stem)) { $stem = $src.BaseName }
    $cutExt = ".mkv"
    if (Test-RawYuvFile $src.FullName) { $cutExt = ".yuv" }
    if (Test-Y4mFile $src.FullName) { $cutExt = ".y4m" }
    $defaultName = "{0}_cut_{1}_{2}{3}" -f $stem, (ConvertTo-FileSafeStamp $start), (ConvertTo-FileSafeStamp $end), $cutExt

    Write-Host "Saved into input as: $defaultName"
    $custom = (Read-Host "Output name [Enter = default]").Trim()
    if ($custom) {
        if ($custom -notmatch '\.[A-Za-z0-9]+$') { $custom += $cutExt }
        $outPath = Join-Path $InputDir $custom
    } else {
        $outPath = Join-Path $InputDir $defaultName
    }

    if ([string]::Equals($outPath, $src.FullName, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Refusing to overwrite the source file. Choose another name." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "CUT $($src.Name)  $start -> $end" -ForegroundColor Cyan

    $ffArgs = @(
        "-y",
        "-hide_banner"
    ) + $rawArgs + @(
        "-ss", $start,
        "-to", $end,
        "-i", $src.FullName,
        "-map", "0:v?",
        "-map", "0:a?",
        "-map", "0:s?",
        "-dn",
        "-ignore_unknown",
        "-c", "copy",
        "-avoid_negative_ts", "make_zero",
        $outPath
    )

    & $ffmpeg @ffArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outPath)) {
        Write-Host "CUT FAILED" -ForegroundColor Red
        return
    }

    Write-Host "Saved in input: $outPath" -ForegroundColor Green
}

function Get-ExtendedFileName([string]$baseName, [string]$extension) {
    if ($baseName -match '^(.*)[-_](4k|1080p|720p|480p|360p|2160p)$') {
        return ("{0}_extended-{1}{2}" -f $Matches[1], $Matches[2], $extension)
    }
    return ("{0}_extended{1}" -f $baseName, $extension)
}

function Invoke-ExtendShortOutputs {
    if (-not (Test-Path $ffprobe)) {
        Write-Host "ffprobe.exe is required for this option. Put it next to ffmpeg.exe." -ForegroundColor Red
        Write-Host "Expected: $ffprobe"
        return
    }

    $all = @(Get-OutputVideos | Where-Object { $_.BaseName -notmatch '_extended-|_extended$|_5m30$' })
    if ($all.Count -eq 0) {
        Write-Host "No videos found in $OutputDir" -ForegroundColor Yellow
        return
    }

    $short = @()
    foreach ($f in $all) {
        $sec = Get-DurationSeconds $f.FullName
        if ($null -eq $sec) { continue }
        if ($sec + 0.05 -lt $TargetExtendSeconds) {
            $short += [pscustomobject]@{
                File = $f
                Seconds = $sec
                Display = Get-DurationString $f.FullName
                Loops = [Math]::Max(2, [int][Math]::Ceiling($TargetExtendSeconds / $sec))
            }
        }
    }

    if ($short.Count -eq 0) {
        Write-Host "Every output is already >= $TargetExtendStamp." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Outputs shorter than $TargetExtendStamp :" -ForegroundColor Cyan
    for ($i = 0; $i -lt $short.Count; $i++) {
        $item = $short[$i]
        Write-Host ("  [{0}] {1}  ({2} -> {3}x copy-concat)" -f ($i + 1), $item.File.Name, $item.Display, $item.Loops)
    }
    Write-Host "  [A] All of the above"

    $choice = (Read-Host "File number, A for all, Enter to cancel").Trim()
    if ($choice -eq "") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    $selected = @()
    if ($choice -match '^[Aa]$') {
        $selected = $short
    } elseif ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -lt 0 -or $idx -ge $short.Count) {
            Write-Host "Invalid number." -ForegroundColor Red
            return
        }
        $selected = @($short[$idx])
    } else {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    $ok = 0
    $fail = 0
    foreach ($item in $selected) {
        $src = $item.File
        $outPath = Join-Path $OutputDir (Get-ExtendedFileName $src.BaseName $src.Extension)
        if (-not $Overwrite -and (Test-Path $outPath)) {
            Write-Host "SKIP already exists: $(Split-Path $outPath -Leaf)" -ForegroundColor Yellow
            continue
        }
        $listPath = Join-Path $OutputDir ("concat_{0}.txt" -f $src.BaseName)

        $posix = ConvertTo-ConcatPath $src.FullName
        $lines = @()
        for ($n = 0; $n -lt $item.Loops; $n++) {
            $lines += "file '$posix'"
        }
        Set-Content -LiteralPath $listPath -Value $lines -Encoding ascii

        Write-Host ""
        Write-Host ("EXTEND {0}  {1} x{2}  -> {3}" -f $src.Name, $item.Display, $item.Loops, (Split-Path $outPath -Leaf)) -ForegroundColor Cyan

        $ffArgs = @(
            "-y",
            "-hide_banner",
            "-f", "concat",
            "-safe", "0",
            "-i", $listPath,
            "-c", "copy",
            "-t", $TargetExtendStamp,
            "-avoid_negative_ts", "make_zero",
            $outPath
        )

        & $ffmpeg @ffArgs
        $code = $LASTEXITCODE
        Remove-Item -LiteralPath $listPath -ErrorAction SilentlyContinue

        if ($code -eq 0 -and (Test-Path $outPath)) {
            $newDur = Get-DurationString $outPath
            Write-Host "OK $outPath  ($newDur)" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "FAIL $($src.Name) (ffmpeg exit $code)" -ForegroundColor Red
            $fail++
        }
    }

    Write-Host ""
    Write-Host "Extend done. ok=$ok fail=$fail" -ForegroundColor Cyan
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
    Write-Host " 2) Cut master      (lossless, start / end)"
    Write-Host " 3) Extend output   (copy-concat loop to 5:30)"
    Write-Host " 4) Quit"
    Write-Host "==============================" -ForegroundColor Cyan
    $sel = (Read-Host "Choice").Trim()

    switch ($sel) {
        "1" { Invoke-EncodeLadder }
        "2" { Invoke-CutMaster }
        "3" { Invoke-ExtendShortOutputs }
        "4" { break }
        "q" { break }
        "Q" { break }
        default { Write-Host "Choose 1, 2, 3 or 4." -ForegroundColor Yellow }
    }

    if ($sel -eq "4" -or $sel -eq "q" -or $sel -eq "Q") { break }
}

exit 0
