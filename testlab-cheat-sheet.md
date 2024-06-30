
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
    
    Install instructions on the developer's website dont work, instead:
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

       Bus  Dev  VendorId  ProductId  Enabled  Can Connect to VM          Name
       ---  ---  --------  ---------  -------  -------------------------  ----
       2    2    bc2       231a       false    no (passthrough disabled)  Seagate RSS LLC Expansion Portable

    10. Reboot. The new USB datastore should be available in the console and USB redirection still available for other USB devices.

### Manually shrink a thin provisioned VMDK:

First, zero out drive free space:
- Linux VM: ```dd if=/dev/zero of=~/zeros.file bs=4096 status=progress && sync && rm -rf ~/zeros.file```
- Windows VM: ```sdelete.exe -z c:```

Next, shrink the zeroed free space vmdk using ESXi CLI:
- ```vmkfstools -K disk_name.vmdk```

### Full offline backup via scp (FAST one time full copy):

For direct scp copy between datastores:
```
scp -rvp /vmfs/volumes/source_path/* /vmfs/volumes/USB_datastore/full_backup
```

For scp copy over the network with sshkeys (set priv key file perms with chmod 400): 
```
scp -rvp -i /productLocker/dest-priv-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /vmfs/volumes/source_path/* user@x.x.x.x:/destination_path/
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
Next, download the newly created config bundle from the http link in the above command output

### Adding Rsync to ESXi for backups and much more: 
See [here](https://github.com/itiligent/RSYNC-for-ESXi) for using rsync with ESXi



