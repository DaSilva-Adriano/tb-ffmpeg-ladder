# tb-ffmpeg-ladder

Private helper scripts for the Travail de Bachelor video ladder.

Put `convert_4k_ladder.bat`, `convert_4k_ladder.ps1`, `ffmpeg.exe` and `ffprobe.exe` in the same folder. Double-click the `.bat`.

1. Encode ladder: 4K / 1080p / 720p / 480p / 360p to `output\\Nom-1080p.mp4` (libx265, Lanczos, audio copy)
2. Cut master: lossless copy into `input\\`
3. Extend output: copy-concat loop to 5:30
