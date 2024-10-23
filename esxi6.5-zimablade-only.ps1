##############################################################################################
# Build custom ESXi 6.5 ISOs for Zimablade - EXPERIMENTAL ONLY! (see esxi6.7.ps1 for Zimaboard)
# David Harrop
# October 2024
##############################################################################################

# Realtek drivers used in this repo can be verified at 
# https://vibsdepot.v-front.de & https://github.com/mcr-ksh/r8125-esxi 

# Set ESXi depot base version
$baseESXiVer = "6.5"

# Dowload Flings from Broadcom here: 
# https://community.broadcom.com/flings/home 
# or 
# https://higherlogicdownload.s3.amazonaws.com/BROADCOM/092f2b51-ca4c-4dca-abc0-070f25ade760/UploadedImages/Flings_Content/filename.zip"

# Define archive source links and files
$flingUrl = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/6-updates/"
$manualUpdateUrl = "https://api.onedrive.com/v1.0/shares/s!Asccp3ag4RnQj-c0WAirME-Ec-D8ig/root/content" # Provide your own update file and adjust link here
$manualUpdate = "ESXi650-202210001.zip"
$realtek8169 = "net51-r8169-6.011.00-2vft.510.0.0.799733-offline_bundle.zip"
$intelnic = "net-igb-5.3.2-99-offline_bundle.zip"
#$usbFling = "ESXi650-VMKUSB-NIC-FLING-39176435-16775917.zip" # giving errors, install this vib manually after build
#$realtek8168 = "net55-r8168-8.045a-napi-offline_bundle.zip" # This may clash with RTL 8169 driver

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
echo "Retrieving ESXi $baseESXiVer installation bundle (Zimablade's RTL 8169 NIC driver requires Esxi 6.5)..."
echo ""

# Add the manual download to the list of profiles 
if (!(Test-Path $manualUpdate)){Invoke-WebRequest -Uri $manualUpdateUrl -OutFile $($manualUpdate)}
Add-EsxSoftwareDepot $manualUpdate

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


if (!(Test-Path $ghettoVCB)){Invoke-WebRequest -Uri $ghettoDownloadUrl -OutFile $($ghettoVCB)}
if (!(Test-Path $realtek8169)){Invoke-WebRequest -Method "GET" $flingUrl$($realtek8169) -OutFile $($realtek8169)}
if (!(Test-Path $intelnic)){Invoke-WebRequest -Method "GET" $flingUrl$($intelnic) -OutFile $($intelnic)}
#if (!(Test-Path $usbFling)){Invoke-WebRequest -Method "GET" $flingUrl$($usbFling) -OutFile $($usbFling)}
#if (!(Test-Path $realtek8168)){Invoke-WebRequest -Method "GET" $flingUrl$($realtek8168) -OutFile $($realtek8168)}

echo ""
echo "Adding extra packages to the local depot"
echo ""

Add-EsxSoftwareDepot "$($imageProfile).zip"
Add-EsxSoftwareDepot $ghettoVCB
Add-EsxSoftwareDepot $realtek8169
Add-EsxSoftwareDepot $intelnic
#Add-EsxSoftwareDepot $usbFling
#Add-EsxSoftwareDepot $realtek8168

echo ""
echo "Creating a custom profile" 
echo ""

$newProfileName = $($imageProfile.Replace("standard", "nvme-usbnic-zimanic"))
$newProfile = New-EsxImageProfile -CloneProfile $imageProfile -name $newProfileName -Vendor "Itiligent"
Set-EsxImageProfile -ImageProfile $newProfile -AcceptanceLevel CommunitySupported

echo ""
echo "Injecting extra packages into the custom profile"
echo ""

Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "ghettoVCB" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "net51-r8169" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "net-igb" -Force
#Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "vmkusb-nic-fling" -Force
#Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "net55-r8168" -Force

echo ""
echo "Exporting the custom profile to an ISO..."
echo ""

Export-ESXImageProfile -ImageProfile $newProfile -ExportToIso -filepath "$newProfileName.iso" -Force
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

echo ""
echo "Build complete!"
echo ""
