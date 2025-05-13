##############################################################################################
# Build custom ESXi 6.7 ISOs for non HCL hardware and Zimaboard
# David Harrop
# February 2024
##############################################################################################

# Realtek drivers used in this repo can be verified at 
# https://vibsdepot.v-front.de & https://github.com/mcr-ksh/r8125-esxi 

# Set ESXi depot base version
$baseESXiVer = "6.7"
$TOKEN = ""

# Dowload Flings from Broadcom here: 
# https://community.broadcom.com/flings/home 
# or 
# https://higherlogicdownload.s3.amazonaws.com/BROADCOM/092f2b51-ca4c-4dca-abc0-070f25ade760/UploadedImages/Flings_Content/filename.zip"

# Define archive source links and files
$flingUrl = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/6-updates/"
# Final 3 updates
$manualUpdate1 = "ESXi670-202503001.zip"
$manualUpdate2 = "ESXi670-202403001.zip"
$manualUpdate3 = "ESXi670-202210001.zip"
$manualUpdateUrl1 = "https://itiligent-my.sharepoint.com/personal/david_itiligent_com_au/_layouts/15/guestaccess.aspx?share=EbN6obvpKXhGsVenUCTxaPUBvVx7qU6IqkRp197kbymeEw&e=C5CFrY&download=1"
$manualUpdateUrl2 = "https://itiligent-my.sharepoint.com/personal/david_itiligent_com_au/_layouts/15/guestaccess.aspx?share=ESq3p83jFIZKuWCiJLQ3Fw0Bo3UBmftUqQxuL-8k2Vft4Q&e=IfEnTg&download=1"
$manualUpdateUrl3 = "https://itiligent-my.sharepoint.com/personal/david_itiligent_com_au/_layouts/15/guestaccess.aspx?share=EWd-oVHhuZNJtwcm1c841lUBz8dVjJRBiw4RpJNJa4f8dw&e=v9IVHx&download=1"
$usbFling = "ESXi670-VMKUSB-NIC-FLING-39203948-offline_bundle-16780994.zip"
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
echo "Retrieving latest ESXi $baseESXiVer release information..."
echo ""

# Prompt user for update choice
do {
    echo "Choose a specific release:"
    echo "1. 2025 extended support update $($manualUpdate1)"
    echo "2. 2024 extended support update $($manualUpdate2)"
    echo "3. 2022 final general support update $($manualUpdate3)"
    echo "4. Choose image profile from VMware online index - REQUIRES BROADCOM TOKEN"
    echo "" 
   $choice = Read-Host "Enter your choice (1-4)"
} while ($choice -notmatch "^[1-4]$")

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
        echo "Downloading $($manualUpdate2) & creating ESXi depot"
        if (!(Test-Path $manualUpdate2)){Invoke-WebRequest -Uri $manualUpdateUrl2 -OutFile $($manualUpdate2)}
        Add-EsxSoftwareDepot $manualUpdate2
        Start-Sleep 2
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending

    }
    
    "3" {
        echo ""
        echo "Downloading $($manualUpdate3) & creating ESXi depot"
        if (!(Test-Path $manualUpdate3)){Invoke-WebRequest -Uri $manualUpdateUrl3 -OutFile $($manualUpdate3)}
        Add-EsxSoftwareDepot $manualUpdate3
        Start-Sleep 2
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending

    }
    
    "4" {
        echo ""
        echo "Downloading vmw-depot-index.xml & building ESXi depot, please be patient..."
        # Retrieve available image profiles from VMware
        Add-EsxSoftwareDepot https://dl.broadcom.com/$TOKEN/PROD/COMP/ESX_HOST/main/vmw-depot-index.xml
        Start-Sleep 2
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending
        echo ""
        echo "ESXi-6.7.0-20221001001s-standard was the last general release" 
    }
}


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
