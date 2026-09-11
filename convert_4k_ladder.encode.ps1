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

function Get-Bicubic4kOutputName([string]$baseName) {
    $stem = $baseName -replace '[-_]720p(-\d+fps)?$', ''
    if ([string]::IsNullOrWhiteSpace($stem)) { $stem = $baseName }
    $fpsTag = "24"
    if ($baseName -match '(\d+)fps$') {
        $fpsTag = $Matches[1]
    }
    return ("{0}-bicubic-4k-{1}fps.mp4" -f $stem, $fpsTag)
}

function Invoke-Upscale720pBicubic4k {
    $pattern = '[-_]720p(-\d+fps)?$'
    $fromOutput = @(Get-OutputVideos | Where-Object {
        $_.BaseName -match $pattern -and $_.BaseName -notmatch 'bicubic-4k'
    })
    $fromInput = @(Get-InputVideos | Where-Object {
        $_.BaseName -match $pattern -and $_.BaseName -notmatch 'bicubic-4k'
    })

    $files = @()
    $seen = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @($fromOutput + $fromInput)) {
        if ($seen.Add($f.FullName)) { $files += $f }
    }

    if ($files.Count -eq 0) {
        Write-Host "No 720p videos found (name must end with -720p or -720p-XXfps)." -ForegroundColor Yellow
        Write-Host "Looked in: $OutputDir" -ForegroundColor Yellow
        Write-Host "       and: $InputDir" -ForegroundColor Yellow
        return
    }

    Write-Host "Bicubic upscale 720p -> 4K (3840x2160), libx265 CRF 12, audio copy."
    Write-Host "Source frame rate is kept. Output: Nom-bicubic-4k-XXfps.mp4"

    Write-Host ""
    Write-Host "720p sources:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $files.Count; $i++) {
        $dur = Get-DurationString $files[$i].FullName
        $where = if ($files[$i].DirectoryName -eq $OutputDir) { "output" } else { "input" }
        if ($dur) {
            Write-Host ("  [{0}] {1}  ({2}, {3})" -f ($i + 1), $files[$i].Name, $dur, $where)
        } else {
            Write-Host ("  [{0}] {1}  ({2})" -f ($i + 1), $files[$i].Name, $where)
        }
    }
    Write-Host "  [A] All of the above"
    $choice = (Read-Host "File(s): 5  or  20-28  or  1,4,20-22  or  A").Trim()
    if ($choice -eq "") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }
    $indexes = @(ConvertTo-SelectedIndexes $choice $files.Count)
    if ($indexes.Count -eq 0) {
        Write-Host "No valid file numbers." -ForegroundColor Yellow
        return
    }
    $picked = @($indexes | ForEach-Object { $files[$_] })

    $ok = 0
    $skip = 0
    $fail = 0
    $index = 0
    foreach ($src in $picked) {
        $index++
        $outName = Get-Bicubic4kOutputName $src.BaseName
        if ($src.BaseName -notmatch '(\d+)fps$') {
            $srcFps = Get-VideoFrameRate $src.FullName
            if ($null -eq $srcFps) { $srcFps = 24 }
            $stem = $src.BaseName -replace '[-_]720p(-\d+fps)?$', ''
            if ([string]::IsNullOrWhiteSpace($stem)) { $stem = $src.BaseName }
            $outName = "{0}-bicubic-4k-{1}fps.mp4" -f $stem, [int][Math]::Round($srcFps)
        }
        $outPath = Join-Path $OutputDir $outName

        if (-not $Overwrite -and (Test-Path $outPath)) {
            Write-Host "SKIP already exists: $outName" -ForegroundColor Yellow
            $skip++
            continue
        }

        Write-Host ""
        Write-Host "[$index/$($picked.Count)] UPSCALE $($src.Name) -> $outName" -ForegroundColor Cyan

        $rawArgs = @(Get-RawVideoInputArgs $src.FullName)
        $ffArgs = @(
            $(if ($Overwrite) { "-y" } else { "-n" }),
            "-hide_banner"
        ) + $rawArgs + @(
            "-i", $src.FullName,
            "-vf", "scale=3840:2160:flags=bicubic,format=yuv420p",
            "-map", "0:v:0", "-map", "0:a?",
            "-c:v", "libx265", "-pix_fmt", "yuv420p", "-profile:v", "main",
            "-crf", "12", "-preset", "medium",
            "-tag:v", "hvc1", "-movflags", "+faststart",
            "-c:a", "copy",
            $outPath
        )

        & $ffmpeg @ffArgs
        if ($LASTEXITCODE -eq 0 -and (Test-Path $outPath)) {
            Write-Host "OK $outPath" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "FAIL $($src.Name) (ffmpeg exit $LASTEXITCODE)" -ForegroundColor Red
            $fail++
        }
    }

    Write-Host ""
    Write-Host "Upscale done. ok=$ok skip=$skip fail=$fail" -ForegroundColor Cyan
}
