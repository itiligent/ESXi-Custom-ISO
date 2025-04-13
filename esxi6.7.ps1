##############################################################################################
# Build custom ESXi 6.7 ISOs for non HCL hardware and Zimaboard
# David Harrop
# February 2024
##############################################################################################

# Realtek drivers used in this repo can be verified at 
# https://vibsdepot.v-front.de & https://github.com/mcr-ksh/r8125-esxi 

# Set ESXi depot base version
$baseESXiVer = "6.7"

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
$manualUpdateUrl1 = "https://my.microsoftpersonalcontent.com/personal/d019e1a076a71cc7/_layouts/15/download.aspx?UniqueId=76a71cc7-e1a0-2019-80d0-0d1e04000000&Translate=false&tempauth=v1e.eyJzaXRlaWQiOiI4ODVlNTNhZC1kMmJhLTQ0MTktYjdiZS1jYmRmMTg5MjQ1OTEiLCJhcHBpZCI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDA0ODE3MTBhNCIsImF1ZCI6IjAwMDAwMDAzLTAwMDAtMGZmMS1jZTAwLTAwMDAwMDAwMDAwMC9teS5taWNyb3NvZnRwZXJzb25hbGNvbnRlbnQuY29tQDkxODgwNDBkLTZjNjctNGM1Yi1iMTEyLTM2YTMwNGI2NmRhZCIsImV4cCI6IjE3NDQ1MTIzNzYifQ.DVoEwnAo7IsHWpl8XSas_EjEj0SLf_aSjbxFgupMJ-kCtGNDu5MHXhaurJgwxTq-lHbfVX6MtShIS0vaU0O5ZfyE_eeDq8h691IGMZcXLe1Q3L7YZ-tOPruKf9SV83PfEm9jcEHdbo-CFhhix27X5354eisOONATbGZnmyLuw6--FXLxWViwsbi1eLkLdlSbagjViGQOXMWI6-K6u26FQHKQTOFEfEqBTTfzd6yrTMMOzBextkc6vCiryTVEy1AyEuI9iDJcyRj7uwsBHLwstqmqOa8PmmS9t1N2gDGjVUYDjYC944l_haPVJ-YR7dhSGuUohuk6zYZnyhoYtDbH-ZVhGfMHXNnWbtpiGEOtnljpU6mT_PZaj8hdtHNCsNmpxxnD8CdPjzmIc08nopKE_g.yavlF59YtLI-dgLvUwnJOe4aDWPwmEJLWCNcf24oB5Q&ApiVersion=2.0"
$manualUpdateUrl2 = "https://my.microsoftpersonalcontent.com/personal/d019e1a076a71cc7/_layouts/15/download.aspx?UniqueId=76a71cc7-e1a0-2019-80d0-5dde03000000&Translate=false&tempauth=v1e.eyJzaXRlaWQiOiI4ODVlNTNhZC1kMmJhLTQ0MTktYjdiZS1jYmRmMTg5MjQ1OTEiLCJhcHBpZCI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDA0ODE3MTBhNCIsImF1ZCI6IjAwMDAwMDAzLTAwMDAtMGZmMS1jZTAwLTAwMDAwMDAwMDAwMC9teS5taWNyb3NvZnRwZXJzb25hbGNvbnRlbnQuY29tQDkxODgwNDBkLTZjNjctNGM1Yi1iMTEyLTM2YTMwNGI2NmRhZCIsImV4cCI6IjE3NDQ1MTI0ODEifQ.vhza3F11hSzQ7YgrWWkaZm9_imncjHFtgw10FItkHM5cy5M9LtehSFdpD9AXzKroMLZs0D_JjKWe0ypXr_K3J2rarZTaYJsuC1wwCTpS_N2zvNz0Ekg67sZe_TdXCsN3bwyitMzOpB8mKb63L5Wn08_BXdXjJUHOr03JPf64m0K7GmBaFUJQ0Yv-HRj9iRngKJez5d8qM7FsH3EhEIil7dhMduqhoXvVdrjyitdS5iH1Oblq6XjS52rUa-Z21Yx9rtL3m966jGNz2U2lsKGNNWmFOHS5Gsse6Sgs3ux712_9i1Qz7xP5o58dRpP0mY6bzJCfPCA1Fylk7M5DX2XFF0bVMXAXDkrmcanXFRjlKsQvUlyJiN752EMVVxMFzkMErIh1o2bvat554KKdTGOgBg.qQyABkqWF7S0DsJjR7vrP7Jz7HgMZ9Et-Zi-DVxLWc4&ApiVersion=2.0"
$manualUpdateUrl3 = "https://my.microsoftpersonalcontent.com/personal/d019e1a076a71cc7/_layouts/15/download.aspx?UniqueId=76a71cc7-e1a0-2019-80d0-0c1e04000000&Translate=false&tempauth=v1e.eyJzaXRlaWQiOiI4ODVlNTNhZC1kMmJhLTQ0MTktYjdiZS1jYmRmMTg5MjQ1OTEiLCJhcHBpZCI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDA0ODE3MTBhNCIsImF1ZCI6IjAwMDAwMDAzLTAwMDAtMGZmMS1jZTAwLTAwMDAwMDAwMDAwMC9teS5taWNyb3NvZnRwZXJzb25hbGNvbnRlbnQuY29tQDkxODgwNDBkLTZjNjctNGM1Yi1iMTEyLTM2YTMwNGI2NmRhZCIsImV4cCI6IjE3NDQ1MTI2MzEifQ.9MsFcPtOZ0fVywCom_BXh3zr5qffoF8qrVoFIqjZa2huBby1xx3aNQwGPCaq7Ay2fRqHTk7Rp0EcjLklvRFiMhtGiXekJYLjXHB5lUlQ6-N-i_QOU6Wd8D0RK5uYhamZqNN4ovsbATK4wFI0Gkw_wKErmG1BC8vyCH83jJpr4XgBy8M33kKKju7O5rB0LQevZRCdNY1UeeEv9_UQeWhUNq6eAOs3vhsQtlQSW5hJZoivYCqHlxVLFoe4yElscTziqxEbJn35u6hyf48bPy6cfRaNMzQwsa1B_L4pt_VKfOztuXlJdOl6kwtH2oSr8ixSal2pq93EL4rVkyB7VPoTRCn4A0fU64w_6Xm1kD7o4N_5KTqtVh3zsjVzQmlv0ziR5jjM_w8FfaaLV_RIGfhf5g.-m53GUEVfaBf53UAQNEYPms8Yn_qKUzRohqMxPXNlE4&ApiVersion=2.0"
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
    echo "4. Choose an older image profile from VMware's online index"
    echo "" 
   $choice = Read-Host "Enter your choice (1-4)"
} while ($choice -notmatch "^[1-4]$")

switch ($choice) {
    "1" {
        echo ""
        echo "Downloading $($manualUpdate1) & creating ESXi depot"
        if (!(Test-Path $manualUpdate1)){Invoke-WebRequest -Uri $manualUpdateUrl1 -OutFile $($manualUpdate1)}
        Add-EsxSoftwareDepot $manualUpdate1
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending
    }
    
    "2" {
        echo ""
        echo "Downloading $($manualUpdate2) & creating ESXi depot"
        if (!(Test-Path $manualUpdate2)){Invoke-WebRequest -Uri $manualUpdateUrl2 -OutFile $($manualUpdate2)}
        Add-EsxSoftwareDepot $manualUpdate2
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending

    }
    
    "3" {
        echo ""
        echo "Downloading $($manualUpdate3) & creating ESXi depot"
        if (!(Test-Path $manualUpdate3)){Invoke-WebRequest -Uri $manualUpdateUrl3 -OutFile $($manualUpdate3)}
        Add-EsxSoftwareDepot $manualUpdate3
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending

    }
    
    "4" {
        echo ""
        echo "Downloading vmw-depot-index.xml & building ESXi depot, please be patient..."
        # Retrieve available image profiles from VMware
        Add-EsxSoftwareDepot https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml
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
