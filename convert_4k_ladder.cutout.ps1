function Invoke-CutOutputs {
    $all = @(Get-OutputVideos | Where-Object { $_.BaseName -notmatch '_cut_|_cut-' })
    if ($all.Count -eq 0) {
        Write-Host "No videos found in $OutputDir" -ForegroundColor Yellow
        return
    }

    Write-Host "Cut files in output. Original is kept."
    Write-Host "The _cut_start_end mark is inserted before the resolution tag."
    Write-Host "Example: Nom-1080p-24fps.mp4 -> Nom_cut_00_01_15_00_03_00-1080p-24fps.mp4"
    $terms = @(Edit-ExclusionTerms -FileName "cut_exclusions.txt" -Terms (Get-ExclusionTerms "cut_exclusions.txt") -Purpose "Cut output")
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

    Write-Host ""
    Write-Host ("Selected {0} file(s). Same start/end applied to each." -f $picked.Count) -ForegroundColor Cyan
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

    $ok = 0
    $skip = 0
    $fail = 0
    foreach ($src in $picked) {
        $outPath = Join-Path $OutputDir (Get-CutOutputFileName $src.BaseName $src.Extension $start $end)
        if ([string]::Equals($outPath, $src.FullName, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "SKIP $($src.Name) (would overwrite source)" -ForegroundColor Yellow
            $skip++
            continue
        }
        if (-not $Overwrite -and (Test-Path $outPath)) {
            Write-Host "SKIP already exists: $(Split-Path $outPath -Leaf)" -ForegroundColor Yellow
            $skip++
            continue
        }

        Write-Host ""
        Write-Host ("CUT {0}  {1} -> {2}  => {3}" -f $src.Name, $start, $end, (Split-Path $outPath -Leaf)) -ForegroundColor Cyan

        $ffArgs = @(
            "-y",
            "-hide_banner",
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
        if ($LASTEXITCODE -eq 0 -and (Test-Path $outPath)) {
            $newDur = Get-DurationString $outPath
            if ($newDur) {
                Write-Host "OK $outPath  ($newDur)" -ForegroundColor Green
            } else {
                Write-Host "OK $outPath" -ForegroundColor Green
            }
            $ok++
        } else {
            Write-Host "FAIL $($src.Name) (ffmpeg exit $LASTEXITCODE)" -ForegroundColor Red
            $fail++
        }
    }

    Write-Host ""
    Write-Host "Cut output done. ok=$ok skip=$skip fail=$fail" -ForegroundColor Cyan
}
