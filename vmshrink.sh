#!/bin/bash

# Zero free space on the filesystem containing ZERO_FILE_LOCATION
# prior to VM disk compaction.
#
# Run as:
#     sudo ./zero-free-space.sh

set -u

clear

# Primary zero file.
ZERO_FILE_LOCATION="/zerofile"

# Locations used by current or older versions of this script.
ZERO_FILE_LOCATIONS=(
    "/zerofile"
    "/root/zerofile"
    "{$HOME}/zerofile"
)

# Leave this amount of free filesystem space.
SAFETY_MARGIN=$((1 * 1024 * 1024 * 1024))   # 1 GiB

# Progress refresh interval.
PROGRESS_INTERVAL=1

# Current dd process/session PID.
dd_pid=""

# Prevent recursive cleanup.
cleanup_running=0


# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

get_free_space() {
    df -B1 --output=avail "$1" 2>/dev/null |
        tail -1 |
        tr -d '[:space:]'
}


human_size() {
    local bytes="$1"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes"
    else
        awk -v b="$bytes" 'BEGIN {
            if (b >= 1073741824)
                printf "%.2f GiB", b / 1073741824;
            else if (b >= 1048576)
                printf "%.2f MiB", b / 1048576;
            else if (b >= 1024)
                printf "%.2f KiB", b / 1024;
            else
                printf "%d B", b;
        }'
    fi
}


# ---------------------------------------------------------------------------
# Determine whether a process is one of our zero-writing dd processes
# ---------------------------------------------------------------------------

is_zero_writer() {
    local pid="$1"
    local zero_file="$2"
    local arg
    local found_if=0
    local found_of=0

    [ -r "/proc/$pid/comm" ] || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1

    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "dd" ] || return 1

    while IFS= read -r -d '' arg; do
        if [ "$arg" = "if=/dev/zero" ]; then
            found_if=1
        fi

        if [ "$arg" = "of=$zero_file" ]; then
            found_of=1
        fi
    done < "/proc/$pid/cmdline"

    [ "$found_if" -eq 1 ] && [ "$found_of" -eq 1 ]
}


# ---------------------------------------------------------------------------
# Kill a process and make sure it actually disappears
# ---------------------------------------------------------------------------

terminate_pid() {
    local pid="$1"
    local i

    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    kill -TERM "$pid" 2>/dev/null || true

    # Allow up to ~2 seconds for graceful termination.
    for ((i = 0; i < 20; i++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            return 0
        fi

        sleep 0.1
    done

    # It did not terminate: force it.
    kill -KILL "$pid" 2>/dev/null || true

    # Wait for the kernel to remove the process.
    for ((i = 0; i < 20; i++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            return 0
        fi

        sleep 0.1
    done

    return 1
}


# ---------------------------------------------------------------------------
# Find and terminate orphaned dd processes from previous runs
# ---------------------------------------------------------------------------

remove_orphaned_zero_writers() {
    local proc
    local pid
    local zero_file
    local found=0

    for proc in /proc/[0-9]*; do

        [ -d "$proc" ] || continue

        pid="${proc##*/}"

        # Never inspect/kill this script.
        [ "$pid" = "$$" ] && continue

        for zero_file in "${ZERO_FILE_LOCATIONS[@]}"; do

            if is_zero_writer "$pid" "$zero_file"; then

                echo "Found orphaned zeroing process:"
                echo "    PID:  $pid"
                echo "    File: $zero_file"
                echo
                echo "Stopping orphaned zeroing process..."

                if ! terminate_pid "$pid"; then
                    echo
                    echo "ERROR: Unable to terminate orphaned dd process $pid."
                    echo "       Refusing to continue."
                    exit 1
                fi

                found=1
                break
            fi
        done
    done

    if [ "$found" -eq 1 ]; then
        sync
        echo "Orphaned zeroing process removed."
        echo
    fi
}


# ---------------------------------------------------------------------------
# Remove visible zero files
# ---------------------------------------------------------------------------

remove_zero_files() {
    local zero_file

    for zero_file in "${ZERO_FILE_LOCATIONS[@]}"; do

        if [ -e "$zero_file" ]; then
            echo "Removing zero file: $zero_file"

            rm -f -- "$zero_file"

            if [ -e "$zero_file" ]; then
                echo "WARNING: Failed to remove $zero_file"
            fi
        fi
    done
}


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

cleanup() {
    local exit_status="${1:-$?}"
    local i

    if [ "$cleanup_running" -eq 1 ]; then
        exit "$exit_status"
    fi

    cleanup_running=1

    # Prevent traps recursively firing during cleanup.
    trap - EXIT INT TERM HUP QUIT

    echo

    # dd is started using setsid, so dd_pid is also its process-group/session
    # leader. Kill the entire group rather than only one process.
    if [ -n "${dd_pid:-}" ] && kill -0 "$dd_pid" 2>/dev/null; then

        echo "Stopping zeroing process..."

        kill -TERM -- "-$dd_pid" 2>/dev/null || \
            kill -TERM "$dd_pid" 2>/dev/null || true

        for ((i = 0; i < 30; i++)); do
            if ! kill -0 "$dd_pid" 2>/dev/null; then
                break
            fi

            sleep 0.1
        done

        if kill -0 "$dd_pid" 2>/dev/null; then
            echo "Zeroing process did not terminate; forcing termination..."

            kill -KILL -- "-$dd_pid" 2>/dev/null || \
                kill -KILL "$dd_pid" 2>/dev/null || true
        fi

        wait "$dd_pid" 2>/dev/null || true

        dd_pid=""
    fi

    # Catch any dd writer that somehow survived the normal shutdown.
    remove_orphaned_zero_writers

    # Now it is safe to unlink the files.
    remove_zero_files

    sync

    exit "$exit_status"
}


# ---------------------------------------------------------------------------
# Signal handling
# ---------------------------------------------------------------------------

trap 'cleanup $?' EXIT
trap 'cleanup 130' INT
trap 'cleanup 143' TERM
trap 'cleanup 129' HUP
trap 'cleanup 131' QUIT


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Root privileges are required."
    echo
    echo "Run:"
    echo
    echo "    sudo $0"
    echo
    exit 1
fi


if ! command -v setsid >/dev/null 2>&1; then
    echo "ERROR: setsid is required but was not found."
    exit 1
fi


ZERO_FILE_DIR=$(dirname "$ZERO_FILE_LOCATION")

if [ ! -d "$ZERO_FILE_DIR" ]; then
    echo "ERROR: Directory does not exist:"
    echo "       $ZERO_FILE_DIR"
    exit 1
fi


MOUNT_POINT=$(
    df -P "$ZERO_FILE_DIR" 2>/dev/null |
        awk 'NR == 2 { print $6 }'
)

if [ -z "$MOUNT_POINT" ]; then
    echo "ERROR: Unable to determine filesystem containing:"
    echo "       $ZERO_FILE_DIR"
    exit 1
fi


# ---------------------------------------------------------------------------
# Clean up damage/stale state from any previous run
# ---------------------------------------------------------------------------

echo "Checking for orphaned zeroing processes..."

remove_orphaned_zero_writers

remove_zero_files

sync


# ---------------------------------------------------------------------------
# Determine available space
# ---------------------------------------------------------------------------

free_space=$(get_free_space "$ZERO_FILE_DIR")

if ! [[ "$free_space" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Unable to determine available filesystem space."
    exit 1
fi


if [ "$free_space" -le "$SAFETY_MARGIN" ]; then
    echo "ERROR: Not enough free space."
    echo "Available:      $(human_size "$free_space")"
    echo "Safety margin:  $(human_size "$SAFETY_MARGIN")"
    exit 1
fi


max_file_size=$((free_space - SAFETY_MARGIN))

max_file_size_mb=$((max_file_size / 1024 / 1024))

if [ "$max_file_size_mb" -le 0 ]; then
    echo "ERROR: Less than 1 MiB is available for zeroing after"
    echo "       applying the safety margin."
    exit 1
fi

target_bytes=$((max_file_size_mb * 1024 * 1024))


echo
echo "Zero file location:  $ZERO_FILE_LOCATION"
echo "Filesystem:          $MOUNT_POINT"
echo "Available space:     $(human_size "$free_space")"
echo "Safety margin:       $(human_size "$SAFETY_MARGIN")"
echo "Zero file target:    $(human_size "$target_bytes")"
echo

echo "Creating zero-filled file..."
echo


# ---------------------------------------------------------------------------
# Start dd in its OWN SESSION / PROCESS GROUP
# ---------------------------------------------------------------------------

setsid dd \
    if=/dev/zero \
    of="$ZERO_FILE_LOCATION" \
    bs=1M \
    count="$max_file_size_mb" \
    status=none &

dd_pid=$!


# Verify that dd actually started.
sleep 0.1

if ! kill -0 "$dd_pid" 2>/dev/null; then
    wait "$dd_pid"
    dd_status=$?
    dd_pid=""

    echo
    echo "ERROR: dd failed to start correctly."
    exit "$dd_status"
fi


# ---------------------------------------------------------------------------
# Progress display
# ---------------------------------------------------------------------------

while kill -0 "$dd_pid" 2>/dev/null; do

    if [ -f "$ZERO_FILE_LOCATION" ]; then
        current_size=$(
            stat -c '%s' "$ZERO_FILE_LOCATION" 2>/dev/null ||
                echo 0
        )
    else
        current_size=0
    fi

    if ! [[ "$current_size" =~ ^[0-9]+$ ]]; then
        current_size=0
    fi

    if [ "$target_bytes" -gt 0 ]; then
        percent=$((current_size * 100 / target_bytes))
    else
        percent=0
    fi

    if [ "$percent" -gt 100 ]; then
        percent=100
    fi

    printf "\rProgress: %3d%%  Written: %-10s / %-10s" \
        "$percent" \
        "$(human_size "$current_size")" \
        "$(human_size "$target_bytes")"

    sleep "$PROGRESS_INTERVAL"
done


wait "$dd_pid"
dd_status=$?

dd_pid=""


if [ "$dd_status" -ne 0 ]; then
    echo
    echo
    echo "ERROR: dd failed with exit code $dd_status."
    exit "$dd_status"
fi


printf "\rProgress: 100%%  Written: %-10s / %-10s\n" \
    "$(human_size "$target_bytes")" \
    "$(human_size "$target_bytes")"


# ---------------------------------------------------------------------------
# Successful cleanup
# ---------------------------------------------------------------------------

echo
echo "Syncing filesystem..."
sync

echo "Removing zero file..."
remove_zero_files

echo "Syncing filesystem..."
sync


free_space_after=$(get_free_space "$ZERO_FILE_DIR")

if [[ "$free_space_after" =~ ^[0-9]+$ ]]; then
    echo
    echo "Available space after cleanup: $(human_size "$free_space_after")"
else
    echo
    echo "WARNING: Unable to verify available space after cleanup."
fi


# Final sanity check: there must be no surviving zero-writing dd.
remove_orphaned_zero_writers


# Normal completion. Do not execute the EXIT cleanup handler again.
trap - EXIT INT TERM HUP QUIT


echo
echo "Zeroing complete."
echo "The VM disk can now be compacted."
echo

echo "To clear Bash history ready for reimage, run:"
echo
echo "    history -c && history -w"
echo
