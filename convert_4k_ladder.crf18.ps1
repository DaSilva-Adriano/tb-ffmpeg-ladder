function Get-Crf18ControlName([string]$stem, [string]$resName, [string]$fpsSuffix) {
    return ("{0}-{1}{2}-crf18.mp4" -f $stem, $resName, $fpsSuffix)
}

function Get-Lanczos4kControlName([string]$stem, [string]$resName, [string]$fpsSuffix) {
    return ("{0}-{1}{2}-crf18-lanczos-4k.mp4" -f $stem, $resName, $fpsSuffix)
}

function Invoke-Crf18LanczosControl {
    $files = @(Get-InputVideos | Where-Object {
        $_.BaseName -notmatch 'crf18|lanczos-4k|bicubic-4k'
    })

    if ($files.Count -eq 0) {
        Write-Host "No source videos found in $InputDir" -ForegroundColor Yellow
        return
    }

    Write-Host "CRF 18 control vs production ladder."
    Write-Host "Encodes 1080p + 360p at CRF 18 (Lanczos downscale), then upscales each to 4K with Lanczos CRF 12."
    Write-Host "Compare Nom-360p-24fps-crf18-lanczos-4k.mp4 with a Lanczos upscale of the production 360p CRF 24."
    Write-Host "Native fps is kept; a 24 fps variant is added when the source is above 24 fps. No 30 fps rung."

    $files = @(Select-InputVideos -Files $files -AllowAll)
    if ($files.Count -eq 0) { return }

    $steps = @(
        @{ Name = "1080p"; Width = 1920; Height = 1080 }
        @{ Name = "360p";  Width = 640;  Height = 360 }
    )

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
        $fpsLadder = @(Get-FpsLadder $srcFps $false)

        Write-Host ""
        Write-Host "[$index/$($files.Count)] $($file.Name)  ($([Math]::Round($srcFps, 3)) fps)" -ForegroundColor Cyan

        foreach ($step in $steps) {
            foreach ($rate in $fpsLadder) {
                $lrName = Get-Crf18ControlName $name $step.Name $rate.Suffix
                $upName = Get-Lanczos4kControlName $name $step.Name $rate.Suffix
                $lrPath = Join-Path $OutputDir $lrName
                $upPath = Join-Path $OutputDir $upName

                if (-not $Overwrite -and (Test-Path $lrPath) -and (Test-Path $upPath)) {
                    Write-Host "SKIP already exists: $lrName / $upName" -ForegroundColor Yellow
                    $skip++
                    continue
                }

                $vfDown = Get-VideoFilter $step.Width $step.Height $rate.Fps
                $ffArgs = @(
                    "-y",
                    "-hide_banner"
                ) + $rawArgs + @(
                    "-i", $file.FullName,
                    "-filter_complex", ("[0:v]{0}[lr];[lr]split=2[enc][to4k];[to4k]scale=3840:2160:flags=lanczos,format=yuv420p[up]" -f $vfDown),
                    "-map", "[enc]", "-map", "0:a?",
                    "-c:v:0", "libx265", "-pix_fmt:v:0", "yuv420p", "-profile:v:0", "main",
                    "-crf:v:0", "18", "-preset:v:0", "medium",
                    "-tag:v:0", "hvc1",
                    "-c:a", "copy",
                    $lrPath,
                    "-map", "[up]", "-map", "0:a?",
                    "-c:v:1", "libx265", "-pix_fmt:v:1", "yuv420p", "-profile:v:1", "main",
                    "-crf:v:1", "12", "-preset:v:1", "medium",
                    "-tag:v:1", "hvc1",
                    "-movflags", "+faststart",
                    $upPath
                )

                Write-Host "CRF18 $($step.Name)$($rate.Suffix) + Lanczos 4K"
                & $ffmpeg @ffArgs
                $code = $LASTEXITCODE
                if ($code -eq 0 -and (Test-Path $lrPath) -and (Test-Path $upPath)) {
                    Write-Host "OK $lrName" -ForegroundColor Green
                    Write-Host "OK $upName" -ForegroundColor Green
                    $ok++
                } else {
                    Write-Host "FAIL $lrName (ffmpeg exit $code)" -ForegroundColor Red
                    $fail++
                }
            }
        }
    }

    Write-Host ""
    Write-Host "CRF 18 control done. ok=$ok skip=$skip fail=$fail" -ForegroundColor Cyan
}
