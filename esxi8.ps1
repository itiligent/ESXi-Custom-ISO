##############################################################################################
# Build custom ESXi 8.x ISOs for non HCL hardware
# David Harrop
# February 2024
##############################################################################################

# Set ESXi depot base version
$baseESXiVer = "8"
$TOKEN = ""

# Dowload Flings from Broadcom here: 
# https://support.broadcom.com/group/ecx/productdownloads?subfamily=Flings&freeDownloads=true

# Define Fling source file & link
$flingUrl = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/8-updates/" # Fling archive in case they disappear again
$usbFling = "ESXi803-VMKUSB-NIC-FLING-76444229-component-24179899.zip"

# Nominate a custom esxi depot zip file and link:
# (Run this script in the same direcrtory as file $manualUpdate1 to build locally without downloading)
#$manualUpdate1 = "ESXi-8.0U3e-24674464-standard.zip"
#$manualUpdateUrl1 = "https://itiligent-my.sharepoint.com/personal/david_itiligent_com_au/_layouts/15/guestaccess.aspx?share=Ed1VKVshlPNGu4sRc22DGmsBm1eDtdfP-PuqXB8AErs7yg&download=1" #VMware-ESXi-8.0U3e-24674464-depot.zip
$manualUpdate1 = "VMware-ESXi-8.0U3g-24859861-depot.zip"
$manualUpdateUrl1 = "https://itiligent-my.sharepoint.com/personal/david_itiligent_com_au/_layouts/15/guestaccess.aspx?share=EW_xj8c5HTFLmoOeiNsjwKgBtIhKez8HmDNQKwoH6I5etg&e=udgNQt&download=1"

echo ""
echo "Retrieving latest ESXi $baseESXiVer release information..."
echo ""

# Prompt user for update choice
do {
    echo "Choose a specific release:"
    echo "1. Manually downloaded depot $($manualUpdate1)"
    echo "2. Choose image profile from VMware online index - REQUIRES BROADCOM TOKEN"
    echo "" 
   $choice = Read-Host "Enter your choice (1-2)"
} while ($choice -notmatch "^[1-2]$")

switch ($choice) {
    "1" {
        echo ""
        echo "Downloading $($manualUpdate1) & creating ESXi depot"
        if (!(Test-Path $manualUpdate1)){Invoke-WebRequest -Uri $manualUpdateUrl1 -OutFile $($manualUpdate1)}
        Add-EsxSoftwareDepot $manualUpdate1
        Start-Sleep 2
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending
    }
    
    
    "2" {
        echo ""
        echo "Downloading vmw-depot-index.xml & building ESXi depot, please be patient..."
        # Retrieve available image profiles from VMware
        Add-EsxSoftwareDepot https://dl.broadcom.com/$TOKEN/PROD/COMP/ESX_HOST/main/vmw-depot-index.xml
        Start-Sleep 2
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending
        echo ""
    }
}

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

echo ""
echo "Adding extra packages to the local depot"
echo ""

Add-EsxSoftwareDepot "$($imageProfile).zip"
Add-EsxSoftwareDepot $usbFling

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

echo ""
echo "Exporting the custom profile to an ISO..."
echo ""

Export-ESXImageProfile -ImageProfile $newProfile -ExportToIso -filepath "$newProfileName.iso" -Force
Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot

echo ""
echo "Build complete!"
echo ""
