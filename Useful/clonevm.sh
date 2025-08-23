#!/bin/sh
# clonevm.sh - Clone a VM on ESXi (current state only)
# Usage:
#   ./clonevm.sh <SourceVM_Name> <ClonedVM_Name> [Datastore] [--keep-mac]

set -eu

clear

usage() {
    echo "Usage: $0 [SourceVM_Name] [ClonedVM_Name] [Datastore] [--keep-mac]"
    exit 1
}

# Default datastore
DEFAULT_DATASTORE=$(esxcli storage filesystem list | awk '$1 ~ /^\/vmfs/ {print $2; exit}')

# Argument parsing
SRC_VM=""
NEW_VM=""
DATASTORE=""
KEEP_MAC=false

for arg in "$@"; do
    case "$arg" in
        --keep-mac|-k) KEEP_MAC=true ;;
        -h|--help) usage ;;
        -*)
            echo "Unknown option: $arg"
            usage ;;
        *)
            if [ -z "$SRC_VM" ]; then
                SRC_VM="$arg"
            elif [ -z "$NEW_VM" ]; then
                NEW_VM="$arg"
            elif [ -z "$DATASTORE" ]; then
                DATASTORE="$arg"
            else
                echo "ERROR: Too many non-option args: $arg"
                usage
            fi
            ;;
    esac
done

# Clear out any orphan processes from previous runs 
echo "--------------------------------------------------"
cleanup_vmkfstools() {
    echo "Checking for leftover vmkfstools processes..."
    while true; do
        # get PIDs safely
        pids=$(ps | grep vmkfstools | grep -v grep | awk '{print $1}' || true)
        [ -z "$pids" ] && break
        for pid in $pids; do
            echo "  Killing PID $pid"
            kill -9 "$pid" 2>/dev/null || true   # ignore errors
            sleep 0.2
        done
        sleep 0.5
    done
}

trap 'echo "Script interrupted!"; cleanup_vmkfstools; exit 1' INT TERM

cleanup_vmkfstools || true

[ -z "$SRC_VM" ] && usage
[ -z "$NEW_VM" ] && usage
[ -z "${DATASTORE:-}" ] && DATASTORE="$DEFAULT_DATASTORE"

SRC_PATH="/vmfs/volumes/${DATASTORE}/${SRC_VM}"
NEW_PATH="/vmfs/volumes/${DATASTORE}/${NEW_VM}"

[ ! -d "$SRC_PATH" ] && { echo "ERROR: Source VM $SRC_PATH not found!"; exit 1; }
[ -d "$NEW_PATH" ] && { echo "ERROR: Target VM $NEW_PATH already exists!"; exit 1; }

echo "Cloning VM '$SRC_VM' -> '$NEW_VM' on datastore '$DATASTORE'..."
mkdir "$NEW_PATH" || { echo "ERROR: Cannot create $NEW_PATH"; exit 1; }

# Copy VMX
SRC_VMX=$(ls "$SRC_PATH"/*.vmx 2>/dev/null | head -n 1)
[ -z "$SRC_VMX" ] && { echo "ERROR: No VMX file found in $SRC_PATH!"; exit 1; }
NEW_VMX="$NEW_PATH/${NEW_VM}.vmx"
cp "$SRC_VMX" "$NEW_VMX" || { echo "ERROR: Copy VMX failed"; exit 1; }

# Copy/update VMXF
SRC_VMXF=$(ls "$SRC_PATH"/*.vmxf 2>/dev/null | head -n 1)
if [ -n "$SRC_VMXF" ]; then
    NEW_VMXF="$NEW_PATH/${NEW_VM}.vmxf"
    cp "$SRC_VMXF" "$NEW_VMXF"
fi

# Build list of disk filenames (skip ISOs/floppies)
DISK_LIST_FILE=$(mktemp)
trap 'rm -f "$DISK_LIST_FILE"' EXIT
awk -F'"' '/fileName/ {print $2}' "$SRC_VMX" \
    | grep -v -E '\.iso$|\.ISO$|\.flp$|\.FLP$' \
    > "$DISK_LIST_FILE"

# Clone disks and force VMX references to new names
# Build temporary list of disks from VMX (exclude ISOs/floppies)
DISK_LIST_FILE=$(mktemp)
trap 'rm -f "$DISK_LIST_FILE"' EXIT
awk -F'"' '/fileName/ && $2 !~ /\.iso$|\.ISO$|\.flp$|\.FLP$/ {print $2}' "$SRC_VMX" > "$DISK_LIST_FILE"

DISK_COUNT=1
while IFS= read -r SRC_FILE; do
    [ -z "$SRC_FILE" ] && continue
    SRC_DISK="$SRC_PATH/$SRC_FILE"
    [ ! -f "$SRC_DISK" ] && { echo "  Source disk missing, skipping: $SRC_DISK"; continue; }

    # New naming convention: vmname-000001.vmdk, vmname-000002.vmdk, ...
    NEW_DISK_NAME=$(printf "%s-%06d.vmdk" "$NEW_VM" "$DISK_COUNT")

    echo "  Cloning: '$SRC_DISK' -> '$NEW_DISK_NAME'"
    vmkfstools -i "$SRC_DISK" "$NEW_PATH/$NEW_DISK_NAME" -d thin || {
        echo "ERROR: vmkfstools clone failed for $SRC_DISK"; exit 1;
    }

    # Replace only this disk reference in VMX
    ESC_SRC_FILE=$(echo "$SRC_FILE" | sed 's/[\/&]/\\&/g')
    sed -i "s#fileName = \"$ESC_SRC_FILE\"#fileName = \"$NEW_DISK_NAME\"#" "$NEW_VMX"

    DISK_COUNT=$((DISK_COUNT + 1))
done < "$DISK_LIST_FILE"

[ $DISK_COUNT -eq 1 ] && { echo "ERROR: No valid disks found in VMX."; exit 1; }

# UEFI NVRAM handling
SRC_NVRAM=$(ls "$SRC_PATH"/*.nvram 2>/dev/null | head -n 1)
if [ -n "$SRC_NVRAM" ]; then
    cp "$SRC_NVRAM" "$NEW_PATH/${NEW_VM}.nvram"
fi
if grep -q '^nvram = ' "$NEW_VMX"; then
    sed -i "s#^nvram = \".*\"#nvram = \"${NEW_VM}.nvram\"#" "$NEW_VMX"
else
    echo "nvram = \"${NEW_VM}.nvram\"" >> "$NEW_VMX"
fi

# Update VMX metadata (force all names)
sed -i "s#^displayName = \".*\"#displayName = \"${NEW_VM}\"#" "$NEW_VMX"
sed -i "s#^migrate.hostLog = \".*\"#migrate.hostLog = \"./${NEW_VM}.hlog\"#" "$NEW_VMX"
sed -i "s#^vmxstats.filename = \".*\"#vmxstats.filename = \"${NEW_VM}.scoreboard\"#" "$NEW_VMX"

# Remove stale MACs unless --keep-mac
if [ "$KEEP_MAC" = false ]; then
    sed -i '/ethernet[0-9]\.generatedAddress/d' "$NEW_VMX"
    sed -i '/ethernet[0-9]\.addressType/d' "$NEW_VMX"
fi

# Register new VM
VMID=$(vim-cmd solo/registervm "$NEW_VMX")
[ -z "$VMID" ] && { echo "ERROR: Failed to register VM."; exit 1; }

# Final summary
echo "------------------------------------------------------------"
echo "Clone complete:"
echo "  Source VM : $SRC_VM"
echo "  Target VM : $NEW_VM"
echo "  Datastore : $DATASTORE"
echo "  Path      : $NEW_PATH"
echo "  VMID      : $VMID"
echo "------------------------------------------------------------"
echo "Power on with: vim-cmd vmsvc/power.on $VMID"
