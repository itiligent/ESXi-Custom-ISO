##############################################################################################
# Build custom ESXi 8.x ISOs for non HCL hardware
# David Harrop
# February 2024
##############################################################################################

# Set ESXi depot base version
$baseESXiVer = "8"

# Dowload Flings from Broadcom here: 
# https://community.broadcom.com/flings/home 
# or 
# https://higherlogicdownload.s3.amazonaws.com/BROADCOM/092f2b51-ca4c-4dca-abc0-070f25ade760/UploadedImages/Flings_Content/filename.zip"

# Define Fling archive source link
$flingUrl = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/8-updates/" # Fling archive in case they disappear again

# Define NVME Fling filename - commented out as this is deprecated now
$nvmeFling = "nvme-community-driver_1.0.1.0-3vmw.700.1.0.15843807-component-18902434.zip"

# Define USB NIC Fling Filename
	# For Esxi800 builds: ESXi800-VMKUSB-NIC-FLING-64098182-component-21668107.zip
	# For ESXI80U1 builds: ESXi80U1-VMKUSB-NIC-FLING-64098092-component-21669994.zip
	# For Esxi80U2 builds: ESXi80U2-VMKUSB-NIC-FLING-67561870-component-22416446.zip
	# Before manually upgrading Esxi, Remove old fling, upgrade, then install new Fling
$usbFling = "ESXi803-VMKUSB-NIC-FLING-76444229-component-24179899.zip"

# Removed ghetoVCB support until vibs are compatible with esxi 8. Manually add ghetto scripts to ESXi in meantime.
	# Define Ghetto VCB repo for latest release download via Github API
	#$ghettoUrl = "https://api.github.com/repos/lamw/ghettoVCB/releases/latest"
	#$ghettoVCB = "vghetto-ghettoVCB-offline-bundle-8x.zip"

	# Set up user agent to avoid GitHub API rate limiting issues
	#$headers = @{
	#    "User-Agent" = "PowerShell"
	#} | Out-Null

	# Fetch the latest release information from Ghetto VCB GitHub API
	#$response = Invoke-RestMethod -Uri $ghettoUrl -Headers $headers

	# Extract Ghetto VCB download URL for the specific asset
	#$ghettoDownloadUrl = $response.assets | Where-Object { $_.name -eq $ghettoVCB } | Select-Object -ExpandProperty browser_download_url

	# Ghetto download the file
	#Invoke-WebRequest -Uri $ghettoDownloadUrl -OutFile $ghettoVCB

echo ""
echo "Retrieving ESXi $baseESXiVer installation bundles to choose from, this may take a while..."
echo ""

Add-EsxSoftwareDepot https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml
$imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending
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
echo "Finished retrieving $imageProfile"
echo ""

if (!(Test-Path $usbFling)){Invoke-WebRequest -Method "GET" $flingUrl$($usbFling) -OutFile $($usbFling)}
#if (!(Test-Path $nvmeFling)){Invoke-WebRequest -Method "GET" $flingUrl$($nvmeFling) -OutFile $($nvmeFling)}
#if (!(Test-Path $ghettoVCB)){Invoke-WebRequest -Uri $ghettoDownloadUrl -OutFile $($ghettoVCB)}

echo ""
echo "Adding extra packages to the local depot"
echo ""

Add-EsxSoftwareDepot "$($imageProfile).zip"
Add-EsxSoftwareDepot $usbFling
#Add-EsxSoftwareDepot $nvmeFling
#Add-EsxSoftwareDepot $ghettoVCB

echo ""
echo "Creating a custom profile" 
echo ""

$newProfileName = $($imageProfile.Replace("standard", "usbnic"))
$newProfile = New-EsxImageProfile -CloneProfile $imageProfile -name $newProfileName -Vendor "Itiligent"
Set-EsxImageProfile -ImageProfile $newProfile -AcceptanceLevel CommunitySupported

echo ""
echo "Injecting extra packages into the custom profile"
echo ""

Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "vmkusb-nic-fling" -Force
#Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "nvme-community" -Force
#Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "ghettoVCB" -Force

echo ""
echo "Exporting the custom profile to an ISO..."
echo ""

Export-ESXImageProfile -ImageProfile $newProfile -ExportToIso -filepath "$newProfileName.iso" -Force
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

echo ""
echo "Build complete!"
echo ""
