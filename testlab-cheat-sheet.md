
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
- Linux VM:  [Use this script](https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/refs/heads/main/vmshrink.sh)

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


