<#
.SYNOPSIS
   JP IDM Activation Script (IAS) - PowerShell Native Version
.DESCRIPTION
   Converted from batch script to run natively in PowerShell.
   For bugs, please message: Facebook: JP ULIT
#>

#Requires -Version 5.0

$iasver = "1.2"
$mas = "https://massgrave.dev/"

# Elevate script as admin if not already
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $args" -Verb RunAs
    exit
}

# Parse parameters
$script:_activate = $false
$script:_freeze = $false
$script:_reset = $false
$script:_unattended = $false

foreach ($arg in $args) {
    if ($arg -eq "/act") { $script:_activate = $true }
    if ($arg -eq "/frz") { $script:_freeze = $true }
    if ($arg -eq "/res") { $script:_reset = $true }
}

if ($script:_activate -or $script:_freeze -or $script:_reset) {
    $script:_unattended = $true
}

# Get User SID
$osSystem = Get-WmiObject -Class Win32_ComputerSystem
$ntAccount = New-Object System.Security.Principal.NTAccount($osSystem.UserName)
$sidObj = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
$_sid = $sidObj.Value

# Check HKCU Sync
$env:IAS_TEST = "1"
$hkcuSync = $null
if (Test-Path "HKCU:\IAS_TEST") {
    $hkcuSync = 1
}
Remove-Item "HKCU:\IAS_TEST" -ErrorAction SilentlyContinue
Remove-Item "Registry::HKEY_USERS\$_sid\IAS_TEST" -ErrorAction SilentlyContinue

# Architecture Check
$arch = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').PROCESSOR_ARCHITECTURE
if ($arch -eq "x86") {
    $CLSID = "HKCU:\Software\Classes\CLSID"
    $CLSID2 = "Registry::HKEY_USERS\$_sid\Software\Classes\CLSID"
    $HKLM = "HKLM:\Software\Internet Download Manager"
} else {
    $CLSID = "HKCU:\Software\Classes\Wow6432Node\CLSID"
    $CLSID2 = "Registry::HKEY_USERS\$_sid\Software\Classes\Wow6432Node\CLSID"
    $HKLM = "HKLM:\SOFTWARE\Wow6432Node\Internet Download Manager"
}

# IDM Path Check
$IDMan = (Get-ItemProperty -Path "Registry::HKEY_USERS\$_sid\Software\DownloadManager" -Name "ExePath" -ErrorAction SilentlyContinue).ExePath
if (-not $IDMan -or -not (Test-Path $IDMan)) {
    if ($arch -eq "x64") { $IDMan = "$env:ProgramFiles(x86)\Internet Download Manager\IDMan.exe" }
    else { $IDMan = "$env:ProgramFiles\Internet Download Manager\IDMan.exe" }
}

function Show-MainMenu {
    Clear-Host
    Write-Host ""
    Write-Host "                This script is NOT working with latest IDM." -ForegroundColor Yellow
    Write-Host "            ___________________________________________________"
    Write-Host ""
    Write-Host "               [1] Freeze Trial"
    Write-Host "               [2] Activate"
    Write-Host "               [3] Reset Activation / Trial"
    Write-Host "               ___________________________________________________"
    Write-Host ""
    Write-Host "               [4] Download IDM"
    Write-Host "               [5] Help"
    Write-Host "               [0] Exit"
    Write-Host "            ___________________________________________________"
    Write-Host ""
    
    $choice = Read-Host "             Enter a menu option in the Keyboard [1,2,3,4,5,0]"
    switch ($choice) {
        "1" { $script:_freeze = $true; Start-Activation }
        "2" { $script:_activate = $true; Start-Activation }
        "3" { Start-Reset }
        "4" { Start-Process "https://www.internetdownloadmanager.com/download.html"; Show-MainMenu }
        "5" { Start-Process "https://github.com/WindowsAddict/IDM-Activation-Script"; Start-Process "$mas/idm-activation-script"; Show-MainMenu }
        "0" { exit }
        default { Show-MainMenu }
    }
}

function Invoke-RegScan {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ActionType
    )
    
    $lockKey = if ($ActionType -eq "Lock") { 1 } else { $null }
    $deleteKey = if ($ActionType -eq "Delete") { 1 } else { $null }
    $toggle = 1
    
    $finalValues = @()
    if ($arch -eq "x86") {
        $regPaths = @("HKCU:\Software\Classes\CLSID", "Registry::HKEY_USERS\$_sid\Software\Classes\CLSID")
    } else {
        $regPaths = @("HKCU:\Software\Classes\WOW6432Node\CLSID", "Registry::HKEY_USERS\$_sid\Software\Classes\Wow6432Node\CLSID")
    }

    foreach ($regPath in $regPaths) {
        if (($regPath -match "HKEY_USERS") -and ($hkcuSync -ne $null)) { continue }
        
        Write-Host ""
        Write-Host "Searching IDM CLSID Registry Keys in $regPath"
        Write-Host ""
        
        $lockedKeys = @()
        $subKeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue -ErrorVariable lockedKeys | Where-Object { $_.PSChildName -match '^\{[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}\}$' }

        foreach ($lockedKey in $lockedKeys) {
            $leafValue = Split-Path -Path $lockedKey.TargetObject -Leaf
            $finalValues += $leafValue
            Write-Output "$leafValue - Found Locked Key"
        }

        if (-not $subKeys) { continue }
        
        $subKeysToExclude = "LocalServer32", "InProcServer32", "InProcHandler32"
        $filteredKeys = $subKeys | Where-Object { !($_.GetSubKeyNames() | Where-Object { $subKeysToExclude -contains $_ }) }

        foreach ($key in $filteredKeys) {
            $fullPath = $key.PSPath
            $keyValues = Get-ItemProperty -Path $fullPath -ErrorAction SilentlyContinue
            $defaultValue = $keyValues.PSObject.Properties | Where-Object { $_.Name -eq '(default)' } | Select-Object -ExpandProperty Value

            if (($defaultValue -match "^\d+$") -and ($key.SubKeyCount -eq 0)) {
                $finalValues += $($key.PSChildName)
                Write-Output "$($key.PSChildName) - Found Digit In Default and No Subkeys"
                continue
            }
            if (($defaultValue -match "\+|=") -and ($key.SubKeyCount -eq 0)) {
                $finalValues += $($key.PSChildName)
                Write-Output "$($key.PSChildName) - Found + or = In Default and No Subkeys"
                continue
            }
            $versionValue = Get-ItemProperty -Path "$fullPath\Version" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty '(default)' -ErrorAction SilentlyContinue
            if (($versionValue -match "^\d+$") -and ($key.SubKeyCount -eq 1)) {
                $finalValues += $($key.PSChildName)
                Write-Output "$($key.PSChildName) - Found Digit In \Version and No Other Subkeys"
                continue
            }
            $keyValues.PSObject.Properties | ForEach-Object {
                if ($_.Name -match "MData|Model|scansk|Therad") {
                    $finalValues += $($key.PSChildName)
                    Write-Output "$($key.PSChildName) - Found MData Model scansk Therad"
                    continue
                }
            }
            if (($key.ValueCount -eq 0) -and ($key.SubKeyCount -eq 0)) {
                $finalValues += $($key.PSChildName)
                Write-Output "$($key.PSChildName) - Found Empty Key"
                continue
            }
        }
    }

    $finalValues = @($finalValues | Select-Object -Unique)

    if ($finalValues) {
        Write-Host ""
        if ($lockKey -ne $null) { Write-Host "Locking IDM CLSID Registry Keys..." }
        if ($deleteKey -ne $null) { Write-Host "Deleting IDM CLSID Registry Keys..." }
        Write-Host ""
    } else {
        Write-Host "IDM CLSID Registry Keys are not found."
        return
    }

    if (($finalValues.Count -gt 20) -and ($toggle -ne $null)) {
        $lockKey = $null
        $deleteKey = 1
        Write-Host "The IDM keys count is more than 20. Deleting them now instead of locking..."
        Write-Host
    }

    foreach ($regPath in $regPaths) {
        if (($regPath -match "HKEY_USERS") -and ($hkcuSync -ne $null)) { continue }
        foreach ($finalValue in $finalValues) {
            $fullPath = Join-Path -Path $regPath -ChildPath $finalValue
            if ($fullPath -match 'HKCU:') { $rootKey = 'CurrentUser' } else { $rootKey = 'Users' }

            $position = $fullPath.IndexOf("\")
            $regKey = $fullPath.Substring($position + 1)

            if ($lockKey -ne $null) {
                if (-not (Test-Path -Path $fullPath -ErrorAction SilentlyContinue)) { New-Item -Path $fullPath -Force -ErrorAction SilentlyContinue | Out-Null }
                try {
                    Remove-Item -Path $fullPath -Force -Recurse -ErrorAction Stop
                    Write-Host "Failed - $fullPath" -BackgroundColor DarkRed -ForegroundColor white
                }
                catch {
                    Write-Host "Locked - $fullPath"
                }
            }

            if ($deleteKey -ne $null) {
                if (Test-Path -Path $fullPath) {
                    Remove-Item -Path $fullPath -Force -Recurse -ErrorAction SilentlyContinue
                    if (Test-Path -Path $fullPath) {
                        try {
                            Remove-Item -Path $fullPath -Force -Recurse -ErrorAction Stop
                            Write-Host "Deleted - $fullPath"
                        }
                        catch {
                            Write-Host "Failed - $fullPath" -BackgroundColor DarkRed -ForegroundColor white
                        }
                    } else {
                        Write-Host "Deleted - $fullPath"
                    }
                }
            }
        }
    }
}

function Start-Reset {
    Clear-Host
    Get-Process idman -ErrorAction SilentlyContinue | Stop-Process -Force
    
    Write-Host "Deleting IDM registry keys..."
    $keysToDelete = @(
        "HKCU:\Software\DownloadManager", "FName",
        "HKCU:\Software\DownloadManager", "LName",
        "HKCU:\Software\DownloadManager", "Email",
        "HKCU:\Software\DownloadManager", "Serial",
        "HKCU:\Software\DownloadManager", "scansk",
        "HKCU:\Software\DownloadManager", "tvfrdt",
        "HKCU:\Software\DownloadManager", "radxcnt",
        "HKCU:\Software\DownloadManager", "LstCheck",
        "HKCU:\Software\DownloadManager", "ptrk_scdt",
        "HKCU:\Software\DownloadManager", "LastCheckQU"
    )
    
    Remove-ItemProperty -Path "HKCU:\Software\DownloadManager" -Name @("FName","LName","Email","Serial","scansk","tvfrdt","radxcnt","LstCheck","ptrk_scdt","LastCheckQU") -ErrorAction SilentlyContinue
    Remove-Item -Path $HKLM -Force -ErrorAction SilentlyContinue

    Invoke-RegScan -ActionType "Delete"
    
    # Add back default registry
    New-Item -Path $HKLM -Force -ErrorAction SilentlyContinue
    New-ItemProperty -Path $HKLM -Name "AdvIntDriverEnabled2" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null

    Write-Host ""
    Write-Host "The IDM reset process has been completed." -ForegroundColor Green
    
    if (-not $script:_unattended) {
        Read-Host "Press Enter to return..."
        Show-MainMenu
    }
}

function Start-Activation {
    Clear-Host
    Get-Process idman -ErrorAction SilentlyContinue | Stop-Process -Force

    Invoke-RegScan -ActionType "Delete"

    # Add registry key
    New-Item -Path $HKLM -Force -ErrorAction SilentlyContinue
    New-ItemProperty -Path $HKLM -Name "AdvIntDriverEnabled2" -Value 1 -PropertyType DWORD -Force -ErrorAction SilentlyContinue | Out-Null

    if (-not $script:_freeze) {
        Write-Host "Applying registration details..."
        $fname = Get-Random -Minimum 1000 -Maximum 9999
        $lname = Get-Random -Minimum 1000 -Maximum 9999
        $email = "$fname.$lname@tonec.com"
        
        $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.ToCharArray()
        $key = -join (Get-Random -InputObject $chars -Count 20)
        $key = "$($key.Substring(0,5))-$($key.Substring(5,5))-$($key.Substring(10,5))-$($key.Substring(15,5))"

        Set-ItemProperty -Path "HKCU:\SOFTWARE\DownloadManager" -Name "FName" -Value $fname -Force
        Set-ItemProperty -Path "HKCU:\SOFTWARE\DownloadManager" -Name "LName" -Value $lname -Force
        Set-ItemProperty -Path "HKCU:\SOFTWARE\DownloadManager" -Name "Email" -Value $email -Force
        Set-ItemProperty -Path "HKCU:\SOFTWARE\DownloadManager" -Name "Serial" -Value $key -Force
    }

    # Trigger Downloads
    Write-Host "Triggering downloads to create registry entries..."
    $links = @(
        "https://www.internetdownloadmanager.com/images/idm_box_min.png",
        "https://www.internetdownloadmanager.com/register/IDMlib/images/idman_logos.png",
        "https://www.internetdownloadmanager.com/pictures/idm_about.png"
    )

    foreach ($link in $links) {
        if (Test-Path "$env:SystemRoot\Temp\temp.png") { Remove-Item "$env:SystemRoot\Temp\temp.png" -Force }
        Start-Process "$IDMan" -ArgumentList "/n /d `"$link`" /p `"$env:SystemRoot\Temp`" /f temp.png" -WindowStyle Hidden
        Start-Sleep -Seconds 2
    }

    Start-Sleep -Seconds 3
    Get-Process idman -ErrorAction SilentlyContinue | Stop-Process -Force

    Invoke-RegScan -ActionType "Lock"

    Write-Host ""
    if (-not $script:_freeze) {
        Write-Host "The IDM Activation process has been completed." -ForegroundColor Green
    } else {
        Write-Host "The IDM 30 days trial period is successfully frozen for Lifetime." -ForegroundColor Green
    }

    if (-not $script:_unattended) {
        Read-Host "Press Enter to return..."
        Show-MainMenu
    }
}

# Entry point logic matching command line arguments
if ($script:_unattended) {
    if ($script:_reset) { Start-Reset }
    elseif ($script:_activate) { $script:_freeze = $false; Start-Activation }
    elseif ($script:_freeze) { Start-Activation }
} else {
    Show-MainMenu
}
