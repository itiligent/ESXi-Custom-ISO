##############################################################################################
# Build custom ESXi 7.x ISOs for non HCL hardware
# David Harrop
# February 2024
##############################################################################################

# Note: After Broadcom's acquisition of VMWare in October 2023, the Community Drivers download site has been 
# taken down and its future is unclear. The script below now downloads the last available flings from this repo directly.
# A copy of the entire flings.vmware.com site can be found https://archive.org/details/flings.vmware.com.

# Set ESXi depot base version
$baseESXiVer = "7"

# Define NIC/USB/NVME driver links and file names
$git7Drv = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/7-drivers/"
$nvmeFling = "nvme-community-driver_1.0.1.0-3vmw.700.1.0.15843807-component-18902434.zip"
$nicFling = "Net-Community-Driver_1.2.7.0-1vmw.700.1.0.15843807_19480755.zip"
$usbFling = "ESXi703-VMKUSB-NIC-FLING-55634242-component-19849370.zip"

# Define Ghetto VCB repo for latest release download via Github API
$releaseUrl = "https://api.github.com/repos/lamw/ghettoVCB/releases/latest"
$ghettoVCB = "vghetto-ghettoVCB-offline-bundle-7x.zip"

# Set up user agent to avoid GitHub API rate limiting issues
$headers = @{
    "User-Agent" = "PowerShell"
} | Out-Null

# Fetch the latest release information from GitHub API
$response = Invoke-RestMethod -Uri $releaseUrl -Headers $headers

# Extract the download URL for the specific asset
$ghettoDownloadUrl = $response.assets | Where-Object { $_.name -eq $ghettoVCB } | Select-Object -ExpandProperty browser_download_url

# Download the file
Invoke-WebRequest -Uri $ghettoDownloadUrl -OutFile $ghettoVCB

echo ""
echo "Retrieving a list of ESXi $baseESXiVer installation bundles to choose from, this may take a while..."
echo ""

Add-EsxSoftwareDepot https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml
$imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Descending -Property @{Expression={$_.Name.Substring(0,10)}},@{Expression={$_.CreationTime.Date}},Name

# Print a list of available profiles to choose from
for ($i = 0; $i -lt $imageProfiles.Count; $i++) {
    echo "$($i + 1). $($imageProfiles[$i].Name)"
}

# Validate the selection
do {
    $selection = [int](Read-Host "Select an ESXi image profile (1-$($imageProfiles.Count))")
} while (-not ($selection -ge 1 -and $selection -le $imageProfiles.Count))

$imageProfile = $imageProfiles[$selection - 1].Name

echo ""
echo "Downloading $imageProfile"
echo ""

if (!(Test-Path "$($imageProfile).zip")){Export-ESXImageProfile -ImageProfile $imageProfile -ExportToBundle -filepath "$($imageProfile).zip"}
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

echo ""
echo "Finished retrieving $imageProfile"
echo ""

if (!(Test-Path $nvmeFling)){Invoke-WebRequest -Method "GET" $git7Drv$($nvmeFling) -OutFile $($nvmeFling)}
if (!(Test-Path $nicFling)){Invoke-WebRequest -Method "GET" $git7Drv$($nicFling) -OutFile $($nicFling)}
if (!(Test-Path $usbFling)){Invoke-WebRequest -Method "GET" $git7Drv$($usbFling) -OutFile $($usbFling)}
if (!(Test-Path $ghettoVCB)){Invoke-WebRequest -Uri $ghettoDownloadUrl -OutFile $($ghettoVCB)}

echo ""
echo "Adding extra packages to the local depot"
echo ""

Add-EsxSoftwareDepot "$($imageProfile).zip"
Add-EsxSoftwareDepot $nvmeFling
Add-EsxSoftwareDepot $nicFling
Add-EsxSoftwareDepot $usbFling
Add-EsxSoftwareDepot $ghettoVCB

echo ""
echo "Creating a custom profile" 
echo ""

$newProfileName = $($imageProfile.Replace("standard", "nvme-nic-usb"))
$newProfile = New-EsxImageProfile -CloneProfile $imageProfile -name $newProfileName -Vendor "Itiligent"
Set-EsxImageProfile -ImageProfile $newProfile -AcceptanceLevel CommunitySupported

echo ""
echo "Injecting extra packages into the custom profile"
echo ""

Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "nvme-community" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "net-community" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "vmkusb-nic-fling" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "ghettoVCB" -Force

# USB NIC FLING BUG WORKAROUND: 
# If later than U1 usb-nic driver packages are injected, this breaks direct ISO export, however bundle creation injects fine.
# So first we create a bundle with all the drivers and then build the ISO from this bundle...
echo ""
echo "Exporting the custom profile to a custom bundle..."
echo ""

Export-ESXImageProfile -ImageProfile $newProfile -ExportToBundle -filepath "$newProfileName.zip" -Force
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

echo ""
echo "Exporting the custom bundle to an ISO..."
echo ""

# Create the iso from the bundle
Add-EsxSoftwareDepot -DepotUrl "$newProfileName.zip"
Set-EsxImageProfile -ImageProfile $newProfile -AcceptanceLevel CommunitySupported
Export-ESXImageProfile -ImageProfile $newProfile -ExportToIso -filepath "$newProfileName.iso" -Force
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

echo ""
echo "Build complete!"
echo ""