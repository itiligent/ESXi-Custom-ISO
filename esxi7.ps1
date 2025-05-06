##############################################################################################
# Build custom ESXi 7.x ISOs for non HCL hardware
# David Harrop
# February 2024
##############################################################################################

# Set ESXi depot base version
$baseESXiVer = "7"
$TOKEN = "<insert_your_broadcom_token_here>"

# Dowload Flings from Broadcom here: 
# https://community.broadcom.com/flings/home 
# or 
# https://higherlogicdownload.s3.amazonaws.com/BROADCOM/092f2b51-ca4c-4dca-abc0-070f25ade760/UploadedImages/Flings_Content/filename.zip"

# Define source links
$flingUrl = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/7-updates/"
$nvmeFling = "nvme-community-driver_1.0.1.0-3vmw.700.1.0.15843807-component-18902434.zip"
$nicFling = "Net-Community-Driver_1.2.7.0-1vmw.700.1.0.15843807_19480755.zip"
$usbFling = "ESXi703-VMKUSB-NIC-FLING-55634242-component-19849370.zip"

# Nominate a custom esxi depot zip file:
# (Run this script in the same direcrtory as file $manualUpdate1 to build locally without downloading)
$manualUpdate1 = "ESXi-7.0U3s-24585291-standard.zip"
# Custom esxi depot zip file link:
$manualUpdateUrl1 = "https://my.microsoftpersonalcontent.com/personal/d019e1a076a71cc7/_layouts/15/download.aspx?UniqueId=6d2c3958-545b-4a8b-a694-2818ccddf3c0&Translate=false&tempauth=v1e.eyJzaXRlaWQiOiI4ODVlNTNhZC1kMmJhLTQ0MTktYjdiZS1jYmRmMTg5MjQ1OTEiLCJhcHBpZCI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDA0ODE3MTBhNCIsImF1ZCI6IjAwMDAwMDAzLTAwMDAtMGZmMS1jZTAwLTAwMDAwMDAwMDAwMC9teS5taWNyb3NvZnRwZXJzb25hbGNvbnRlbnQuY29tQDkxODgwNDBkLTZjNjctNGM1Yi1iMTEyLTM2YTMwNGI2NmRhZCIsImV4cCI6IjE3NDQ1MTQ4NjkifQ.0EH-MyFff1RKir0oC0lW6dEynLsw94C5sqoysip1od_5yngSmNZGPh8hdtbmqSikLvOE-Zvt6aHNjkHq8Ex4q27bZC9AqYWfRNISG5z8_1JQLy2ce0jnTJK0Db_5epOs4TPyGLx13ATv5dX3q2phJsYYTxp9iVhxvbzTwAqF7AJyxHi5atvKhAN9bK8ASq3S2HWmgamStQ4VIvalqumKdLMbr6tyfhixOGMzdMS44cTJyH9HG4XvA0rCrnJWtg9_dgz5Js3UQUB4zJpsRaxi08GPEps9qiVmDYc0M136H7fx1WWjuVxAJAKSn6grvI3GmXqY-oee5zzXpNvoYB-MzFVnDYkRUkfiLJKUZgYb2rpe15lDpd4nnCrq9HlRA_cwEGPmvjxoR5ZLMLRNhrMM6w.GRS9QAaWNq-HEvW_mqqRRG1NXYD6HGN-vdG0YqtAtWM&ApiVersion=2.0"

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
        echo "ESXi-7.0U3s-24585291-standard.zip was the last public download" 
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

if (!(Test-Path $nvmeFling)){Invoke-WebRequest -Method "GET" $flingUrl$($nvmeFling) -OutFile $($nvmeFling)}
if (!(Test-Path $nicFling)){Invoke-WebRequest -Method "GET" $flingUrl$($nicFling) -OutFile $($nicFling)}
if (!(Test-Path $usbFling)){Invoke-WebRequest -Method "GET" $flingUrl$($usbFling) -OutFile $($usbFling)}
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
