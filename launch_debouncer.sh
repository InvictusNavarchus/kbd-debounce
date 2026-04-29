#!/usr/bin/env bash
# Launch keyboard-debouncer using settings from debouncer.conf.
#
# Config fields (see debouncer.conf.example for documentation):
#   KEYBOARD_NAME  — physical keyboard name as shown by evtest
#   DEVICE_PATH    — direct path to event node, e.g. /dev/input/event10
#                    (overrides KEYBOARD_NAME if both are set)
#   KEYS           — required; comma-separated KEY_* names to debounce (e.g. KEY_K,KEY_L)
#   THRESHOLD_MS   — optional; debounce window in ms (default: 30)
#   LOG_FORWARD    — optional; true/false, log forwarded events (default: false)

set -euo pipefail

# ── Locate config file ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/debouncer.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo "Error: configuration file not found: $CONF_FILE" >&2
    echo "       Copy debouncer.conf.example to debouncer.conf and fill in your values." >&2
    exit 1
fi

# ── Helper: read a single key=value from the conf file ─────────────────────
# Usage: conf_get KEY
# Prints the value (everything after the first '='), or empty string if absent.
conf_get() {
    grep -m1 "^${1}=" "$CONF_FILE" | cut -d= -f2-
}

# ── KEYBOARD_NAME / DEVICE_PATH ────────────────────────────────────────────
# Either DEVICE_PATH (direct) or KEYBOARD_NAME (lookup) must be set.
# If both are set, DEVICE_PATH wins and KEYBOARD_NAME is ignored.
DEVICE_PATH=$(conf_get DEVICE_PATH)
KEYBOARD_NAME=$(conf_get KEYBOARD_NAME)

if [ -n "$DEVICE_PATH" ]; then
    # Direct path — validate it looks sane and exists.
    if [[ ! "$DEVICE_PATH" =~ ^/dev/input/event[0-9]+$ ]]; then
        echo "Error: DEVICE_PATH must be a path like /dev/input/event10, got: '$DEVICE_PATH'" >&2
        exit 1
    fi
    if [ ! -e "$DEVICE_PATH" ]; then
        echo "Error: DEVICE_PATH '$DEVICE_PATH' does not exist" >&2
        exit 1
    fi
    if [ -n "$KEYBOARD_NAME" ]; then
        echo "Note: DEVICE_PATH is set — KEYBOARD_NAME ('$KEYBOARD_NAME') is ignored" >&2
    fi
    DEVICE="$DEVICE_PATH"
else
    # Name-based lookup.
    if [ -z "$KEYBOARD_NAME" ]; then
        echo "Error: either KEYBOARD_NAME or DEVICE_PATH must be set in $CONF_FILE" >&2
        exit 1
    fi

    DEVICE=""
    for dev in /sys/class/input/event*; do
        # Strip trailing whitespace/newlines — some kernels append a trailing space.
        name=$(tr -d '\n' < "$dev/device/name" | sed 's/[[:space:]]*$//')
        if [ "$name" = "$KEYBOARD_NAME" ]; then
            DEVICE="/dev/input/$(basename "$dev")"
            break
        fi
    done

    if [ -z "$DEVICE" ]; then
        echo "Error: no input device found with name '$KEYBOARD_NAME'" >&2
        echo "       Run 'evtest' to list connected devices and update KEYBOARD_NAME in $CONF_FILE." >&2
        exit 1
    fi
fi

# ── KEYS (required) ─────────────────────────────────────────────────────────
KEYS=$(conf_get KEYS)
if [ -z "$KEYS" ]; then
    echo "Error: KEYS is required in $CONF_FILE" >&2
    echo "       Specify which keys to debounce, e.g. KEYS=KEY_K,KEY_L" >&2
    echo "       Use KEY_* names exactly as shown by evtest." >&2
    exit 1
fi

# ── THRESHOLD_MS (optional, default: 30) ───────────────────────────────────
THRESHOLD_MS=$(conf_get THRESHOLD_MS)
if [ -z "$THRESHOLD_MS" ]; then
    THRESHOLD_MS=30
    echo "Note: THRESHOLD_MS not set in $CONF_FILE — using default: ${THRESHOLD_MS}ms" >&2
elif ! [[ "$THRESHOLD_MS" =~ ^[0-9]+$ ]] || [ "$THRESHOLD_MS" -eq 0 ]; then
    echo "Error: THRESHOLD_MS must be a positive integer, got: '$THRESHOLD_MS'" >&2
    exit 1
fi

# ── LOG_FORWARD (optional, default: false) ──────────────────────────────────
LOG_FORWARD=$(conf_get LOG_FORWARD)
if [ -z "$LOG_FORWARD" ]; then
    LOG_FORWARD=false
elif [ "$LOG_FORWARD" != "true" ] && [ "$LOG_FORWARD" != "false" ]; then
    echo "Error: LOG_FORWARD must be 'true' or 'false', got: '$LOG_FORWARD'" >&2
    exit 1
fi


# ── Build argument list ─────────────────────────────────────────────────────
DEBOUNCER_ARGS=("$DEVICE" "--keys" "$KEYS" "--threshold-ms" "$THRESHOLD_MS")
if [ "$LOG_FORWARD" = "true" ]; then
    DEBOUNCER_ARGS+=("--log-forward")
fi

# ── Launch ──────────────────────────────────────────────────────────────────
echo "Device   : $DEVICE${KEYBOARD_NAME:+ ($KEYBOARD_NAME)}"
echo "Keys     : $KEYS"
echo "Threshold: ${THRESHOLD_MS}ms"
echo "Log fwd  : $LOG_FORWARD"
exec sudo "${SCRIPT_DIR}/target/release/keyboard-debouncer" "${DEBOUNCER_ARGS[@]}"
