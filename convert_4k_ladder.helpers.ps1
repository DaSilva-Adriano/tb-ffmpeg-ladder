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
