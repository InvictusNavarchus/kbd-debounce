#!/usr/bin/env bash
# Launch keyboard-debouncer with the correct event device for the configured keyboard.

set -euo pipefail

# --- Configuration file -------------------------------------------------------
# First, look next to the script; fall back to a system-wide location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/debouncer.conf"

if [ ! -f "$CONF_FILE" ]; then
    # System-wide alternative (uncomment and adjust if needed)
    # CONF_FILE="/etc/kb_debouncer.conf"
    echo "Configuration file not found: $CONF_FILE" >&2
    exit 1
fi

# --- Read the keyboard name from the conf file --------------------------------
# Extract the value of KEYBOARD_NAME (everything after the first '=').
# Only the first match is used; trailing whitespace in the config value is preserved.
KEYBOARD_NAME=$(grep -m1 '^KEYBOARD_NAME=' "$CONF_FILE" | cut -d= -f2-)

if [ -z "$KEYBOARD_NAME" ]; then
    echo "KEYBOARD_NAME is empty or not set in $CONF_FILE" >&2
    exit 1
fi

# --- Locate the matching input event device -----------------------------------
DEVICE=""
for dev in /sys/class/input/event*; do
    # Read the device name file and strip any trailing whitespace / newlines.
    # This handles the typical hardware quirk where the name ends with a space.
    name=$(tr -d '\n' < "$dev/device/name" | sed 's/[[:space:]]*$//')
    if [ "$name" = "$KEYBOARD_NAME" ]; then
        DEVICE="/dev/input/$(basename "$dev")"
        break
    fi
done

if [ -z "$DEVICE" ]; then
    echo "No input device found with name '$KEYBOARD_NAME'" >&2
    exit 1
fi

# --- Launch the debouncer -----------------------------------------------------
echo "Found device: $DEVICE"
exec sudo ./target/release/keyboard-debouncer "$DEVICE"
