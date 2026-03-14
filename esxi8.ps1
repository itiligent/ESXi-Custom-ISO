##############################################################################################
# Build custom ESXi 8.x ISOs for non HCL hardware
# David Harrop
# March 2025
##############################################################################################

# Set ESXi depot base version
$baseESXiVer = "8"

# Download other VMWare Flings from Broadcom here: 
# https://support.broadcom.com/group/ecx/productdownloads?subfamily=Flings&freeDownloads=true

# Define Fling file names & download links (Adapt these with the versions you wish to use)
$flingUrl = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/8-updates/" # Flings archived here in case they disappear again
$usbNicFling = "ESXi803-VMKUSB-NIC-FLING-93415869-component.zip"
$realtekNicFling = "VMware-Re-Driver_1.101.01-5vmw.800.1.0.20613240.zip"

# Define the esxi depot zip file name & download link (Adapt these with the versions you wish to use)
# (Download frpm links, or run this script from the same direcrtory as the local source files)
$manualUpdate1 = "VMware-ESXi-8.0U3g-24859861-depot.zip"
$manualUpdateUrl1 = "https://itiligent-my.sharepoint.com/personal/david_itiligent_com_au/_layouts/15/guestaccess.aspx?share=EW_xj8c5HTFLmoOeiNsjwKgBtIhKez8HmDNQKwoH6I5etg&e=udgNQt&download=1"

Write-Host ""
Write-Host "Preparing local ESXi depot and package files..."
Write-Host ""

echo ""
echo "Downloading $($manualUpdate1) & creating ESXi depot"
if (!(Test-Path $manualUpdate1)){Invoke-WebRequest -Uri $manualUpdateUrl1 -OutFile $($manualUpdate1)}
Add-EsxSoftwareDepot $manualUpdate1
Start-Sleep 2
$imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending

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

if (!(Test-Path $usbNicFling)){Invoke-WebRequest -Method "GET" $flingUrl$($usbNicFling) -OutFile $($usbNicFling)}
if (!(Test-Path $realtekNicFling)){Invoke-WebRequest -Method "GET" $flingUrl$($realtekNicFling) -OutFile $($realtekNicFling)}

echo ""
echo "Adding extra packages to the local depot"
echo ""

Add-EsxSoftwareDepot "$($imageProfile).zip"
Add-EsxSoftwareDepot $usbNicFling
Add-EsxSoftwareDepot $realtekNicFling

echo ""
echo "Creating a custom profile" 
echo ""

$newProfileName = $($imageProfile.Replace("standard", "usbnic-realteknic"))
$newProfile = New-EsxImageProfile -CloneProfile $imageProfile -name $newProfileName -Vendor "Itiligent"
Set-EsxImageProfile -ImageProfile $newProfile -AcceptanceLevel CommunitySupported

echo ""
echo "Injecting extra packages into the custom profile"
echo ""

Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "vmkusb-nic-fling" -Force
Add-EsxSoftwarePackage -ImageProfile $newProfile -SoftwarePackage "if-re" -Force

echo ""
echo "Exporting the custom profile to an ISO..."
echo ""

Export-ESXImageProfile -ImageProfile $newProfile -ExportToIso -filepath "$newProfileName.iso" -Force
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

$isoPath = "$newProfileName.iso"
echo ""
echo "Build complete!"
echo "Created ISO: $isoPath"
echo ""
