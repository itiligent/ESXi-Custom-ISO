# ☁️ Custom VMware ESXi ISO build scripts
## Inject consumer NIC, NVME & USB NIC drivers into ESXi ISO images.

### [esxi8.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi8.ps1) 
- Builds an ESXi 8.x iso with latest USB NIC Fling drivers.

### [esxi7.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi7.ps1)
- Builds an ESXi 7.x iso with latest NVME, NIC & USB NIC Fling drivers + latest GhettoVCB backup.

### [esxi6.7.ps1](https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/esxi6.7.ps1) (Zimaboard compatible)
- Builds an ESXi 6.7 iso with latest NVME & USB NIC drivers, Zimaboard Realtek 1GbE NIC driver + latest GhettoVCB backup.

---

### 🛠️ Using Scripts Without A Broadcom Subscription (After Free Offline Updates Discontinued)

If you have a Broadcom access token, skip to step 5.

1. Find an alternate source for your ESXi offline depot zip file
2. Set the zip file download URL in the script:
   `manualUpdateUrl1="your_custom_url.zip"`
3. Set the expected zip filename:
   `manualUpdate1="your-esxi-offline-bundle.zip"`
4. Run the script and choose **Option 1** (run the script from the same directory as your source zip file)
5. Save your your Broadcom acess between quotes in `$TOKEN = ""` and run the script with **Option 2**

> ⚠️ **Important:** Always verify the SHA256 checksum when using non-VMware sources. Official release checksums can be found [here](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere/8-0/release-notes/esxi-update-and-patch-release-notes.html).


### 🛠️ PowerCLI Environment Setup Instructions:

- The below is tested on Powershell 5.1 (the default for Windows 10 & 11). For those who have manually upgraded to a later Powershell version, you may need to use the latest PowerCLI version from here: https://developer.broadcom.com/tools/vmware-powercli/latest. Don't install a bleeding edge Python version - tested with Python 3.12.9) 

```
First enable Powershell scripts to run:
	Set-ExecutionPolicy Unrestricted -Scope CurrentUser # and select All

To restore default policy:
	Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### For ESXi 7.x and 8.x:
```
1. Install-Module VMware.PowerCLI -Scope CurrentUser # Select Y to install from untrusted repo

2. Download and install Python and check "Add Python to PATH" a the start of install 

3. At end of Python install, select "Disable path length limit"

4. Upgrade Python PIP:
	C:\Users\%username%\AppData\Local\Programs\Python\Python<MAJOR_VERSION>\python.exe -m pip install --upgrade pip

5. Add Python dependencies for PowerCLI
        C:\Users\%username%\AppData\Local\Programs\Python\Python<MAJOR_VERSION>\Scripts\pip<MAJOR_VERSION>.exe install six psutil lxml pyopenssl
	
6. Adjust the PowerCLI python.exe path and Customer Improvement Program settings
	Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
	Set-PowerCLIConfiguration -PythonPath C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python<MAJOR_VERSION>\python.exe

7. Update `$manualUpdate` and `$manualUpdateUrl` script settings to point to your ESXi source

8. Run esxi7.ps1 or esxi8.ps1 to build your ISO
```

### For ESXi 6.7
```
1. Start with a FRESH Windows system (Powercli's uninstaller does not remove everything)

2. ESXi 6.7 ISOs require an older version of Powercli.  You must OFFLINE INSTALL PowerCli:
https://developer.broadcom.com/tools/vmware-powercli/12.7.0

3. Extract contents of PowerCLI zip to %ProgramFiles%\WindowsPowerShell\Modules 

4. Run: Get-ChildItem -Path $env:PROGRAMFILES\WindowsPowerShell\Modules\ -Recurse | Unblock-File

5. Update `$manualUpdate` and `$manualUpdateUrl` script settings to point to your ESXi source

6. Run the esxi6.7.ps1 script to build the 6.7 ISO.
 ```
  
- ESXi6.7 Zimaboard/Zimablade users note:
  - Zimaboard's optional RTL 8125 2.5GbE NIC driver for ESXi 6.7 can be found [here](https://github.com/itiligent/ESXi-Custom-ISO/raw/main/6-updates/net-r8125-9.011.00-10.vib)
    - To manually install 2.5GbE driver:`esxcli software vib install -v net-r8125-9.011.00-10.vib`
    - To manually remove 2.5GbE driver: `esxcli software vib remove -n net-r8125`
    - Full duplex on the ESXi NIC & physical switch may give better performance, your milage may vary
  
<p align="center">
  <img src="https://github.com/itiligent/ESXi-Custom-ISO/blob/main/6-updates/esxi-zimaboard-screenshot.PNG" width="750" alt="Screenshot">
</p>

- VMware Community Flings have been moved into the Broadcom universe at https://community.broadcom.com/flings/home
- The ESXi 6.7 script's Zimaboard RTL8168 NIC drivers were sourced from https://vibsdepot.v-front.de
- Optional RTL 8125 2.5GBe vibs for use with ESXi 6.7 were sourced from https://github.com/mcr-ksh/r8125-esxi
