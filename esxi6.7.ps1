##############################################################################################
# Build custom ESXi 6.7 ISOs for non HCL hardware and Zimaboard
# David Harrop
# February 2024
##############################################################################################

# Note: After Broadcom's acquisition of VMWare in October 2023, the VMware Community Drivers download site has been 
# taken down and its future is unclear. This script now downloads saved copies of the last available flings from this repo directly.
# Realtek drivers are now also copied from this repo in case they disappear in future and can be verified
# at https://vibsdepot.v-front.de & https://github.com/mcr-ksh/r8125-esxi 
# A final archive copy of the entire flings.vmware.com site can be found https://archive.org/details/flings.vmware.com

# Set ESXi depot base version
$baseESXiVer = "6.7"

# Dowload Flings from Broadcom here: 
# https://community.broadcom.com/flings/home 
# or 
# https://higherlogicdownload.s3.amazonaws.com/BROADCOM/092f2b51-ca4c-4dca-abc0-070f25ade760/UploadedImages/Flings_Content/filename.zip"

# Define Fling archive source link
$flingUrl = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/6.7-updates/"
$usbFling = "ESXi670-VMKUSB-NIC-FLING-39203948-offline_bundle-16780994.zip"
$2024034001Url = "https://api.onedrive.com/v1.0/shares/s!Asccp3ag4RnQj7xd8Pes4eJTZhQVfg/root/content" # Provide your own update file and adjust link here
$2024034001Update = "ESXi670-202403001.zip"
$realtek8168 = "net55-r8168-8.045a-napi-offline_bundle.zip"
$intelnic = "net-igb-5.3.2-99-offline_bundle.zip"
$nvmeFling = "nvme-community-driver_1.0.1.0-1vmw.670.0.0.8169922-offline_bundle-17658145.zip"

# Define Ghetto VCB repo for latest release download via Github API
$ghettoUrl = "https://api.github.com/repos/lamw/ghettoVCB/releases/latest"
$ghettoVCB = "vghetto-ghettoVCB-offline-bundle-7x.zip"

# Set up user agent to avoid GitHub API rate limiting issues
$headers = @{
    "User-Agent" = "PowerShell"
} | Out-Null

# Fetch the latest release information from GitHub API
$response = Invoke-RestMethod -Uri $ghettoUrl -Headers $headers

# Extract the download URL for the specific asset
$ghettoDownloadUrl = $response.assets | Where-Object { $_.name -eq $ghettoVCB } | Select-Object -ExpandProperty browser_download_url

# Download the file
Invoke-WebRequest -Uri $ghettoDownloadUrl -OutFile $ghettoVCB

echo ""
echo "Retrieving ESXi $baseESXiVer installation bundles to choose from, this may take a while..."
echo ""

# TESTING: Add to the list of profiles by separately downloading the restricted 202403400 update See: https://docs.vmware.com/en/VMware-vSphere/6.7/rn/esxi670-202403001.html
# (SHA256 sums match VMmware docs)
if (!(Test-Path $2024034001Update)){Invoke-WebRequest -Uri $2024034001Url -OutFile $($2024034001Update)}
Add-EsxSoftwareDepot $2024034001Update

# Grab the list of publically available image profiles from VMware 
Add-EsxSoftwareDepot https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml
$imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } |  Sort-Object -Property CreationTime -Descending

echo ""
# Print a list of available profiles to choose from
for ($i = 0; $i -lt $imageProfiles.Count; $i++) {
    echo "$($i + 1). $($imageProfiles[$i].Name) - Created on: $($imageProfiles[$i].CreationTime)"
}

# Validate the selection
do {
    $selection = [int](Read-Host "Select an ESXi image profile (1-$($imageProfiles.Count))")
} while (-not ($selection -ge 1 -and $selection -le $imageProfiles.Count))

$imageProfile = $imageProfiles[$selection - 1].Name

echo ""
echo "Downloading $imageProfile and exporting to an image bundle "
echo ""

if (!(Test-Path "$($imageProfile).zip")){Export-ESXImageProfile -ImageProfile $imageProfile -ExportToBundle -filepath "$($imageProfile).zip"}
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

echo ""
echo "Finished retrieving latest ESXi $baseESXiVer bundle"
echo ""

if (!(Test-Path $nvmeFling)){Invoke-WebRequest -Method "GET" $flingUrl$($nvmeFling) -OutFile $($nvmeFling)}
if (!(Test-Path $usbFling)){Invoke-WebRequest -Method "GET" $flingUrl$($usbFling) -OutFile $($usbFling)}
if (!(Test-Path $realtek8168)){Invoke-WebRequest -Method "GET" $flingUrl$($realtek8168) -OutFile $($realtek8168)}
if (!(Test-Path $intelnic)){Invoke-WebRequest -Method "GET" $flingUrl$($intelnic) -OutFile $($intelnic)}
if (!(Test-Path $ghettoVCB)){Invoke-WebRequest -Uri $ghettoDownloadUrl -OutFile $($ghettoVCB)}

echo ""
echo "Adding extra packages to the local depot"
echo ""

Add-EsxSoftwareDepot "$($imageProfile).zip"
Add-EsxSoftwareDepot $nvmeFling
Add-EsxSoftwareDepot $usbFling
Add-EsxSoftwareDepot $realtek8168
Add-EsxSoftwareDepot $intelnic
Add-EsxSoftwareDepot $ghettoVCB

echo ""
echo "Creating a custom profile" 
echo ""

$newProfileName = $($imageProfile.Replace("standard", "nvme-usbnic-zimanic"))
$newProfile = New-EsxImageProfile -CloneProfile $imageProfile -name $newProfileName -Vendor "Itiligent"
Set-EsxImageProfile -ImageProfile $newProfile -AcceptanceLevel CommunitySupported

echo ""
echo "Injecting extra packages into the custom profile"
echo ""

Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "nvme-community" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "vmkusb-nic-fling" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "net55-r8168" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "net-igb" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "ghettoVCB" -Force

echo ""
echo "Exporting the custom profile to an ISO..."
echo ""

Export-ESXImageProfile -ImageProfile $newProfile -ExportToIso -filepath "$newProfileName.iso" -Force
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

echo ""
echo "Build complete!"
echo ""
