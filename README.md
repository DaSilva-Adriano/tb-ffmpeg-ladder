# tb-ffmpeg-ladder

Private helper scripts for the Travail de Bachelor video ladder.

Put `convert_4k_ladder.bat`, `convert_4k_ladder.ps1`, `ffmpeg.exe` and `ffprobe.exe` in the same folder. Double-click the `.bat`.

1. Encode ladder: 4K / 1080p / 720p / 480p / 360p to `output\\Nom-1080p.mp4` (libx265, Lanczos, audio copy). For sources above 30 fps the script asks whether to also generate a 30 fps ladder (default no; pass `-Include30Fps` to skip the question).
2. Cut master: lossless copy of a file from `input\\` back into `input\\`
3. Cut output: lossless copy of one or more files from `output\\`. Multi-select (`5`, `20-28`, `1,4,20-22`, `A`) and a separate exclusion list (`cut_exclusions.txt`). The cut mark is inserted before the resolution tag, same idea as extend: `Nom-1080p-24fps.mp4` → `Nom_cut_00_01_15_00_03_00-1080p-24fps.mp4`
4. Extend output: copy-concat loop to 5:30. Multi-select and `extend_exclusions.txt`. Mark before resolution: `Nom_extended-1080p-24fps.mp4`
