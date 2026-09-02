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

function Get-FpsLadder([double]$srcFps) {
    $list = @()
    $rounded = [int][Math]::Round($srcFps)
    if ($srcFps -gt 60.05) {
        $list += [pscustomobject]@{ Fps = 60; Suffix = "-60fps" }
    } else {
        $list += [pscustomobject]@{ Fps = $null; Suffix = "-${rounded}fps" }
    }
    if ($srcFps -gt 30.05) {
        $list += [pscustomobject]@{ Fps = 30; Suffix = "-30fps" }
    }
    if ($srcFps -gt 24.05) {
        $list += [pscustomobject]@{ Fps = 24; Suffix = "-24fps" }
    }
    return @($list)
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
        $name = $file.BaseName -replace '[-_](4k|uhd|2160p)(-\d+fps)?$', ''
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $file.BaseName }

        $rawArgs = @(Get-RawVideoInputArgs $file.FullName)
        $srcFps = Get-VideoFrameRate $file.FullName
        if ($null -eq $srcFps) { $srcFps = 24 }
        $fpsLadder = @(Get-FpsLadder $srcFps)

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

function Get-ExclusionFilePath {
    return (Join-Path $root "extend_exclusions.txt")
}

function Get-ExclusionTerms {
    $path = Get-ExclusionFilePath
    $found = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path $path)) { return @() }
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        if (-not $found.Contains($t)) { $found.Add($t) }
    }
    return $found.ToArray()
}

function Save-ExclusionTerms([string[]]$terms) {
    $path = Get-ExclusionFilePath
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("# One substring per line. Case-insensitive.")
    [void]$lines.Add("# Files whose name contains a term are hidden from Extend.")
    [void]$lines.Add("# Example: -vsr")
    [void]$lines.Add("")
    $seen = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
    foreach ($term in @($terms)) {
        if ([string]::IsNullOrWhiteSpace($term)) { continue }
        $clean = $term.Trim()
        if ($seen.Add($clean)) { [void]$lines.Add($clean) }
    }
    [IO.File]::WriteAllLines($path, $lines.ToArray())
    Write-Host "Saved exclusions: $path" -ForegroundColor Green
}

function Test-NameExcluded([string]$name, [string[]]$terms) {
    foreach ($term in $terms) {
        if ([string]::IsNullOrWhiteSpace($term)) { continue }
        if ($name.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Edit-ExclusionTerms([string[]]$terms) {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($t in @($terms)) {
        if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$list.Add($t.Trim()) }
    }
    Write-Host ""
    if ($list.Count -eq 0) {
        Write-Host "No exclusion file yet. None applied."
    } else {
        Write-Host "Current exclusions:" -ForegroundColor Cyan
        foreach ($t in $list) { Write-Host "  $t" }
    }
    Write-Host "Add a name substring to hide (e.g. -vsr). Empty line = done."
    while ($true) {
        $add = (Read-Host "Exclusion").Trim()
        if ($add -eq "") { break }
        $exists = $false
        foreach ($t in $list) {
            if ($t.Equals($add, [System.StringComparison]::OrdinalIgnoreCase)) { $exists = $true }
        }
        if ($exists) {
            Write-Host "Already listed: $add" -ForegroundColor Yellow
            continue
        }
        [void]$list.Add($add)
        Write-Host "Added: $add"
    }
    if ($list.Count -gt 0) {
        Save-ExclusionTerms $list.ToArray()
    }
    return $list.ToArray()
}

function ConvertTo-SelectedIndexes([string]$choice, [int]$count) {
    if ($choice -match '^[Aa]$') {
        if ($count -le 0) { return @() }
        return @(0..($count - 1))
    }
    $found = New-Object System.Collections.Generic.List[int]
    foreach ($part in @($choice -split '[,; ]+' | Where-Object { $_ -ne "" })) {
        if ($part -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]
            $b = [int]$Matches[2]
            if ($a -gt $b) { $tmp = $a; $a = $b; $b = $tmp }
            for ($n = $a; $n -le $b; $n++) {
                if ($n -lt 1 -or $n -gt $count) {
                    Write-Host "Out of range: $n" -ForegroundColor Yellow
                    continue
                }
                $found.Add($n - 1)
            }
        } elseif ($part -match '^\d+$') {
            $n = [int]$part
            if ($n -lt 1 -or $n -gt $count) {
                Write-Host "Out of range: $n" -ForegroundColor Yellow
                continue
            }
            $found.Add($n - 1)
        } else {
            Write-Host "Ignored: $part" -ForegroundColor Yellow
        }
    }
    return @($found | Select-Object -Unique | Sort-Object)
}

function Get-ExtendedFileName([string]$baseName, [string]$extension) {
    if ($baseName -match '^(.*)[-_](4k|1080p|720p|480p|360p|2160p)(-\d+fps)?$') {
        return ("{0}_extended-{1}{2}{3}" -f $Matches[1], $Matches[2], $Matches[3], $extension)
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

    Write-Host "Extend files shorter than $TargetExtendStamp. Original is kept."
    $terms = @(Edit-ExclusionTerms (Get-ExclusionTerms))
    $visible = @($all | Where-Object { -not (Test-NameExcluded $_.Name $terms) })
    if ($visible.Count -eq 0) {
        Write-Host "No files left after exclusions." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Files in output:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $visible.Count; $i++) {
        $dur = Get-DurationString $visible[$i].FullName
        if ($dur) {
            Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $visible[$i].Name, $dur)
        } else {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $visible[$i].Name)
        }
    }
    Write-Host "  [A] All of the above"
    $choice = (Read-Host "File(s): 5  or  20-28  or  1,4,20-22  or  A").Trim()
    if ($choice -eq "") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }
    $indexes = @(ConvertTo-SelectedIndexes $choice $visible.Count)
    if ($indexes.Count -eq 0) {
        Write-Host "No valid file numbers." -ForegroundColor Yellow
        return
    }
    $picked = @($indexes | ForEach-Object { $visible[$_] })

    $selected = @()
    foreach ($f in $picked) {
        $sec = Get-DurationSeconds $f.FullName
        if ($null -eq $sec -or $sec -le 0) {
            Write-Host "SKIP $($f.Name) (duration unknown)" -ForegroundColor Yellow
            continue
        }
        if ($sec + 0.05 -ge $TargetExtendSeconds) {
            Write-Host "SKIP $($f.Name) (already $(Get-DurationString $f.FullName))" -ForegroundColor Yellow
            continue
        }
        $selected += [pscustomobject]@{
            File = $f
            Seconds = $sec
            Display = Get-DurationString $f.FullName
            Loops = [Math]::Max(2, [int][Math]::Ceiling($TargetExtendSeconds / $sec))
        }
    }

    if ($selected.Count -eq 0) {
        Write-Host "Nothing to extend." -ForegroundColor Yellow
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
