# ☁️ Custom VMware ESXi ISO build scripts

### Inject consumer NIC, NVME & USB NIC drivers into ESXi ISO images.
- Each script will present a menu to select which patch level to build your new ISO.

### [esxi8.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi8.ps1) 
- Builds an ESXi 8.x iso with latest NVME & USB NIC Fling drivers + latest GhettoVCB backup. (The VMware Community NIC Fling is built-in from 8.x)
	- _For earlier 800, 80U1 or 80U2 builds, see script notes to select the correct USB NIC Fling_

### [esxi7.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi7.ps1)
- Builds an ESXi 7.x iso with latest NVME, NIC & USB NIC Fling drivers + latest GhettoVCB backup.

### [esxi6.7.ps1](https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/esxi6.7.ps1) (Zimaboard compatible)
- Builds an ESXi 6.7 iso with latest NVME & USB NIC drivers, Zimaboard Realtek 1GbE NIC driver + latest GhettoVCB backup.


### 🛠️ Instructions for building ESXi ISOs:

```
1. Ensure your local Powershell script policy will allow you to run PS scripts.
	Set-ExecutionPolicy Unrestricted -Scope CurrentUser # and select All
		To restore default policy: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser 

2. (For ESXi 7 & 8 ISOs, GO TO STEP 3)
	For 6.7 ISOs you must OFFLINE INSTALL PowerCLI 12.7.0 using the method shown below.
		Download it here: https://developer.vmware.com/web/tool/12.7.0/vmware-powercli
		a. Start with a FRESH Windows system (Powercli's uninstaller does not appear to remove everything)
		b. Extract contents of PowerCLI zip to %ProgramFiles%\WindowsPowerShell\Modules 
		c. Run: Get-ChildItem -Path $env:PROGRAMFILES\WindowsPowerShell\Modules\ -Recurse | Unblock-File 
		d. Run the esxi6.7.ps1 script so build the 6.7 ISO.
 
3. For ESXi 7.x and 8.x ISOs: install the CURRENT version of VMware PowerCLI and Python
	a. Run the Python installer and check "Add Python to PATH" a the start of the install, t
	b. At the end of the Python install, select "Disable path length limit". 
	c. Run: Install-Module VMware.PowerCLI -Scope CurrentUser # Select Y to install from untrusted repo

4. Upgrade Python PIP:
	C:\Users\%username%\AppData\Local\Programs\Python\Python37\python.exe -m pip install --upgrade pip

5. Add Python dependencies for PowerCLI
	C:\Users\%username%\AppData\Local\Programs\Python\Python37\Scripts\pip3.7.exe install six psutil lxml pyopenssl

6. Adjust the PowerCLI python.exe path and Customer Improvement Program settings
	Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
	Set-PowerCLIConfiguration -PythonPath C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python37\python.exe

7. Run esxi7.ps1 or esxi8.ps1 to build your ISO
```

- Zimaboard users note:
  - Full duplex on the ESXi NIC & physical switch may give better performance, your milage may vary.
  - Zimaboard's optional RTL 8125 2.5GbE NIC driver for ESXi 6.7 can be found [here](https://github.com/itiligent/ESXi-Custom-ISO/raw/main/6.7-drivers/net-r8125-9.011.00-10.vib)
    - To manually install 2.5GbE driver:`esxcli software vib install -v net-r8125-9.011.00-10.vib`
    - To manually remove 2.5GbE driver: `esxcli software vib remove -n net-r8125`
  
<p align="center">
  <img src="https://github.com/itiligent/ESXi-Custom-ISO/blob/main/6.7-updates/esxi-zimaboard-screenshot.PNG" width="750" alt="Screenshot">
</p>

- VMware Community Flings have been moved into the Broadcom universe at https://community.broadcom.com/flings/home
- The ESXi 6.7 script's Zimaboard RTL8168 NIC drivers were sourced from https://vibsdepot.v-front.de
- Optional RTL 8125 2.5GBe vibs for use with ESXi 6.7 were sourced from https://github.com/mcr-ksh/r8125-esxi
