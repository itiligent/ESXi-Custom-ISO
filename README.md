# ☁️ Custom VMware ESXi ISO build scripts

Add latest versions of VMware Flings for network, nvme & usb nic drivers to ESXi ISO images.

### For ESXi 8.x ISO: [esxi8.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi8.ps1) 
- Builds ESXi 8 iso with VMWare Community NVME & USB NIC drivers + latest GhettoVCB backup.
  - For earlier 800 & 80U1 builds, see script notes to select the correct USB NIC Fling

### For Esxi 7.x ISO: [esxi7.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi7.ps1)
- Builds ESXi 7 iso with VMWare Community NVME, NIC & USB NIC driver + latest GhettoVCB backup.

### For ESXi 6.7 ISO (Zimaboard compatible): [esxi6.7.ps1](https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/esxi6.7.ps1)
- Builds ESXi 6.7 with VMware Community NVME & USB NIC drivers, Zimaboard Realtek 1GbE NIC driver + latest GhettoVCB backup.
- Zimaboard users: 
  - Set full duplex on ESXi NIC & physical switch for better performance.
  - Zimaboard's optional RTL 8125 2.5GbE NIC driver for ESXi 6.7 can be found [here](https://github.com/itiligent/ESXi-Custom-ISO/raw/main/6.7-drivers/net-r8125-9.011.00-10.vib)
  - To manually install:`esxcli software vib install -v net-r8125-9.011.00-10.vib` 
  - To manually remove: `esxcli software vib remove -n net-r8125`
  
<p align="center">
  <img src="https://github.com/itiligent/ESXi-Custom-ISO/blob/main/6.7-drivers/esxi-zimaboard-screenshot.PNG" alt="Screeshot">
</p>

### 🛠️ Prerequisites for building ESXi ISOs:

VMWare's PowerCLI requires Python. As some versions can break PowerCLI, stick to what works...

1. Install *specifically* Python 3.7.9 [from here](https://www.python.org/downloads/release/python-379/) (Check "Add Python to PATH" a the start of the install and at the end select "Disable path length limit").

2. For ESXi 7.x or 8.x ISOs, Install latest VMware PowerCLI tool:
   ```
   Install-Module VMware.PowerCLI
   ```
   For ESXi 6.7 ISOs, you must offline install PowerCLI 13.1.0 [download it here](https://developer.vmware.com/web/tool/13.1.0/vmware-powercli/). 
   ```
   # If PowerCLI later than 13.1.0 is already installed, remove this first
      (Get-Module VMware.PowerCLI -ListAvailable).RequiredModules | Uninstall-Module -Force
   # Extract the contents of the downloaded PowerCLI 13.1.0 zip directly into the path below (do not create another sub directory)
      %ProgramFiles%\WindowsPowerShell\Modules 
   # Unblock the new module files  
      Get-ChildItem -Path $env:PROGRAMFILES\WindowsPowerShell\Modules\ -Recurse | Unblock-File
   ```
3. Upgrade Python PIP via Command prompt:
   ```
   C:\Users\%username%\AppData\Local\Programs\Python\Python37\python.exe -m pip install --upgrade pip
   ```
4. Add extra Python dependencies via Command prompt:
   ```
   C:\Users\%username%\AppData\Local\Programs\Python\Python37\Scripts\pip3.7.exe install six psutil lxml pyopenssl
   ```

5. Set the python.exe path via PowerShell:
   ```
   Set-PowerCLIConfiguration -PythonPath C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python37\python.exe
   ```

6. Run the desired build script to start creating your custom ISO 🚀


- This repo is for creation of VMware test labs using affordable non HCL hardware. Not suitable for production use.
- After Broadcom's acquisition of VMWare in October 2023, the VMware Flings community download site has been taken offline and its future is uncertain. A copy of the entire flings.vmware.com site now can be found at https://archive.org/details/flings.vmware.com.
- The ESXi 6.7 script's additional Zimaboard RTL8168 NIC drivers were sourced from [here](https://vibsdepot.v-front.de). Optional RTL 8125 2.5GBe vibs for use with ESXi 6.7 were sourced from [here](https://github.com/mcr-ksh/r8125-esxi).

