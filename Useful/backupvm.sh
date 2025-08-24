#!/bin/sh
# =============================================================================
# ghettoVCB Backup & Restore Wrapper
# David Harrop 
# August 2025
#
# Description:
#   Wrapper for ghettoVCB to simplify backing up and restoring ESXi VMs.
#   Features include:
#     - Backup & restore with exclusions
#     - Backup & restore individual, a selection, or all VMs for bare metal restores
#     - Tracking restore candidates. (Script automatically searches the default backup datastore from ghettoVCB.conf
#     - Handling of VM names with spaces
# 	  - Prompts to rename vm(s) during restores 
# 	  - Prompt to manually edit the ghettoVCB restore list prior to running 
#     - Dry-run mode for preview without execution
#     - Cleans up orphan vmkfstools processes or /tmp/ghetto* files after any script interruptions
#
# Usage:
#   ./script.sh --all                   # Back up all VMs except excluded
#   ./script.sh --name <VMNAME>         # Back up a specific VM
#   ./script.sh --restore --all         # Restore all VMs in backup datastore except excluded, with option to manually edit restore list
#   ./script.sh --restore --name <VM>   # Restore a specific VM
#   ./script.sh --dry-run --all         # Preview which VMs would be backed up
#   ./script.sh --restore --dry-run     # Preview restore targets
#   ./script.sh --help                  # Show these options
#
# Requirements:
#   - ghettoVCB.sh, ghettoVCB-restore.sh, and ghettoVCB.conf to be placed in the same directory
#   - Must run on an ESXi host with vim-cmd available
#   - Must run only one instance of this script at a time (script stops any running vmkfstools processes)
# =============================================================================

# Excluded VMs (exact names, one VM per line)
EXCLUDE_VMS="
Router1
"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GHB_CONF="$SCRIPT_DIR/ghettoVCB.conf"
BACKUPLIST="$SCRIPT_DIR/backuplist.txt"
RESTORELIST="$SCRIPT_DIR/restorelist.txt"
VM_BACKUP_VOLUME=$(
  grep -E '^VM_BACKUP_VOLUME=' "$GHB_CONF" \
  | cut -d'=' -f2- \
  | sed 's/^"[[:space:]]*//; s/[[:space:]]*"//; s/[[:space:]]*$//'
)
# VM_BACKUP_VOLUME="manually override here"
# ensure no trailing slash
VM_BACKUP_VOLUME="${VM_BACKUP_VOLUME%/}"
RECOVERY_DATASTORE=$(esxcli storage filesystem list | awk '$1 ~ /^\/vmfs/ {print $2; exit}')
#RECOVERY_DATASTORE= "manually override here"
RECOVERY_DATASTORE_PATH="/vmfs/volumes/$RECOVERY_DATASTORE/"
RESTORE_DISK_FORMAT="3" # 1 = zeroedthick, 2 = 2gbsparse, 3 = thin, 4 = eagerzeroedthick

set -eu

clear

usage() {
    echo "Usage: $0 [--restore] [--dry-run] --all | --name <VMNAME>"
    echo
    echo "Examples:"
    echo "  $0 --all                   # Backup all VMs (except excluded)"
    echo "  $0 --name <VMNAME>         # Backup a specific VM"
    echo "  $0 --dry-run --all         # Preview which VMs would be backed up"
	echo "  $0 --restore --all         # Restore all VMs in backup datastore (except excluded)"
    echo "  $0 --restore --name <VM>   # Restore a specific VM"
    echo "  $0 --restore --dry-run     # Preview restore targets in backup datastore"
    echo "  $0 --help                  # Shows this help message"
    echo
    exit 1
}

# Gather any exlcuded VMs 
is_excluded() {
    vm="$1"
    while IFS= read -r ex; do
        [ -z "$ex" ] && continue
        [ "$vm" = "$ex" ] && return 0
    done <<EOF
$EXCLUDE_VMS
EOF
    return 1
}

# Check for availabiity of script dependencies
[ -z "$VM_BACKUP_VOLUME" ] && { echo "Error: VM_BACKUP_VOLUME not set in $GHB_CONF"; exit 1; }
[ -z "$RECOVERY_DATASTORE" ] && { echo "Error: RECOVERY_DATASTORE not set"; exit 1; }
[ ! -f "$GHB_CONF" ] && { echo "Error: ghettoVCB.conf not found"; exit 1; }

# Parse script arguments
RESTORE_MODE=0
DRYRUN_MODE=0
ARG_MODE=""
ARG_VM=""

# Show usage if no arguments
echo
if [ $# -eq 0 ]; then
		[ $# -eq 0 ] && usage
fi

# Detect --restore, --dry-run before main args
while [ $# -gt 0 ]; do
    case "$1" in
	--help) usage;;
        --restore) RESTORE_MODE=1 ;;
        --dry-run) DRYRUN_MODE=1 ;;
        --all)     ARG_MODE="all" ;;
        --name)    
            shift
            [ -z "$1" ] && { echo "Error: VM name required after --name"; echo; exit 1; }
            if is_excluded "$1"; then
                echo "Error: VM '$1' is excluded."; echo; exit 1
            fi
            ARG_MODE="name"
            ARG_VM="$1"
            ;;
        *) usage;;
    esac
    shift

done

# Ensure required mode args are set
[ -z "$ARG_MODE" ] && usage

# Clear out leftover temp files or processes from previous (interrupted) ghettoVCB runs 
echo "--------------------------------------------------"
echo "Cleaning temporary files..."
rm -rf /tmp/ghetto* 2>/dev/null

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

echo
echo "Excluded VMs:"
echo "$EXCLUDE_VMS" | sed '/^$/d' | while IFS= read -r ex; do
    echo "  - $ex"
done
echo "--------------------------------------------------"
echo

# Backup list generator
generate_backuplist() {
    > "$BACKUPLIST"

    if [ "$RESTORE_MODE" -eq 1 ]; then
        # In restore mode, build list from backup storage
        echo "Building backup list from backup repository: $VM_BACKUP_VOLUME"
        find "$VM_BACKUP_VOLUME" -maxdepth 1 -mindepth 1 -type d | while IFS= read -r vm_dir; do
            vm="$(basename "$vm_dir")"
            if ! is_excluded "$vm"; then
                echo "$vm" >> "$BACKUPLIST"
            fi
        done
    else
        # In backup mode, build list from registered VMs
        vim-cmd vmsvc/getallvms | awk '
        NR>1 && $1 ~ /^[0-9]+$/ {
            name=""
            for(i=2;i<=NF;i++){
                if($i ~ /^\[/) break
                name = (name=="" ? $i : name " " $i)
            }
            if(name != "") print name
        }' | while IFS= read -r vm; do
            vm="$(echo "$vm" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
            if ! is_excluded "$vm"; then
                echo "$vm" >> "$BACKUPLIST"
            fi
        done
    fi
}

if [ "$ARG_MODE" = "all" ]; then
    generate_backuplist
else
    echo "$ARG_VM" > "$BACKUPLIST"
fi

# Restore list generator
generate_restorelist() {
    : > "$RESTORELIST"

    if [ ! -f "$BACKUPLIST" ]; then
        echo "Error: BACKUPLIST '$BACKUPLIST' not found" >&2
        return 1
    fi

    while IFS= read -r vm || [ -n "$vm" ]; do
        [ -z "$vm" ] && continue

        vm_dir=$(find "$VM_BACKUP_VOLUME" -maxdepth 1 -type d -name "${vm}*" 2>/dev/null | sort | tail -n1)
        if [ -z "$vm_dir" ]; then
            echo "Warning: No backup directory found for '$vm', skipping" >&2
            continue
        fi

        latest_gz=$(find "$vm_dir" -maxdepth 1 -type f \( -name "${vm}*.gz" -o -name "${vm}*.tgz" \) 2>/dev/null | sort | tail -n1)
        if [ -z "$latest_gz" ]; then
            echo "Warning: No matching .gz in '$vm_dir' for '$vm', skipping" >&2
            continue
        fi

        # Prompt for rename
        read -rp "Restore '$vm' as (press Enter to keep original name): " new_vm </dev/tty
        [ -z "$new_vm" ] && new_vm="$vm"

        # Write **only once** to restorelist
        printf '"%s;%s;%s;%s"\n' "$latest_gz" "$RECOVERY_DATASTORE_PATH" "$RESTORE_DISK_FORMAT" "$new_vm" >> "$RESTORELIST"

    done < "$BACKUPLIST"

    echo
    echo "restorelist.txt generated with $(wc -l < "$RESTORELIST") entries"

    # Manual edit option
    read -rp "Do you want to manually edit restorelist before continuing? (:wq to save) (y/N): " edit_choice </dev/tty
    case "$edit_choice" in
        [yY]*)
            ${EDITOR:-vi} "$RESTORELIST"
            ;;
    esac
}

# Dry-run
if [ "$DRYRUN_MODE" -eq 1 ]; then
    if [ "$RESTORE_MODE" -eq 1 ]; then
        echo "[DRY-RUN] Restore would be run on the following VMs:"
    else
        echo "[DRY-RUN] Backup would be run on the following VMs:"
    fi
    cat "$BACKUPLIST"
    rm -f "$BACKUPLIST"
    exit 0
fi

# Execute backup/restore
if [ "$RESTORE_MODE" -eq 1 ]; then
    echo "Running ghettoVCB-restore with $BACKUPLIST..."
	generate_restorelist
    "$SCRIPT_DIR/ghettoVCB-restore.sh" -c "$RESTORELIST"
    ACTION="Restore"
else
    echo "Running ghettoVCB backup with $BACKUPLIST..."
    "$SCRIPT_DIR/ghettoVCB.sh" -g "$GHB_CONF" -f "$BACKUPLIST"
    ACTION="Backup"
fi

echo
echo "$ACTION completed. VMs processed:"
cat "$BACKUPLIST"
echo

rm -f "$BACKUPLIST"
rm -f "$RESTORELIST"
