
### Update ESXi online:
    esxcli system maintenanceMode set -e true
    esxcli network firewall ruleset set -e true -r httpClient
    esxcli software sources profile list -d https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml | grep -i ESXi-8
    esxcli software profile update -d https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml -p PROFILE_NAME_FROM_LIST
    esxcli network firewall ruleset set -e false -r httpClient
	esxcli system maintenanceMode set -e false
	
### Update ESXi offline:
    1. Use the powershell scripts in this repo to select and download the desired offline update bundle .zip file
	2. SCP copy the bundle with SCP to the Esxi host
	3. SSH into Esxi | cd to the dirctory the bundle uploaded to  	
    4. esxcli system maintenanceMode set -e true
	5. esxcli software sources profile list -d /full_path/ESXi-update-package.zip # checks to see available profiles in the bundle
	6. TEST!:  esxcli software profile update -p ESXi_PROFILE_NAME -d /full_path/ESXi-update-package.zip --dry-run
	7. esxcli software profile update -p ESXi_PROFILE_NAME -d /full_path/ESXi-update-package.zip # updates Esxi server
	8. esxcli system maintenanceMode set -e false

### Remove incompatible Fling before upgrading ESXi, then upgrade Fling post ESXi upgrade:
	1. esxcli software vib remove -n vmkusb-nic-fling | reboot
	2. upgrade Esxi | reboot
	3. Download the appropriate Fling and SCP copy this to Esxi's /tmp dir 
	4. SSH to Esxi | cd /tmp | unzip /tmp/flingname.zip
	5. esxcli software vib install -v /tmp/vib20/vmkusb-nic-fling/filename.vib  (use full path) | reboot
 
### Manually install ghettoVCB ESXi 7.x and lower:

    Download offline bundle from https://github.com/lamw/ghettoVCB/releases and copy to /tmp on ESXi
    
    Install instructions on the developer's website cause errors, do this instead:
    unzip /tmp/vghetto-ghettoVCB-offline-bundle.zip
    esxcli software vib install -v /tmp/vib20/ghettoVCB/virtuallyGhetto_bootbank_ghettoVCB_1.0.0-0.0.0.vib -f

    Update:
    unzip /tmp/vghetto-ghettoVCB-offline-bundle.zip
    esxcli software vib update -v /tmp/vib20/ghettoVCB/virtuallyGhetto_bootbank_ghettoVCB_1.0.0-0.0.0.vib -f

    Remove:
    esxcli software vib remove -n ghettoVCB
	
## Create persistent USB NIC name mappings

Identify usb nics present:
```
esxcli network nic list |grep vusb |awk '{print $1, $8}'
vusb0 ??:??:??:??:??:??
vusb1 ??:??:??:??:??:??
```

Take thew MAC address output of the above to create the mapping. (Every time this is run it overwrites any previous mappings, so include all devices each time). 
```
esxcli system module parameters set -p "vusb0_mac=??:??:??:??:??:?? vusb1_mac=??:??:??:??:??:??" -m vmkusb_nic_fling
```

Verify mappings with
```
esxcli system module parameters list -m vmkusb_nic_fling
```

To make your current mappings persistent, use this one liner:
```
esxcli system module parameters set -p "$(esxcli network nic list |grep vusb |awk '{print $1 "_mac=" $8}' | awk 1 ORS=' ')" -m vmkusb_nic_fling
```	

### To add a USB backup datastore to ESXi:



    1. Plug in the new USB storage

    2. Get the new USB device ID from the hardware passthrough list:
	
    		esxcli hardware usb passthrough device list
	   
   		    Bus  Dev  VendorId  ProductId  Enabled  Can Connect to VM          Name
       		---  ---  --------  ---------  -------  -------------------------  ----
       		2    2    bc2       231a       true     yes 				       Seagate RSS LLC Expansion Portable
		 											(yes = passthrough enabled,
			  										   we want this disabled)
  
	3. Stop the USB arbitrator from passing through USB devices temporarily:
			/etc/init.d/usbarbitrator stop
			
    4. Prevent USB passthrough for this specific USB device using the above list output, formatted as  #:#:#:#
	
       esxcli hardware usb passthrough device disable -d 2:2:bc2:231a

	5. Start the USB arbitrator:
			/etc/init.d/usbarbitrator start

    5. Refresh storage devices list in the ESXi console and note the new USB device name for the optional next step. e.g: mpx.vmhba32:C0:T0:L0 
	
	6. If a VMFS partition not already present on the USB, update the below DEV and DATASTORE variables by running each updated line in the terminal:

 	DEV="/dev/disks/mpx.vmhba32:C0:T0:L0"
	DATASTORE_NAME="Backup"

 	7. To create the VMFS partition on the USB  
	partedUtil mklabel $DEV gpt # set the gpt label
	END_SECTOR=$(eval expr $(partedUtil getptbl "$DEV" | tail -1 | awk '{print $1 " \\* " $2 " \\* " $3}') - 1) # get disk geometry
	partedUtil setptbl $DEV gpt "1 2048 $END_SECTOR AA31E02A400F11DB9590000C2911D1B8 0" # create partition
	vmkfstools -C vmfs6 -S $DATASTORE_NAME $DEV:1 # format as vmfs6 volume

### Manually shrink a thin provisioned VMDK:

First, zero out drive free space:
- Windows VM: ```sdelete.exe -z c:```
- Linux VM: 
```
#!/bin/bash

# Zero free space on the filesystem containing ZERO_FILE_LOCATION.
# Compatible with Debian, Fedora, and other GNU/Linux distributions.

set -u

clear

# Temporary zero-filled file
ZERO_FILE_LOCATION="${HOME}/zerofile"

# Amount of free space to leave available
SAFETY_MARGIN=$((1 * 1024 * 1024 * 1024))   # 1 GiB

# Progress update interval
PROGRESS_INTERVAL=1


# Directory containing the zero file
ZERO_FILE_DIR=$(dirname "$ZERO_FILE_LOCATION")

# Determine the actual filesystem mount point containing the zero file
MOUNT_POINT=$(df -P "$ZERO_FILE_DIR" | tail -1 | awk '{print $6}')


# Return available filesystem space in bytes
get_free_space() {
    df -B1 --output=avail "$1" 2>/dev/null | tail -1 | tr -d ' '
}


# Convert bytes to human-readable units
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
            else
                printf "%.2f KiB", b / 1024;
        }'
    fi
}


# Remove zero file if interrupted
cleanup() {
    if [ -f "$ZERO_FILE_LOCATION" ]; then
        echo
        echo "Removing temporary zero file..."
        rm -f "$ZERO_FILE_LOCATION"
        sync
    fi
}

trap cleanup INT TERM


# Make sure destination directory exists
if [ ! -d "$ZERO_FILE_DIR" ]; then
    echo "ERROR: Directory does not exist:"
    echo "       $ZERO_FILE_DIR"
    exit 1
fi


# Determine available space on the filesystem containing ZERO_FILE_LOCATION
free_space=$(get_free_space "$ZERO_FILE_DIR")

if ! [[ "$free_space" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Unable to determine available space."
    exit 1
fi


# Ensure enough space remains for safety margin
if [ "$free_space" -le "$SAFETY_MARGIN" ]; then
    echo "ERROR: Not enough free space."
    echo "Available:      $(human_size "$free_space")"
    echo "Safety margin:  $(human_size "$SAFETY_MARGIN")"
    exit 1
fi


# Calculate size to write
max_file_size=$((free_space - SAFETY_MARGIN))

# dd uses 1 MiB blocks
max_file_size_mb=$((max_file_size / 1024 / 1024))
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


# Write zeros in the background
dd if=/dev/zero \
   of="$ZERO_FILE_LOCATION" \
   bs=1M \
   count="$max_file_size_mb" \
   status=none &

dd_pid=$!


# Display progress
while kill -0 "$dd_pid" 2>/dev/null; do

    if [ -f "$ZERO_FILE_LOCATION" ]; then
        current_size=$(stat -c '%s' "$ZERO_FILE_LOCATION" 2>/dev/null || echo 0)
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


if [ "$dd_status" -ne 0 ]; then
    echo
    echo
    echo "ERROR: dd failed with exit code $dd_status."
    cleanup
    exit "$dd_status"
fi


printf "\rProgress: 100%%  Written: %-10s / %-10s\n" \
    "$(human_size "$target_bytes")" \
    "$(human_size "$target_bytes")"


echo
echo "Syncing filesystem..."
sync

echo "Removing zero file..."
rm -f "$ZERO_FILE_LOCATION"

echo "Syncing filesystem..."
sync

echo "Clearing history cache ready for reimage..."
history -c && history -w

echo
echo "Zeroing complete."
echo "The VM disk can now be compacted."
echo

```

Next, shrink the zeroed free space vmdk using ESXi CLI:
- ```vmkfstools -K disk_name.vmdk```

### Full offline backup via scp (FAST one time full copy):

Direct scp copy between datastores:
```
scp -rp /vmfs/volumes/source_path/* /vmfs/volumes/USB_datastore/full_backup
```

SCP copy over network (ssh password)
```
scp -rp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /vmfs/volumes/source_path/* user@x.x.x.x:/destination_path/
```

SCP copy over the network with sshkeys (set priv key file perms with chmod 400): 
```
from a separate linux ssh host
scp -rp -i /path/to/privkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@x.x.x.1:/vmfs/volumes/datastore1/source/* root@x.x.x.2:/vmfs/volumes/datastore1/destination/

from esxi:
    scp -rp -i /path/to/privkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /vmfs/volumes/source/* user@x.x.x.x:/destination/
```

### Cloning an ESXi OS disk with a VMFS datastore present
Problem: After cloning an ESxi disk containing a VMFS datastore, the datastore is not automatically mounted.

```
esxcfg-volume -l  			# lists all available unmounted VMFS datastores
esxcfg-volume -m vmfs_label_name	# mounts the datastore till next reboot
esxcfg-volume -M vmfs_label_name	# mounts the datastore persistent

```

### Backup ESXi config

```
vim-cmd hostsvc/firmware/sync_config && vim-cmd hostsvc/firmware/backup_config
```
Next, download *configBundle*.tgz  from the http link given

### Restore ESXi config
change backup file name to configBundle.tgz and copy to configBundle.tgz to /tmp
```
vim-cmd hostsvc/maintenance_mode_enter
vim-cmd hostsvc/firmware/restore_config 0 # if restoring to same server
vim-cmd hostsvc/firmware/restore_config 1 # if restoring to different hw and/or there is a UUID mismatch
```

### Adding Rsync to ESXi for backups and much more: 
See [here](https://github.com/itiligent/RSYNC-for-ESXi) for using rsync with ESXi


### ESXi 8 homelab setup tweaks 
```
lower password quality control:  retry=5 min=1,1,1,1,1
password remember history: 0
change root password
config ntpd: 0.au.pool.ntp.org, 1.au.pool.ntp.org, 2.au.pool.ntp.org, 3.au.pool.ntp.org
start ntpd
config portgroups
change switch security (promiscious mode, mac changes, forged transmits
add passthrough devices
set power policy
config autostart and any vms


add eddsa ssh keys:
	/etc/ssh/sshd_config
		fipsmode no
		kbdinteractiveauthentication no
		challengeresponseauthentication no

	/etc/ssh/keys-root/authorized_keys
		add pub key
		/etc/init.d/SSH restart
```

### VM auto usb passthrough syntax 
```
usb.autoConnect.device0 = "0xbda:0x9210" # ssd enclosure
usb.autoConnect.device1 = "0x1e0e:0x9011" # 4g modem
usb.autoConnect.device2 = "0x4e8:0x6863" # android tether mode
usb.autoConnect.device3 = "0x152d:0x578" # Sata usb 
usb.autoConnect.device4 = "0xbda:0x8156" # RTL 2.5gbe
```
### Check Esxi NVME smart data

```
esxcli storage core device smart get -d t10.NVMe____TEAM_TM8FPK002T_________________________0200000000000000
```


