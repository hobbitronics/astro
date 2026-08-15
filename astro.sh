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
LIVE_VIEW_USED="no"
LIVE_VIEW_SIZE_PATH="not-supported"
LIVE_VIEW_SIZE_SELECTED="unchanged"

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

require_camera_config_path() {
    local label="$1"
    shift

    if ! find_first_config_path "$@"; then
        echo "❌ ERROR: Could not find a supported $label config path on this camera." >&2
        return 1
    fi
}

choose_image_format() {
    local options_csv="$1"
    local option
    local trimmed
    local upper

    IFS=',' read -r -a options <<< "$options_csv"

    for option in "${options[@]}"; do
        trimmed=$(trim_whitespace "$option")
        upper=$(echo "$trimmed" | tr '[:lower:]' '[:upper:]')
        if [[ "$upper" == *"RAW"* ]]; then
            echo "$trimmed"
            return 0
        fi
    done

    return 1
}

choose_largest_live_view_size() {
    local options_csv="$1"
    local option
    local best_option=""
    local best_score=-1
    local score
    local trimmed
    local lower
    local width
    local height

    IFS=',' read -r -a options <<< "$options_csv"

    for option in "${options[@]}"; do
        trimmed=$(trim_whitespace "$option")
        lower=$(echo "$trimmed" | tr '[:upper:]' '[:lower:]')
        score=0

        if [[ "$trimmed" =~ ^([0-9]{3,4})x([0-9]{3,4})$ ]]; then
            width=${BASH_REMATCH[1]}
            height=${BASH_REMATCH[2]}
            score=$(( width * height ))
        elif [[ "$lower" == *"1920"* ]]; then
            score=2073600
        elif [[ "$lower" == *"1280"* ]]; then
            score=921600
        elif [[ "$lower" == *"1024"* ]]; then
            score=786432
        elif [[ "$lower" == *"960"* ]]; then
            score=614400
        elif [[ "$lower" == *"800"* ]]; then
            score=480000
        elif [[ "$lower" == *"640"* ]]; then
            score=307200
        elif [[ "$lower" == *"full hd"* ]] || [[ "$lower" == *"fhd"* ]]; then
            score=2073600
        elif [[ "$lower" == *"large"* ]] || [[ "$lower" == *"high"* ]]; then
            score=900000
        elif [[ "$lower" == *"medium"* ]]; then
            score=500000
        elif [[ "$lower" == *"small"* ]] || [[ "$lower" == *"low"* ]]; then
            score=250000
        fi

        if [ "$score" -gt "$best_score" ]; then
            best_score=$score
            best_option="$trimmed"
        fi
    done

    if [ -n "$best_option" ]; then
        echo "$best_option"
        return 0
    fi

    return 1
}

configure_live_view_size() {
    local live_view_size_options
    local selected_live_view_size

    LIVE_VIEW_SIZE_PATH=$(find_first_config_path "/main/capturesettings/liveviewsize")

    if [ -z "$LIVE_VIEW_SIZE_PATH" ]; then
        LIVE_VIEW_SIZE_PATH="not-supported"
        echo "⚠️ WARNING: Camera does not expose /main/capturesettings/liveviewsize. Continuing with current camera value."
        return 0
    fi

    live_view_size_options=$(get_config_choices "$LIVE_VIEW_SIZE_PATH" "")
    selected_live_view_size=$(choose_largest_live_view_size "$live_view_size_options")

    if [ -z "$selected_live_view_size" ]; then
        echo "⚠️ WARNING: No Live View size choices found. Continuing with current camera value."
        return 0
    fi

    if set_camera_config_or_fail "$LIVE_VIEW_SIZE_PATH" "$selected_live_view_size" "live view size"; then
        LIVE_VIEW_SIZE_SELECTED="$selected_live_view_size"
        echo "✓ Live View size set to: $LIVE_VIEW_SIZE_SELECTED"
        return 0
    fi

    echo "⚠️ WARNING: Could not set Live View size. Continuing with current camera value."
    return 0
}

camera_supports_live_view() {
    find_first_config_path \
        "/main/actions/eosviewfinder" \
        "/main/actions/viewfinder" \
        "/main/capturesettings/liveviewsize" \
        > /dev/null
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
    FOCUS_MODE_PATH=$(find_first_config_path "/main/capturesettings/focusmode" "/main/settings/focusmode")
    if [ -z "$FOCUS_MODE_PATH" ]; then
        return 0
    fi

    FOCUS_MODE=$(get_config_current_value "$FOCUS_MODE_PATH")
    if [ -n "$FOCUS_MODE" ]; then
        if [[ "$FOCUS_MODE" == Manual* ]]; then
            echo "✓ Focus mode is Manual."
        else
            echo "⚠️ WARNING: Focus mode is '$FOCUS_MODE'. Switch the lens/camera to Manual focus for astrophotography."
        fi
    fi
}

run_live_view_if_requested() {
    local answer

    if ! camera_supports_live_view; then
        echo "⚠️ WARNING: Camera does not expose Live View over USB. Skipping Live View prompt."
        return 0
    fi

    read -p "Open Live View for manual focusing now? [y/N]: " answer
    answer=${answer:-N}

    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        return 0
    fi

    if ! command -v ffplay > /dev/null 2>&1; then
        echo "⚠️ WARNING: ffplay is not installed. Skipping Live View."
        return 0
    fi

    configure_live_view_size

    echo ""
    echo "Starting Live View..."
    echo "Live View window: 1920x1080"
    echo "Tip: press q in the ffplay window when you are done focusing."

    gphoto2 --stdout --capture-movie | ffplay -f mjpeg -x 1920 -y 1080 -

    LIVE_VIEW_USED="yes"
    echo "Live View closed."
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
    ISO_PATH=$(require_camera_config_path "ISO" "/main/imgsettings/iso" "/main/settings/iso") || exit 1
    SHUTTER_PATH=$(require_camera_config_path "shutter speed" "/main/capturesettings/shutterspeed" "/main/settings/shutterspeed") || exit 1
    APERTURE_PATH=$(require_camera_config_path "aperture" "/main/capturesettings/aperture" "/main/settings/aperture") || exit 1

    SHUTTER_OPTIONS=$(get_config_choices "$SHUTTER_PATH" "bulb, 30, 25, 20, 15, 13, 10.3, 8, 6.3, 5, 4, 3.2, 2.5, 2, 1.6, 1.3, 1, 0.8, 0.6, 0.5")
    APERTURE_OPTIONS=$(get_config_choices "$APERTURE_PATH" "4, 5.6, 8, 11, 16")
    ISO_OPTIONS=$(get_config_choices "$ISO_PATH" "100, 200, 400, 800, 1600")
    IMAGE_FORMAT_PATH=$(find_first_config_path "/main/imgsettings/imageformat" "/main/imgsettings/imageformatsd" "/main/imgsettings/imgformat" "/main/imgsettings/imagequality" "/main/imgsettings/quality" "/main/settings/imageformat")

    if [ -z "$IMAGE_FORMAT_PATH" ]; then
        IMAGE_FORMAT_PATH="not-supported"
        IMAGE_FORMAT_OPTIONS="not-supported"
        IMAGE_FORMAT="unchanged"
        echo "⚠️ WARNING: Camera does not expose an image format config path. Set RAW manually on the camera; continuing with current camera value."
        return 0
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
        echo "live_view_used: $LIVE_VIEW_USED"
        echo "live_view_size_path: ${LIVE_VIEW_SIZE_PATH:-unknown}"
        echo "live_view_size_selected: ${LIVE_VIEW_SIZE_SELECTED:-unknown}"
        echo "battery_level: ${BATTERY_VAL:-unknown}"
        echo "frames: $TOTAL_FRAMES"
        echo "interval_seconds: $INTERVAL"
        echo "iso: $ISO"
        echo "shutter_speed: $SHUTTER_SPEED"
        echo "aperture: $APERTURE"
        echo "iso_path: $ISO_PATH"
        echo "shutter_path: $SHUTTER_PATH"
        echo "aperture_path: $APERTURE_PATH"
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
run_live_view_if_requested

# 3. Check battery status

check_battery_level
load_camera_options

APERTURE_DEFAULT="4"
if ! is_valid_choice "$APERTURE_DEFAULT" "$APERTURE_OPTIONS" && is_valid_choice "4.0" "$APERTURE_OPTIONS"; then
    APERTURE_DEFAULT="4.0"
fi

echo ""
echo "Available ISO options: $ISO_OPTIONS"
prompt_for_valid_choice "ISO" "1600" "$ISO_OPTIONS" ISO

echo ""
echo "Available shutter speed options: $SHUTTER_OPTIONS"
prompt_for_valid_choice "Shutter speed" "5" "$SHUTTER_OPTIONS" SHUTTER_SPEED

echo "Available aperture options: $APERTURE_OPTIONS"
prompt_for_valid_choice "Aperture" "$APERTURE_DEFAULT" "$APERTURE_OPTIONS" APERTURE

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
if [ "$IMAGE_FORMAT_PATH" != "not-supported" ]; then
    set_camera_config_or_fail "$IMAGE_FORMAT_PATH" "$IMAGE_FORMAT" "image format" || exit 1
else
    echo "Skipping image format configuration; camera does not expose it over USB."
fi
set_camera_config_or_fail "$ISO_PATH" "$ISO" "ISO" || exit 1
set_camera_config_or_fail "$SHUTTER_PATH" "$SHUTTER_SPEED" "shutter speed" || exit 1
set_camera_config_or_fail "$APERTURE_PATH" "$APERTURE" "aperture" || exit 1

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
