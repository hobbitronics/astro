# Astro Capture Script

This repository contains a single script, [astro.sh](astro.sh), for running an interval capture sequence with a gphoto2-compatible camera.

The script creates a new session folder in your current working directory, so you should run it from wherever you want your photos saved (for example your Pictures folder).

## What It Does

- Prompts for frame count and interval.
- Connects to your camera through gphoto2.
- Shows available camera values for ISO, shutter speed, and aperture.
- Applies your selected settings.
- Captures and downloads images into a timestamped folder.

## Requirements

- Linux system
- `gphoto2` installed
- Camera connected by USB and recognized by gphoto2

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

## Input Notes

- Enter the exact value labels shown in the options list.
  - ISO examples: `Auto`, `800`, `1600`
  - Shutter examples: `1`, `0.5`, `1/30`, `bulb`
  - Aperture examples: `3.5`, `5.6`, `11`
- Press Enter with no value to use the default shown in brackets.

## Troubleshooting

- "Camera not detected"
  - Reconnect USB cable.
  - Turn camera on.
  - Retry `gphoto2 --auto-detect`.
- "Could not read battery level"
  - Script continues, but monitor battery manually.
- Permission/USB busy issues
  - Close camera apps and file managers that may access the camera.

## Tip

Because the script writes output in the current directory, your workflow is usually:

1. `cd` into your target parent folder (for example `~/Pictures`).
2. Run `/home/user/autoshoot/astro.sh`.
3. Find your capture set in the new `astro_*` subfolder.
