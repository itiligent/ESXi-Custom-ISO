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

# Define source links
$flingUrl = "https://raw.githubusercontent.com/itiligent/ESXi-Custom-ISO/main/8-updates/" # Fling archive in case they disappear again
$usbFling = "ESXi803-VMKUSB-NIC-FLING-76444229-component-24179899.zip"
$manualUpdate1 = "ESXi-8.0U3e-24674464-standard.zip"
$manualUpdateUrl1 = "https://my.microsoftpersonalcontent.com/personal/d019e1a076a71cc7/_layouts/15/download.aspx?UniqueId=f5954d1d-748f-435d-826d-98ce8e98b7ab&Translate=false&tempauth=v1e.eyJzaXRlaWQiOiI4ODVlNTNhZC1kMmJhLTQ0MTktYjdiZS1jYmRmMTg5MjQ1OTEiLCJhcHBpZCI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDA0ODE3MTBhNCIsImF1ZCI6IjAwMDAwMDAzLTAwMDAtMGZmMS1jZTAwLTAwMDAwMDAwMDAwMC9teS5taWNyb3NvZnRwZXJzb25hbGNvbnRlbnQuY29tQDkxODgwNDBkLTZjNjctNGM1Yi1iMTEyLTM2YTMwNGI2NmRhZCIsImV4cCI6IjE3NDQ1MTYyNDIifQ.hysKNEqutu2qoDGwPVcn-VACWYuzx--L_ru5uxcZifYEHsD4tINxB6umRO-7WvMS1NhcTqEcRtR601q6YgW_DOR-TlMzp2HeXPc7tpqRrG-fVO3z2PxQzR4B9FFluQEMPjOWccZkx5FQGWsJSaClpd8sf-sImwf7njIq7YcDYJATlfuFCZgUO88SCdjmEqzj2wqVZF6hV-OqXMQERhO9p2Bnhk99j30LjMfSJAwall3Qt2KYjVeH3kObhXaibSgaKXYPfgsmvrmkxDyzwuxJyf3d5eMEkrCLQ8136DCnayLbjoXdlXHiHYTWCMJstKwN3IXIsUQbAt-vWrnzlX8MxxiOlAOcHdGMEQHXTHfdCLLLEn55FFORJT6CR5Hnz3F-kHTAV65gSie16G_xB3ngsg.zfNP9bVAlqMK3NeJ9n_zu_XuSecUoa74g8p-o6HjYuM&ApiVersion=2.0"
# Run this script in the same direcrtory as file $manualUpdate1 to build locally without downloading    

echo ""
echo "Retrieving latest ESXi $baseESXiVer release information..."
echo ""

# Prompt user for update choice
do {
    echo "Choose a specific release:"
    echo "1. Manually downloaded depot $($manualUpdate1)"
    echo "2. Choose an image profile from VMware's online index"
    echo "" 
   $choice = Read-Host "Enter your choice (1-2)"
} while ($choice -notmatch "^[1-2]$")

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
        echo "Downloading vmw-depot-index.xml & building ESXi depot, please be patient..."
        # Retrieve available image profiles from VMware
        Add-EsxSoftwareDepot https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml
        $imageProfiles = Get-EsxImageProfile | Where-Object { $_.Name -like "ESXi-$baseESXiVer*-standard*" } | Sort-Object -Property CreationTime -Descending
        echo ""
        echo "ESXi-8.0U3e-24674464-standard was the last public download" 
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
