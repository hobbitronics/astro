# Astro Capture Script

This repository contains a single script, [astro.sh](astro.sh), for running an interval capture sequence with a gphoto2-compatible camera.

The script creates a new session folder in your current working directory, so you should run it from wherever you want your photos saved (for example your Pictures folder).

## What It Does

- Prompts for frame count and interval.
- Connects to your camera through gphoto2.
- Shows available camera values for ISO, shutter speed, and aperture.
- Offers optional Live View for manual focusing when the camera exposes it over USB.
- Validates ISO, shutter speed, and aperture input against available camera options.
- Detects a supported image-format config path and selects RAW when the camera exposes that setting.
- Warns if the camera focus mode is not Manual.
- Applies your selected settings.
- Stops immediately with a clear error if any camera setting fails to apply.
- Captures and downloads images into a timestamped folder.
- Writes a session metadata file with selected settings and timestamps.

## Requirements

- Linux system
- `gphoto2` installed
- `ffplay` installed (optional, for Live View)
- Camera connected by USB and recognized by gphoto2
- A memory card for cameras/workflows where downloaded files are required

Install gphoto2 on Debian/Ubuntu:

```bash
sudo apt update
sudo apt install gphoto2
```

## First-Time Setup

From this repository folder:

```bash
chmod +x astro.sh
```

Optional camera check:

```bash
gphoto2 --auto-detect
```

Optional Live View dependency install on Debian/Ubuntu:

```bash
sudo apt install ffmpeg
```

## Supported Models

This script targets gphoto2-compatible cameras and discovers the setting paths exposed by each body.

| Camera                         | Status   | Notes                                                                                                                                                                                                                                                                                                                  |
| ------------------------------ | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Canon EOS 300D / Digital Rebel | Tested   | Uses `/main/settings/...` paths for ISO, shutter speed, aperture, focus mode, and image format. USB Live View, battery level, and capture-target selection are not exposed. The camera may briefly display an exposure without a CF card; downloaded files still depend on what the camera makes available to gphoto2. |
| Newer Canon EOS bodies         | Expected | Uses common `/main/imgsettings/...` and `/main/capturesettings/...` paths when exposed by gphoto2. Live View is offered only when the camera exposes Live View controls.                                                                                                                                               |

If your camera is detected but settings are missing, run:

```bash
gphoto2 --list-config
```

Then compare the exposed paths with the script's supported path list.

## Recommended Usage (Run From Pictures)

If your photos should go under Pictures, start in that directory and run the script by full path:

```bash
cd ~/Pictures
/home/user/autoshoot/astro.sh
```

You can also run from any other parent folder, for example:

```bash
cd ~/photos
/home/user/autoshoot/astro.sh
```

## Output Location

Each run creates a folder named like:

```text
astro_YYYY-MM-DD_HH-MM
```

Example:

```text
~/Pictures/astro_2026-08-09_11-45
```

Inside it, images are saved as:

```text
astro_shot_001.<ext>
astro_shot_002.<ext>
...
```

The folder also includes:

```text
session_metadata.txt
```

This metadata file records selected settings, camera detect info, battery level (if available), and start/finish timestamps.
It also records whether Live View was used.

## Input Notes

- Enter the exact value labels shown in the options list.
  - ISO examples: `Auto`, `800`, `1600`
  - Shutter examples: `1`, `0.5`, `1/30`, `bulb`
  - Aperture examples: `3.5`, `5.6`, `11`
- If you type a value that is not in the displayed options, the script rejects it and asks again.
- Press Enter with no value to use the default shown in brackets.

## Troubleshooting

- "Camera not detected"
  - Reconnect USB cable.
  - Turn camera on.
  - Retry `gphoto2 --auto-detect`.
- "Could not read battery level"
  - Script continues, but monitor battery manually.
- Shutter fires but no image downloads
  - Confirm a memory card is installed and has free space.
  - Some older cameras, including the Canon EOS 300D, may show a brief post-shot review image without producing a downloadable file.
  - The EOS 300D does not expose a gphoto2 capture-target setting, so this script cannot redirect capture storage directly to the computer before download.
- Permission/USB busy issues
  - Close camera apps and file managers that may access the camera.

## Tip

Because the script writes output in the current directory, your workflow is usually:

1. `cd` into your target parent folder (for example `~/Pictures`).
2. Run `/home/user/autoshoot/astro.sh`.
3. Find your capture set in the new `astro_*` subfolder.
