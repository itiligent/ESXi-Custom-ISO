#!/bin/sh
#
# esxi-nvme-unmap.sh
#
# Enable/disable ESXi 8.x NVMe DSM/Deallocate support and optionally
# run VMFS6 space reclamation for an existing NVMe-backed datastore.
#  
# Before running this script:
#   Run fstrim on hosts with thin provisioned disks  
#
# Default datastore:
#   Datastore1
#
# Override without editing:
#   DATASTORE="OtherDatastore" ./esxi-nvme-unmap.sh status
#
# Commands:
#   status
#   enable [--reboot] [--yes]
#   disable [--reboot] [--yes]
#   reclaim [--yes]
#
# Notes:
# - The script does NOT change the existing VMFS automatic-reclaim
#   priority/bandwidth. 
# - "reclaim" runs a manual VMFS UNMAP over free datastore blocks.
# - A manual UNMAP cannot be "undone".

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

DATASTORE="${DATASTORE:-Datastore1}"
RECLAIM_UNIT="${RECLAIM_UNIT:-200}"
DSM_KEY="/Scsi/NvmeUseDsmTp4040"

YES=0
DO_REBOOT=0

usage()
{
    cat <<EOF
Usage:
  $0 status
  $0 enable [--reboot] [--yes]
  $0 disable [--reboot] [--yes]
  $0 reclaim [--yes]

Environment overrides:
  DATASTORE=Datastore1
  RECLAIM_UNIT=200

Examples:
  $0 status
  $0 enable
  $0 enable --reboot
  $0 reclaim
  $0 disable --reboot

What the commands do:

  status
      Shows ESXi version, NvmeUseDsmTp4040 state, VMFS reclaim
      configuration, backing device and VAAI Delete support.

  enable
      Sets:
          ${DSM_KEY} = 1

      For an existing NVMe-backed VMFS datastore, reboot the host
      afterwards (or use VMware's device reclaim procedure) so the
      existing device/datastore is reinitialised with DSM enabled.

  disable
      Sets:
          ${DSM_KEY} = 0

      Reboot afterwards if you want the existing device/datastore
      reinitialised with DSM disabled.

  reclaim
      Runs:
          esxcli storage vmfs unmap
      against ${DATASTORE} to issue UNMAP for currently free VMFS blocks.

Options:
  --reboot
      Reboot the ESXi host after changing the DSM setting.

  --yes
      Do not ask for confirmation before reboot/manual UNMAP.
EOF
}

die()
{
    echo "ERROR: $*" >&2
    exit 1
}


require_root()
{
    # Parse `id` output (for root it begins with uid=0).
    ident="$(id 2>/dev/null)"

    case "$ident" in
        uid=0\(*|*" uid=0("*)
            return 0
            ;;
    esac

    # Fall back to the shell account variables if `id` is restricted.
    if [ "${USER:-}" = "root" ] || [ "${LOGNAME:-}" = "root" ]; then
        return 0
    fi

    die "This script must be run as root on the ESXi host."
}

require_esxi()
{
    esxcli system version get >/dev/null 2>&1 ||
        die "Unable to execute 'esxcli system version get'."
}

datastore_uuid()
{
    target="$(readlink -f "/vmfs/volumes/$DATASTORE" 2>/dev/null)" || return 1
    [ -n "$target" ] || return 1
    basename "$target"
}

backing_device()
{
    uuid="$(datastore_uuid)" || return 1

    esxcli storage vmfs extent list 2>/dev/null |
        awk -v u="$uuid" '
            $2 == u {
                print $4
                exit
            }
        '
}

get_dsm_value()
{
    esxcfg-advcfg -g "$DSM_KEY" 2>/dev/null |
        awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[01]$/) {
                        print $i
                        exit
                    }
                }
            }
        '
}

confirm()
{
    prompt="$1"

    [ "$YES" -eq 1 ] && return 0

    printf "%s [y/N]: " "$prompt"
    read answer
    case "$answer" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

show_status()
{
    echo
    echo "============================================================"
    echo "ESXi NVMe / VMFS reclamation status"
    echo "============================================================"
    echo

    echo "ESXi version:"
    esxcli system version get 2>&1
    echo

    echo "NVMe DSM setting:"
    esxcfg-advcfg -g "$DSM_KEY" 2>&1
    echo

    echo "Datastore:"
    echo "  Name: $DATASTORE"

    uuid="$(datastore_uuid 2>/dev/null)"
    if [ -n "$uuid" ]; then
        echo "  UUID: $uuid"
    else
        echo "  UUID: unable to determine"
    fi
    echo

    echo "VMFS automatic-reclaim configuration:"
    esxcli storage vmfs reclaim config get -l "$DATASTORE" 2>&1
    echo

    device="$(backing_device 2>/dev/null)"
    if [ -n "$device" ]; then
        echo "Backing device:"
        echo "  $device"
        echo

        echo "VAAI status:"
        esxcli storage core device vaai status get -d "$device" 2>&1
        echo
    else
        echo "Backing device:"
        echo "  Unable to determine from VMFS extent list."
        echo
    fi

    echo "Datastore capacity:"
    esxcli storage filesystem list 2>/dev/null |
        awk -v u="${uuid:-__none__}" '
            NR == 1 || $3 == u
        '
    echo

    value="$(get_dsm_value)"
    case "$value" in
        1)
            echo "Result: NvmeUseDsmTp4040 is ENABLED."
            ;;
        0)
            echo "Result: NvmeUseDsmTp4040 is DISABLED."
            ;;
        *)
            echo "Result: Unable to determine NvmeUseDsmTp4040 state."
            ;;
    esac

    echo
}

set_dsm()
{
    wanted="$1"

    current="$(get_dsm_value)"

    if [ "$current" = "$wanted" ]; then
        if [ "$wanted" = "1" ]; then
            echo "NvmeUseDsmTp4040 is already enabled."
        else
            echo "NvmeUseDsmTp4040 is already disabled."
        fi
        return 0
    fi

    echo "Setting $DSM_KEY to $wanted..."
    esxcfg-advcfg -s "$wanted" "$DSM_KEY" ||
        die "Failed to modify $DSM_KEY."

    current="$(get_dsm_value)"
    [ "$current" = "$wanted" ] ||
        die "Verification failed: expected $wanted, found '${current:-unknown}'."

    if [ "$wanted" = "1" ]; then
        echo "NVMe DSM/Deallocate support is now configured as enabled."
    else
        echo "NVMe DSM/Deallocate support is now configured as disabled."
    fi
}

reboot_if_requested()
{
    [ "$DO_REBOOT" -eq 1 ] || {
        echo
        echo "No reboot requested."
        echo "For an existing NVMe-backed datastore, reboot the ESXi host"
        echo "before relying on the new NvmeUseDsmTp4040 setting."
        return 0
    }

    echo
    echo "A host reboot will stop/restart all workloads on this ESXi host."

    if ! confirm "Reboot ESXi now?"; then
        echo "Reboot cancelled. The setting itself has been changed."
        return 0
    fi

    echo "Rebooting ESXi..."
    sync
    reboot
}

manual_reclaim()
{
    uuid="$(datastore_uuid 2>/dev/null)" ||
        die "Unable to resolve datastore '$DATASTORE'."

    device="$(backing_device 2>/dev/null)"
    [ -n "$device" ] ||
        die "Unable to determine the backing device for '$DATASTORE'."

    echo
    echo "Datastore:     $DATASTORE"
    echo "VMFS UUID:     $uuid"
    echo "Backing device: $device"
    echo "Reclaim unit:  $RECLAIM_UNIT"
    echo

    echo "Checking VAAI Delete/UNMAP support..."
    vaai="$(esxcli storage core device vaai status get -d "$device" 2>&1)"
    echo "$vaai"
    echo

    echo "$vaai" | grep -q "Delete Status: supported" ||
        die "Backing device does not report 'Delete Status: supported'."

    dsm="$(get_dsm_value)"
    if [ "$dsm" != "1" ]; then
        echo "WARNING: $DSM_KEY is not currently reported as enabled."
        echo "Manual VMFS UNMAP may therefore not deallocate blocks on the"
        echo "underlying NVMe device."
        echo
    fi

    echo "This will issue UNMAP for free VMFS blocks on '$DATASTORE'."
    echo "The operation may generate storage I/O while it runs."

    if ! confirm "Run manual VMFS UNMAP now?"; then
        echo "Manual reclaim cancelled."
        return 0
    fi

    echo
    echo "Starting VMFS UNMAP..."
    esxcli storage vmfs unmap \
        --volume-label="$DATASTORE" \
        --reclaim-unit="$RECLAIM_UNIT" ||
        die "VMFS UNMAP failed."

    echo
    echo "Manual VMFS UNMAP completed."
}

parse_options()
{
    shift

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --reboot)
                DO_REBOOT=1
                ;;
            --yes|-y)
                YES=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
}

main()
{
    require_root
    require_esxi


    command="${1:-}"

    case "$command" in
        status)
            parse_options "$@"
            show_status
            ;;

        enable)
            parse_options "$@"
            echo "Enabling ESXi NVMe DSM/Deallocate support..."
            set_dsm 1
            echo
            echo "Current datastore reclaim configuration:"
            esxcli storage vmfs reclaim config get -l "$DATASTORE" 2>&1
            reboot_if_requested
            ;;

        disable)
            parse_options "$@"
            echo "Disabling ESXi NVMe DSM/Deallocate support..."
            set_dsm 0
            reboot_if_requested
            ;;

        reclaim)
            parse_options "$@"
            manual_reclaim
            ;;

        -h|--help|help|"")
            usage
            ;;

        *)
            usage
            echo
            die "Unknown command: $command"
            ;;
    esac
}

main "$@"
