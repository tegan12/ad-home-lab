#requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs AD DS and promotes this LAB VM to a new-forest Domain Controller (corp.local).
.DESCRIPTION
    !! RUN ONLY ON A DEDICATED LAB VM !!
    This installs the Active Directory Domain Services role and creates a NEW FOREST, then REBOOTS
    the machine. After it reboots, log back in and run Initialize-LabAD.ps1 to add DHCP, the OU
    structure, security groups, a GPO and a file share.
.PARAMETER DomainName
    FQDN for the new forest (default corp.local).
.PARAMETER NetbiosName
    NetBIOS domain name (default CORP).
.EXAMPLE
    .\Install-LabDomain.ps1
.NOTES
    Author: Tegan Wilton.  NEVER run on a production or personal machine — it becomes a domain controller.
#>
[CmdletBinding()]
param(
    [string]$DomainName  = 'corp.local',
    [string]$NetbiosName = 'CORP'
)

Write-Host "==============================================================" -ForegroundColor Yellow
Write-Host "  This will promote '$env:COMPUTERNAME' to a DOMAIN CONTROLLER"  -ForegroundColor Yellow
Write-Host "  for '$DomainName' and then REBOOT the machine."               -ForegroundColor Yellow
Write-Host "  Only continue on a dedicated LAB VM."                         -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Yellow
if ((Read-Host "Type YES to continue") -ne 'YES') { Write-Host 'Cancelled.' -ForegroundColor Red; return }

Write-Host "`n[1/2] Installing the AD DS role..." -ForegroundColor Cyan
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Write-Host "[2/2] Promoting to a new forest (the server will reboot at the end)..." -ForegroundColor Cyan
$dsrm = Read-Host -AsSecureString "Set a DSRM (Directory Services Restore Mode) password"

Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName                    $DomainName `
    -DomainNetbiosName             $NetbiosName `
    -SafeModeAdministratorPassword $dsrm `
    -InstallDns `
    -Force
