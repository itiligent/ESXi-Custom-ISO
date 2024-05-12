# ☁️ Custom VMware ESXi ISO build scripts

### Inject consumer NIC, NVME & USB NIC drivers into ESXi ISO images.
- Each script will present a menu to select which patch level to build your new ISO.

### [esxi8.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi8.ps1) 
- Builds an ESXi 8.x iso with latest NVME & USB NIC Fling drivers + latest GhettoVCB backup. (The VMware Community NIC Fling was built in to 8.x, so no need to add this.)
	- _For earlier 800 & 80U1 builds, see script notes to select the correct USB NIC Fling_

### [esxi7.ps1](https://github.com/itiligent/ESXi-Custom-ISO/blob/main/esxi7.ps1)
- Builds an ESXi 7.x iso with latest NVME, NIC & USB NIC Fling drivers + latest GhettoVCB backup.

### [esxi6.7.ps1](https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/esxi6.7.ps1) (Zimaboard compatible)
- Builds an ESXi 6.7 iso with latest NVME & USB NIC drivers, Zimaboard Realtek 1GbE NIC driver + latest GhettoVCB backup.


### 🛠️ Instructions for building ESXi ISOs:

1. Ensure your local Powershell script policy will allow you to run PS scripts.
````
Set-ExecutionPolicy Unrestricted -Scope CurrentUser #(and select All)
To restore default policy: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser 
````

2 For ESXi 6.7 ISOs, you must OFFLINE INSTALL **PowerCLI 12.7.0**  using the method shown below. [Download it here](https://developer.vmware.com/web/tool/12.7.0/vmware-powercli/). After install, simply run the esxi6.7.ps1 script. ESXi6.x ISOs DO NOT REQUIRE PYTHON steps 3->6 below. 
```
# If a PowerCLI version later than 12.7.0 is already installed, remove this first with:
    Get-Module VMware.PowerCLI -ListAvailable).RequiredModules | Uninstall-Module -Force
# Next, extract all the contents of the PowerCLI zip (a bunch of VMware.xxx directories) and copy these into the below path.
    %ProgramFiles%\WindowsPowerShell\Modules 
# Unblock the new PowerCLI module files  
    Get-ChildItem -Path $env:PROGRAMFILES\WindowsPowerShell\Modules\ -Recurse | Unblock-File 
```

For ESXi 7.x and 8.x ISOs only, you must install the CURRENT version of VMware PowerCLI and Python > 3.7.1
```
Install-Module VMware.PowerCLI -Scope CurrentUser 
Select Y to install from untrusted repo.  Install might take a long while
```

 
3. To install Python 3.7.9 [download it here](https://www.python.org/downloads/release/python-379/) (3.7.9 is shown to be stable, some versions are more buggy):
```
Run the installer and check "Add Python to PATH" a the start of the install, and at the end of the install, select "Disable path length limit". 
```

4. Next upgrade Python PIP via Command prompt (assumes 64 bit):
```
C:\Users\%username%\AppData\Local\Programs\Python\Python37\python.exe -m pip install --upgrade pip
```

5. Add the extra Python dependencies for PowerCLI via Command prompt (assumes 64 bit):
```
C:\Users\%username%\AppData\Local\Programs\Python\Python37\Scripts\pip3.7.exe install six psutil lxml pyopenssl
```

6. Adjust the PowerCLI python.exe path and Customer Improvement Program settings (assumes 64 bit):
```
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false
Set-PowerCLIConfiguration -PythonPath C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python37\python.exe
```

7. **Now you can run the script to start creating your own custom ISO!**  🚀

- Zimaboard users note:
  - You may need to set full duplex on ESXi NIC & physical switch for better performance.
  - Zimaboard's optional RTL 8125 2.5GbE NIC driver for ESXi 6.7 can be found [here](https://github.com/itiligent/ESXi-Custom-ISO/raw/main/6.7-drivers/net-r8125-9.011.00-10.vib)
    - To manually install 2.5GbE driver:`esxcli software vib install -v net-r8125-9.011.00-10.vib`
    - To manually remove 2.5GbE driver: `esxcli software vib remove -n net-r8125`
  
<p align="center">
  <img src="https://github.com/itiligent/ESXi-Custom-ISO/blob/main/6.7-drivers/esxi-zimaboard-screenshot.PNG" width="750" alt="Screenshot">
</p>

- After Broadcom's acquisition of VMWare in October 2023, the VMware Flings community download site was taken offline. The Community Flings appear to have been rolled into the Broadcom universe, but Flings now require a Broadcom user account to access. A copy of the original (archived) flings.vmware.com site can also be found at https://archive.org/details/flings.vmware.com.
- The ESXi 6.7 script's additional Zimaboard RTL8168 NIC drivers were sourced from [here](https://vibsdepot.v-front.de). Optional RTL 8125 2.5GBe vibs for use with ESXi 6.7 were sourced from [here](https://github.com/mcr-ksh/r8125-esxi).