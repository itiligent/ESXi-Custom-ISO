
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
	6. esxcli software profile update -p ESXi_PROFILE_NAME -d /full_path/ESXi-update-package.zip # updates Esxi server

### Some updates can break Flings:
	If upgrading from 800 & 80U1, you wll also need to upgrade the Fling.
	1. esxcli software vib remove -n vmkusb-nic-fling | reboot
	2. upgrade Esxi as per above | reboot
	3. Download the appropriate Fling and SCP copy this to Esxi's /tmp dir 
	4. SSH to Esxi | cd /tmp | unzip /tmp/flingname.zip
	5. esxcli software vib install -v /tmp/vib20/vmkusb-nic-fling/filename.vib  (use full path) | reboot
 
### Manually install ghettoVCB:

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

    1. Stop the USB arbitrator from passing through USB devices temporarily:
       /etc/init.d/usbarbitrator stop

    2. Plug in the new USB storage

    3. Refresh storage devices list in the ESXi console and note the new USB device name. e.g: mpx.vmhba32:C0:T0:L0

    4. Use the new USB device name to create new GPT parition label:
       partedUtil mklabel /dev/disks/mpx.vmhba32:C0:T0:L0 gpt

    5. Use the new USB device name to calculate the total volume sectors:
       eval expr $(partedUtil getptbl /dev/disks/mpx.vmhba32:C0:T0:L0 | tail -1 | awk '{print $1 " \\* " $2 " \\* " $3}') - 1

    6. Use the sector result from above e.g 7814032064 to create the new datastore partition:
       partedUtil setptbl /dev/disks/mpx.vmhba32:C0:T0:L0 gpt "1 2048 7814032064 AA31E02A400F11DB9590000C2911D1B8 0"

    9. Format and name the new USB datastore on the new USB device:
       vmkfstools -C vmfs6 -S USB4TB /dev/disks/mpx.vmhba32:C0:T0:L0:1

    8. Get the new USB device ID from the hardware passthrough list:
       esxcli hardware usb passthrough device list
   
       Bus  Dev  VendorId  ProductId  Enabled  Can Connect to VM          Name
       ---  ---  --------  ---------  -------  -------------------------  ----
       2    2    bc2       231a       true     yes (passthrough enabled)  Seagate RSS LLC Expansion Portable

    9. Prevent USB passthrough for this specific USB device using the above list output, formatted as  #:#:#:#
       esxcli hardware usb passthrough device disable -d 2:2:bc2:231a

    10. Reboot. The new USB datastore should be available in the console and USB redirection still available for other USB devices.

### Manually shrink a thin provisioned VMDK:

First, zero out drive free space:
- Windows VM: ```sdelete.exe -z c:```
- Linux VM: 
```
#!/bin/sh
# clonevm.sh - Clone a VM on ESXi (current state only)
# Usage: ./clonevm.sh <SourceVM_Name> <ClonedVM_Name> [Datastore]

# Default datastore
DEFAULT_DATASTORE=$(esxcli storage filesystem list | awk '$1 ~ /^\/vmfs/ {print $3; exit}')

# Arguments
SRC_VM="$1"
NEW_VM="$2"
DATASTORE="${3:-$DEFAULT_DATASTORE}"

# Validate
if [ $# -lt 2 ]; then
    echo "Usage: $0 <SourceVM_Name> <ClonedVM_Name> [Datastore]"
    echo "If Datastore is omitted, default is $DEFAULT_DATASTORE"
    exit 1
fi

# Paths
SRC_PATH="/vmfs/volumes/${DATASTORE}/${SRC_VM}"
NEW_PATH="/vmfs/volumes/${DATASTORE}/${NEW_VM}"

# Check source and target
[ ! -d "$SRC_PATH" ] && { echo "ERROR: Source VM $SRC_PATH not found!"; exit 1; }
[ -d "$NEW_PATH" ] && { echo "ERROR: Target VM $NEW_PATH already exists!"; exit 1; }

echo "Cloning VM '$SRC_VM' to '$NEW_VM' on datastore '$DATASTORE'..."
mkdir "$NEW_PATH"

# Copy VMX
SRC_VMX=$(ls "$SRC_PATH"/*.vmx | head -n 1)
[ -z "$SRC_VMX" ] && { echo "ERROR: No VMX file found!"; exit 1; }
NEW_VMX="$NEW_PATH/${NEW_VM}.vmx"
cp "$SRC_VMX" "$NEW_VMX"

# Copy and update VMXF if exists
SRC_VMXF=$(ls "$SRC_PATH"/*.vmxf 2>/dev/null | head -n 1)
if [ -n "$SRC_VMXF" ]; then
    NEW_VMXF="$NEW_PATH/$(basename "$SRC_VMXF" | sed "s#$SRC_VM#$NEW_VM#")"
    cp "$SRC_VMXF" "$NEW_VMXF"
    sed -i "s#$SRC_VM#$NEW_VM#g" "$NEW_VMXF"
fi

# Clone disks
DISK_COUNT=0
for FILE in $(awk -F'"' '/fileName/ {print $2}' "$SRC_VMX"); do
    case "$FILE" in *.iso) continue ;; esac
    SRC_DISK="$SRC_PATH/$FILE"
    [ ! -f "$SRC_DISK" ] && { echo " Source disk $SRC_DISK not found, skipping"; continue; }

    if [ $DISK_COUNT -eq 0 ]; then
        NEW_DISK_NAME="${NEW_VM}.vmdk"
    else
        NEW_DISK_NAME="${NEW_VM}_disk${DISK_COUNT}.vmdk"
    fi

    echo " Cloning $SRC_DISK -> $NEW_DISK_NAME"
    vmkfstools -i "$SRC_DISK" "$NEW_PATH/$NEW_DISK_NAME" -d thin

    # Update VMX disk reference
    sed -i "s#fileName = \"$FILE\"#fileName = \"$NEW_DISK_NAME\"#" "$NEW_VMX"
    DISK_COUNT=$((DISK_COUNT + 1))
done

[ $DISK_COUNT -eq 0 ] && { echo "ERROR: No valid disks found!"; exit 1; }

# Update VMX metadata to new VM name
sed -i "s/displayName = \".*\"/displayName = \"${NEW_VM}\"/" "$NEW_VMX"
sed -i "s#^migrate.hostLog = \".*\"#migrate.hostLog = \"./${NEW_VM}.hlog\"#" "$NEW_VMX"
sed -i "s#^vmxstats.filename = \".*\"#vmxstats.filename = \"${NEW_VM}.scoreboard\"#" "$NEW_VMX"
sed -i "s#^nvram = \".*\"#nvram = \"${NEW_VM}.nvram\"#" "$NEW_VMX"

# Remove old MAC addresses
sed -i '/ethernet[0-9]\.generatedAddress/d' "$NEW_VMX"
sed -i '/ethernet[0-9]\.addressType/d' "$NEW_VMX"

# Optional: replace any remaining occurrences of the old VM name in VMX
sed -i "s#$SRC_VM#$NEW_VM#g" "$NEW_VMX"

# Register new VM
VMID=$(vim-cmd solo/registervm "$NEW_VMX")
[ -z "$VMID" ] && { echo "ERROR: Failed to register VM."; exit 1; }

echo "Clone complete. New VM registered with VMID: $VMID"
echo "Power it on with: vim-cmd vmsvc/power.on $VMID"


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
RSA ssh keys:
    scp -rp -i /productLocker/dest-priv-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /vmfs/volumes/source_path/* user@x.x.x.x:/destination_path/
EdSA ssh keys:
   scp -rp -i /productLocker/dest-priv-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAcceptedKeyTypes=+ssh-ed25519  /vmfs/volumes/source_path/* user@x.x.x.x:/destination_path/
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
change backup file name to configBundle.tgz
copy to configBundle.tgz to /tmp
vim-cmd hostsvc/maintenance_mode_enter
vim-cmd hostsvc/firmware/restore_config 0
vim-cmd hostsvc/firmware/restore_config 1 # override UUID


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

### Clone VM via CLI

```
#!/bin/sh
# clonevm.sh - Clone a VM on ESXi (current state only)
# Usage: ./clonevm.sh <SourceVM_Name> <ClonedVM_Name> [Datastore]

# Determine default datastore
DEFAULT_DATASTORE=$(esxcli storage filesystem list | awk '$1 ~ /^\/vmfs/ {print $3; exit}')

# Script arguments
SRC_VM="$1"
NEW_VM="$2"
DATASTORE="${3:-$DEFAULT_DATASTORE}"

# Validate arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <SourceVM_Name> <ClonedVM_Name> [Datastore]"
    echo "If Datastore is omitted, default is $DEFAULT_DATASTORE"
    exit 1
fi

# Paths for source and new VM
SRC_PATH="/vmfs/volumes/${DATASTORE}/${SRC_VM}"
NEW_PATH="/vmfs/volumes/${DATASTORE}/${NEW_VM}"

# Check source VM exists
if [ ! -d "$SRC_PATH" ]; then
    echo "ERROR: Source VM $SRC_PATH not found!"
    exit 1
fi

# Check target VM does not already exist
if [ -d "$NEW_PATH" ]; then
    echo "ERROR: Target VM $NEW_PATH already exists!"
    exit 1
fi

echo "Cloning VM '$SRC_VM' to '$NEW_VM' on datastore '$DATASTORE'..."
mkdir "$NEW_PATH"

# Copy VMX file
SRC_VMX=$(ls "$SRC_PATH"/*.vmx | head -n 1)
if [ -z "$SRC_VMX" ]; then
    echo "ERROR: No VMX file found in source VM folder!"
    exit 1
fi
NEW_VMX="$NEW_PATH/${NEW_VM}.vmx"
cp "$SRC_VMX" "$NEW_VMX"

# Clone disks referenced in VMX
DISK_COUNT=0
for FILE in $(awk -F'"' '/fileName/ {print $2}' "$SRC_VMX"); do
    # Skip CD-ROM/ISO files
    case "$FILE" in *.iso) continue ;; esac

    SRC_DISK="$SRC_PATH/$FILE"
    if [ ! -f "$SRC_DISK" ]; then
        echo " Source disk $SRC_DISK not found, skipping"
        continue
    fi

    if [ $DISK_COUNT -eq 0 ]; then
        NEW_DISK_NAME="${NEW_VM}.vmdk"
    else
        NEW_DISK_NAME="${NEW_VM}_disk${DISK_COUNT}.vmdk"
    fi

    echo " Cloning $SRC_DISK -> $NEW_DISK_NAME"
    vmkfstools -i "$SRC_DISK" "$NEW_PATH/$NEW_DISK_NAME" -d thin

    # Update VMX to point to the new disk
    sed -i "s#fileName = \"$FILE\"#fileName = \"$NEW_DISK_NAME\"#" "$NEW_VMX"

    DISK_COUNT=$((DISK_COUNT + 1))
done

if [ $DISK_COUNT -eq 0 ]; then
    echo "ERROR: No valid disks found to clone. Aborting."
    exit 1
fi

# Update VM display name
sed -i "s/displayName = \".*\"/displayName = \"${NEW_VM}\"/" "$NEW_VMX"

# Remove old MAC addresses
sed -i '/ethernet[0-9]\.generatedAddress/d' "$NEW_VMX"
sed -i '/ethernet[0-9]\.addressType/d' "$NEW_VMX"

# Register the new VM
VMID=$(vim-cmd solo/registervm "$NEW_VMX")
if [ -z "$VMID" ]; then
    echo "ERROR: Failed to register new VM."
    exit 1
fi

echo "Clone complete. New VM registered with VMID: $VMID"
echo "Power it on with: vim-cmd vmsvc/power.on $VMID"


```
