# ☁️ Custom VMware ESXi ISO build scripts

### Inject common NIC, NVME & USB NIC drivers into ESXi ISO images.

## Instructions
 - Install PowerCLI (see below prerequisites)
 - Run the Powershell script and select from the menu your desired ESXi ISO patch level 

### ESXi 8 ISO: [esxi8.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi8.ps1) 
- Builds ESXi 8.x iso with VMWare NVME & USB NIC Fling drivers + latest GhettoVCB backup. (NIC Fling was productized in 8.x)
	- _For earlier 800 & 80U1 builds, see script notes to select the correct USB NIC Fling_

### Esxi 7 ISO: [esxi7.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi7.ps1)
- Builds ESXi 7.x iso with VMWare NVME, NIC & USB NIC Fling drivers + latest GhettoVCB backup.

### ESXi 6.7 ISO: [esxi6.7.ps1](https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/esxi6.7.ps1) (Zimaboard compatible)
- Builds ESXi 6.7 iso with VMware Community NVME & USB NIC drivers, Zimaboard Realtek 1GbE NIC driver + latest GhettoVCB backup.
- _Zimaboard users:_
  - _You may need to set full duplex on ESXi NIC & physical switch for better performance._
  - _Zimaboard's optional RTL 8125 2.5GbE NIC driver for ESXi 6.7 can be found [here](https://github.com/itiligent/ESXi-Custom-ISO/raw/main/6.7-drivers/net-r8125-9.011.00-10.vib)_
    - _To manually install 2.5GbE driver:_`esxcli software vib install -v net-r8125-9.011.00-10.vib`
    - _To manually remove 2.5GbE driver:_ `esxcli software vib remove -n net-r8125`
  
<p align="center">
  <img src="https://github.com/itiligent/ESXi-Custom-ISO/blob/main/6.7-drivers/esxi-zimaboard-screenshot.PNG" width="750" alt="Screenshot">
</p>

### 🛠️ PowerCLI & Python are prerequisites for building ESXi ISOs:

1. Ensure your local Powershell script policy will allow you to run scripts.
   ```
   Set-ExecutionPolicy Unrestricted (and select All)
   To restore default policy: Set-ExecutionPolicy RemoteSigned
   ````

2a. For ESXi 6.7 ISOs, you must OFFLINE INSTALL install **PowerCLI 12.7.0**  this using the OFFLINE install method shown below [download it here](https://developer.vmware.com/web/tool/12.7.0/vmware-powercli/) and then simply run the esxi6.7.ps1 script. ESXi 6.x ISOs DO NOT REQUIRE PYTHON steps below. 
   ```
   # 1. If a PowerCLI version later than 12.7.0 is already installed, remove this first
      (Get-Module VMware.PowerCLI -ListAvailable).RequiredModules | Uninstall-Module -Force
   # 2. Extract all the contents of the PowerCLI 12.7.0 zip directly into the below path (should be a large bunch of VMware.xxx directories - do not create another sub directory)
      %ProgramFiles%\WindowsPowerShell\Modules 
   # 3. Unblock the new PowerCLI module files  
      Get-ChildItem -Path $env:PROGRAMFILES\WindowsPowerShell\Modules\ -Recurse | Unblock-File 
```

2b. For ESXi 7.x and 8.x ISOs only, you must install the CURRENT version of VMware PowerCLI and Python:
   ```
   Install-Module VMware.PowerCLI
   ```
 
3. To install Python 3.7.9 [download from here](https://www.python.org/downloads/release/python-379/) (Run the installer and check "Add Python to PATH" a the start of the install, and at the end of the install, select "Disable path length limit"). 
  - _Scripts are tested and working with Python 3.7.9, for other versions YMMV and you must adapt the below instructions to suit._


4. Next upgrade Python PIP via Command prompt (assumes 64 bit):
   ```
   C:\Users\%username%\AppData\Local\Programs\Python\Python37\python.exe -m pip install --upgrade pip
   ```
5. Add extra Python dependencies via Command prompt (assumes 64 bit):
   ```
   C:\Users\%username%\AppData\Local\Programs\Python\Python37\Scripts\pip3.7.exe install six psutil lxml pyopenssl
   ```

6. Optional, set the python.exe path via PowerShell (assumes 64 bit):
   ```
   Set-PowerCLIConfiguration -PythonPath C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python37\python.exe
   ```

7. Run your desired version build script to start creating your custom ISO 🚀


- This repo supports creation of VMware test labs using consumer (non HCL) hardware. Not suitable for production use.
- After Broadcom's acquisition of VMWare in October 2023, the VMware Flings community download site was taken offline and its future is uncertain. A copy of the archived flings.vmware.com site can be found at https://archive.org/details/flings.vmware.com.
- The ESXi 6.7 script's additional Zimaboard RTL8168 NIC drivers were sourced from [here](https://vibsdepot.v-front.de). Optional RTL 8125 2.5GBe vibs for use with ESXi 6.7 were sourced from [here](https://github.com/mcr-ksh/r8125-esxi).


