function Get-ExclusionFilePath([string]$fileName) {
    return (Join-Path $root $fileName)
}

function Get-ExclusionTerms([string]$fileName) {
    $path = Get-ExclusionFilePath $fileName
    $found = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path $path)) { return @() }
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        if (-not $found.Contains($t)) { $found.Add($t) }
    }
    return $found.ToArray()
}

function Save-ExclusionTerms {
    param(
        [string]$FileName,
        [string[]]$Terms,
        [string]$Purpose = "this mode"
    )
    $path = Get-ExclusionFilePath $FileName
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("# One substring per line. Case-insensitive.")
    [void]$lines.Add("# Files whose name contains a term are hidden from $Purpose.")
    [void]$lines.Add("# Example: -vsr")
    [void]$lines.Add("")
    $seen = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
    foreach ($term in @($Terms)) {
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

function Edit-ExclusionTerms {
    param(
        [string]$FileName,
        [string[]]$Terms,
        [string]$Purpose = "this mode"
    )
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($t in @($Terms)) {
        if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$list.Add($t.Trim()) }
    }
    Write-Host ""
    Write-Host ("Exclusion list for {0} ({1})" -f $Purpose, $FileName) -ForegroundColor Cyan
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
        Save-ExclusionTerms -FileName $FileName -Terms $list.ToArray() -Purpose $Purpose
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

function Get-LadderTaggedName([string]$baseName, [string]$mark, [string]$extension) {
    if ($baseName -match '^(.*)[-_](4k|1080p|720p|480p|360p|2160p)(-\d+fps)?$') {
        return ("{0}{1}-{2}{3}{4}" -f $Matches[1], $mark, $Matches[2], $Matches[3], $extension)
    }
    return ("{0}{1}{2}" -f $baseName, $mark, $extension)
}

function Get-ExtendedFileName([string]$baseName, [string]$extension) {
    return (Get-LadderTaggedName $baseName "_extended" $extension)
}

function Get-CutOutputFileName([string]$baseName, [string]$extension, [string]$start, [string]$end) {
    $mark = ("_cut_{0}_{1}" -f (ConvertTo-FileSafeStamp $start), (ConvertTo-FileSafeStamp $end))
    return (Get-LadderTaggedName $baseName $mark $extension)
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
    $terms = @(Edit-ExclusionTerms -FileName "extend_exclusions.txt" -Terms (Get-ExclusionTerms "extend_exclusions.txt") -Purpose "Extend")
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
