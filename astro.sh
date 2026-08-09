#!/bin/bash

MONITOR_STOPPED=0

restore_volume_monitor() {
    if [ "$MONITOR_STOPPED" -eq 1 ]; then
        systemctl --user start gvfs-gphoto2-volume-monitor.service 2>/dev/null
        MONITOR_STOPPED=0
    fi
}

trap restore_volume_monitor EXIT

RUN_STARTED_AT=$(date -Iseconds)

trim_whitespace() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

get_config_choices() {
    local config_path="$1"
    local fallback_choices="$2"
    local choices

    choices=$(gphoto2 --get-config "$config_path" 2>/dev/null | awk '
        /^Choice:/ {
            sub(/^Choice:[[:space:]]+[0-9]+[[:space:]]+/, "")
            if (choices != "") choices = choices ", "
            choices = choices $0
        }
        END {
            if (choices != "") print choices
        }
    ')

    if [ -n "$choices" ]; then
        echo "$choices"
    else
        echo "$fallback_choices"
    fi
}

get_config_current_value() {
    local config_path="$1"

    gphoto2 --get-config "$config_path" 2>/dev/null | awk -F': ' '/^Current: / { print $2; exit }'
}

is_valid_choice() {
    local value="$1"
    local options_csv="$2"
    local option

    IFS=',' read -r -a options <<< "$options_csv"
    for option in "${options[@]}"; do
        option=$(trim_whitespace "$option")
        if [ "$value" = "$option" ]; then
            return 0
        fi
    done

    return 1
}

prompt_for_valid_choice() {
    local label="$1"
    local default_value="$2"
    local options_csv="$3"
    local output_var="$4"
    local input

    while true; do
        read -p "$label [$default_value] (enter one of the listed values): " input
        input=${input:-$default_value}

        if is_valid_choice "$input" "$options_csv"; then
            printf -v "$output_var" '%s' "$input"
            return 0
        fi

        echo "❌ ERROR: '$input' is not in the available options."
        echo "Please choose one of: $options_csv"
    done
}

set_camera_config_or_fail() {
    local config_path="$1"
    local value="$2"
    local label="$3"

    if ! gphoto2 --set-config "${config_path}=${value}" > /dev/null 2>&1; then
        echo "❌ ERROR: Failed to set $label to '$value'."
        return 1
    fi

    return 0
}

find_first_config_path() {
    local path

    for path in "$@"; do
        if gphoto2 --get-config "$path" > /dev/null 2>&1; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

choose_image_format() {
    local options_csv="$1"
    local option

    IFS=',' read -r -a options <<< "$options_csv"

    for option in "${options[@]}"; do
        option=$(trim_whitespace "$option")
        if [ "$option" = "RAW" ]; then
            echo "$option"
            return 0
        fi
    done

    return 1
}

print_capture_settings() {
    echo ""
    echo "Capture settings:"
    echo "  Frames:       $TOTAL_FRAMES"
    echo "  Interval:     ${INTERVAL}s"

    if [ -n "$ISO" ]; then
        echo "  ISO:          $ISO"
        echo "  Shutter:      $SHUTTER_SPEED"
        echo "  Aperture:     $APERTURE"
    fi

    echo ""
}

check_camera_connection() {
    echo "Checking camera connection..."
    CAMERA_DETECT_INFO=$(gphoto2 --auto-detect 2>/dev/null)
    if ! echo "$CAMERA_DETECT_INFO" | grep -q "usb"; then
        echo "❌ ERROR: Camera not detected! Check your USB cable and power switch."
        exit 1
    fi

    CAMERA_MODEL_LINE=$(echo "$CAMERA_DETECT_INFO" | awk '/usb:/{print; exit}')
    echo "✓ Camera detected successfully."
}

check_focus_mode() {
    FOCUS_MODE=$(get_config_current_value "/main/capturesettings/focusmode")
    if [ -n "$FOCUS_MODE" ]; then
        if [ "$FOCUS_MODE" = "Manual" ]; then
            echo "✓ Focus mode is Manual."
        else
            echo "⚠️ WARNING: Focus mode is '$FOCUS_MODE'. Switch the lens/camera to Manual focus for astrophotography."
        fi
    fi
}

check_battery_level() {
    echo "Checking battery level..."
    BATTERY_INFO=$(gphoto2 --get-config /main/status/batterylevel 2>/dev/null)
    BATTERY_VAL=$(echo "$BATTERY_INFO" | grep "Current:" | awk '{print $2}')

    if [ -z "$BATTERY_VAL" ]; then
        echo "⚠️ WARNING: Could not read battery level. Proceeding with caution."
        return 0
    fi

    echo "✓ Battery level is at: $BATTERY_VAL"

    if [[ "$BATTERY_VAL" =~ ^[0-9]+$ ]] && [ "$BATTERY_VAL" -lt 20 ]; then
        echo "❌ ERROR: Battery is too low ($BATTERY_VAL%). Recharge before starting."
        exit 1
    fi
}

load_camera_options() {
    SHUTTER_OPTIONS=$(get_config_choices "/main/capturesettings/shutterspeed" "bulb, 1, 1/60, 1/125, 1/250")
    APERTURE_OPTIONS=$(get_config_choices "/main/capturesettings/aperture" "3.5, 5.6, 8, 11, 16")
    ISO_OPTIONS=$(get_config_choices "/main/imgsettings/iso" "100, 200, 400, 800, 1600")
    IMAGE_FORMAT_PATH=$(find_first_config_path "/main/imgsettings/imageformat" "/main/imgsettings/imageformatsd" "/main/imgsettings/imgformat")

    if [ -z "$IMAGE_FORMAT_PATH" ]; then
        echo "❌ ERROR: Could not find a supported image format config path on this camera."
        exit 1
    fi

    IMAGE_FORMAT_OPTIONS=$(get_config_choices "$IMAGE_FORMAT_PATH" "RAW, RAW + L, L")
    IMAGE_FORMAT=$(choose_image_format "$IMAGE_FORMAT_OPTIONS")

    if [ -z "$IMAGE_FORMAT" ]; then
        echo "❌ ERROR: RAW is not available in image format options for $IMAGE_FORMAT_PATH."
        echo "Available image format options: $IMAGE_FORMAT_OPTIONS"
        exit 1
    fi
}

write_session_metadata() {
    METADATA_FILE="session_metadata.txt"
    {
        echo "session_directory: $SESSION_DIR"
        echo "run_started_at: $RUN_STARTED_AT"
        echo "camera_detect_line: ${CAMERA_MODEL_LINE:-unknown}"
        echo "focus_mode: ${FOCUS_MODE:-unknown}"
        echo "battery_level: ${BATTERY_VAL:-unknown}"
        echo "frames: $TOTAL_FRAMES"
        echo "interval_seconds: $INTERVAL"
        echo "iso: $ISO"
        echo "shutter_speed: $SHUTTER_SPEED"
        echo "aperture: $APERTURE"
        echo "image_format_path: $IMAGE_FORMAT_PATH"
        echo "image_format: $IMAGE_FORMAT"
        echo "iso_options: $ISO_OPTIONS"
        echo "shutter_options: $SHUTTER_OPTIONS"
        echo "aperture_options: $APERTURE_OPTIONS"
        echo "image_format_options: $IMAGE_FORMAT_OPTIONS"
        echo "capture_started_at: $(date -Iseconds)"
    } > "$METADATA_FILE"
}

# Ask for capture settings
read -p "Number of frames [1]: " TOTAL_FRAMES
TOTAL_FRAMES=${TOTAL_FRAMES:-1}

read -p "Interval between shots in seconds [12]: " INTERVAL
INTERVAL=${INTERVAL:-12}

print_capture_settings

# 1. Kill background processes to free up the USB interface

echo ""
echo "Releasing USB lock from system volume monitors..."
systemctl --user stop gvfs-gphoto2-volume-monitor.service 2>/dev/null
killall gvfs-gphoto2-volume-monitor gvfsd-gphoto2 2>/dev/null
MONITOR_STOPPED=1

# 2. Check if the camera is physically connected and detected

check_camera_connection
check_focus_mode

# 3. Check battery status

check_battery_level
load_camera_options

echo ""
echo "Available ISO options: $ISO_OPTIONS"
prompt_for_valid_choice "ISO" "1600" "$ISO_OPTIONS" ISO

echo ""
echo "Available shutter speed options: $SHUTTER_OPTIONS"
prompt_for_valid_choice "Shutter speed" "10" "$SHUTTER_OPTIONS" SHUTTER_SPEED

echo "Available aperture options: $APERTURE_OPTIONS"
prompt_for_valid_choice "Aperture" "3.5" "$APERTURE_OPTIONS" APERTURE

print_capture_settings

read -p "Start capture? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# 4. Create a uniquely named folder for tonight's session

SESSION_DIR="astro_$(date +%Y-%m-%d_%H-%M)"
echo "Creating session directory: $SESSION_DIR"
mkdir -p "$SESSION_DIR"
cd "$SESSION_DIR" || exit 1

write_session_metadata

# 5. Set camera configurations

echo "Configuring camera settings..."
set_camera_config_or_fail "$IMAGE_FORMAT_PATH" "$IMAGE_FORMAT" "image format" || exit 1
set_camera_config_or_fail "/main/imgsettings/iso" "$ISO" "ISO" || exit 1
set_camera_config_or_fail "/main/capturesettings/shutterspeed" "$SHUTTER_SPEED" "shutter speed" || exit 1
set_camera_config_or_fail "/main/capturesettings/aperture" "$APERTURE" "aperture" || exit 1

# 6. Capture loop with progress bar

echo ""
echo "Starting capture sequence..."

for ((i=1; i<=TOTAL_FRAMES; i++)); do

    # Calculate progress
    PERCENT=$(( i * 100 / TOTAL_FRAMES ))
    BAR_LENGTH=$(( PERCENT / 4 ))

    # Construct progress bar
    BAR=$(printf "%${BAR_LENGTH}s" | tr ' ' '#')

    # Print progress
    printf "\rProgress: [%-25s] %d%% (%d/%d frames)" \
        "$BAR" "$PERCENT" "$i" "$TOTAL_FRAMES"

    # Capture frame
    gphoto2 \
        --filename "astro_shot_$(printf "%03d" "$i").%C" \
        --capture-image-and-download \
        > /dev/null 2>&1

    # Wait for next shot
    if [ "$i" -lt "$TOTAL_FRAMES" ]; then
        sleep "$INTERVAL"
    fi

done

echo ""
echo ""
echo "🎉 Sequence complete!"
echo "Images saved in: $(pwd)"

{
    echo "capture_completed_at: $(date -Iseconds)"
    echo "images_directory: $(pwd)"
} >> "$METADATA_FILE"

# 7. Restore system services

echo "Restoring system volume monitor..."
restore_volume_monitor
trap - EXIT
