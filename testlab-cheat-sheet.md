
### Update ESXi online
    esxcli network firewall ruleset set -e true -r httpClient
    esxcli software sources profile list -d https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml | grep -i ESXi-7.0
    esxcli software profile update -d https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml -p PROFILE_NAME
    esxcli network firewall ruleset set -e false -r httpClient
 
### Install ghettoVCB

    Download offline bundle from https://github.com/lamw/ghettoVCB/releases and copy to /tmp on ESXi
    
    Install instructions on the developer's website dont work, instead:
    unzip /tmp/vghetto-ghettoVCB-offline-bundle.zip
    esxcli software vib install -v /tmp/vib20/ghettoVCB/virtuallyGhetto_bootbank_ghettoVCB_1.0.0-0.0.0.vib -f

    Update:
    unzip /tmp/vghetto-ghettoVCB-offline-bundle.zip
    esxcli software vib update -v /tmp/vib20/ghettoVCB/virtuallyGhetto_bootbank_ghettoVCB_1.0.0-0.0.0.vib -f

    Remove:
    esxcli software vib remove -n ghettoVCB

### To add a USB backup datastore to ESXi

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

### Full offline backup via scp (FAST one time full copy)

For direct scp copy between datastores:
```
scp -rvp /vmfs/volumes/source_path/* /vmfs/volumes/USB_datastore/full_backup
```

For scp copy over the network with sshkeys: 
```
scp -rvp -i /productLocker/dest-priv-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /vmfs/volumes/source_path/* user@x.x.x.x:/destination_path/
```

### Rsync bakups 
See [here](https://github.com/itiligent/RSYNC-for-ESXi) for using rsync with ESXi

