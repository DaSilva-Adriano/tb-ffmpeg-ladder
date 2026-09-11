# tb-ffmpeg-ladder

Private helper scripts for the Travail de Bachelor video ladder.

Keep these next to `ffmpeg.exe` and `ffprobe.exe`, then double-click `convert_4k_ladder.bat`:

- `convert_4k_ladder.bat`
- `convert_4k_ladder.ps1`
- `convert_4k_ladder.helpers.ps1`
- `convert_4k_ladder.encode.ps1`
- `convert_4k_ladder.extend.ps1`
- `convert_4k_ladder.cutout.ps1`
- `convert_4k_ladder.crf18.ps1`

1. Encode ladder: 4K / 1080p / 720p / 480p / 360p to `output\\Nom-1080p.mp4` (libx265, Lanczos, audio copy). For sources above 30 fps the script asks whether to also generate a 30 fps ladder (default no; pass `-Include30Fps` to skip the question).
2. Cut master: lossless copy of a file from `input\\` back into `input\\`
3. Cut output: lossless copy of one or more files from `output\\`. Before the file list: persisted exclusions (`cut_exclusions.txt`) then session must-have terms (typed, not saved). A file is listed only if its name contains every must-have term. Then multi-select (`5`, `20-28`, `1,4,20-22`, `A`). The cut mark is inserted before the resolution tag: `Nom-1080p-24fps.mp4` → `Nom_cut_00_01_15_00_03_00-1080p-24fps.mp4`
4. Extend output: copy-concat loop to 5:30. Same listing flow with `extend_exclusions.txt` and session must-have terms. Mark before resolution: `Nom_extended-1080p-24fps.mp4`
5. Upscale to 4K: bicubic scale to 3840x2160, libx265 CRF 12, audio copy. Lists any video from `output\\` then `input\\` (name does not matter). Writes `Nom-bicubic-4k-24fps.mp4`
6. CRF 18 control: pick a master in `input\\`, encode **1080p + 360p at CRF 18** (Lanczos downscale), force **24 fps**, then Lanczos-upscale each to 4K at CRF 12. Writes `Nom-360p-24fps-crf18.mp4` and `Nom-360p-24fps-crf18-lanczos-4k.mp4` (same for 1080p). No native-fps or 30 fps variants.
7. Quit
