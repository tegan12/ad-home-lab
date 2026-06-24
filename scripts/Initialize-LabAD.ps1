#requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures the lab domain after promotion: DHCP, OUs, security groups, a GPO and a file share.
.DESCRIPTION
    Run this on the Domain Controller AFTER Install-LabDomain.ps1 has rebooted it. It is idempotent
    where possible (safe to re-run). When it finishes, run New-BulkADUsers.ps1 to populate users.
    Adjust the IP/scope parameters to match your lab network.
.NOTES
    Author: Tegan Wilton. Lab use only.
#>
[CmdletBinding()]
param(
    [string]$DomainDN   = 'DC=corp,DC=local',
    [string]$DnsDomain  = 'corp.local',
    [string]$DcIp       = '192.168.10.10',
    [string]$ScopeStart = '192.168.10.100',
    [string]$ScopeEnd   = '192.168.10.200',
    [string]$ScopeMask  = '255.255.255.0',
    [string]$Gateway    = '192.168.10.1'
)

Import-Module ActiveDirectory
Import-Module GroupPolicy

Write-Host "[1/4] Installing & configuring DHCP..." -ForegroundColor Cyan
Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
try {
    Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$DnsDomain" -IPAddress $DcIp -ErrorAction Stop
} catch { Write-Warning "Authorise DHCP: $($_.Exception.Message)" }
netsh dhcp add securitygroups | Out-Null
Restart-Service dhcpserver -ErrorAction SilentlyContinue
if (-not (Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object Name -eq 'LAB-LAN')) {
    Add-DhcpServerv4Scope -Name 'LAB-LAN' -StartRange $ScopeStart -EndRange $ScopeEnd -SubnetMask $ScopeMask
}
Set-DhcpServerv4OptionValue -DnsServer $DcIp -Router $Gateway -DnsDomain $DnsDomain

Write-Host "[2/4] Creating OUs and security groups..." -ForegroundColor Cyan
foreach ($dept in 'Sales', 'IT', 'HR', 'Finance') {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$dept'" -SearchBase $DomainDN -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $dept -Path $DomainDN -ProtectedFromAccidentalDeletion $false
    }
    $group = "$dept-Team"
    if (-not (Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $group -GroupScope Global -GroupCategory Security -Path "OU=$dept,$DomainDN"
    }
}

Write-Host "[3/4] Creating and linking a demo GPO..." -ForegroundColor Cyan
if (-not (Get-GPO -Name 'Lab-Baseline' -ErrorAction SilentlyContinue)) {
    New-GPO -Name 'Lab-Baseline' -Comment 'Lab baseline policy' | Out-Null
    New-GPLink -Name 'Lab-Baseline' -Target $DomainDN | Out-Null
}

Write-Host "[4/4] Creating a secured file share..." -ForegroundColor Cyan
$sharePath = 'C:\Shares\Finance'
if (-not (Test-Path $sharePath)) { New-Item -Path $sharePath -ItemType Directory -Force | Out-Null }
if (-not (Get-SmbShare -Name 'Finance' -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name 'Finance' -Path $sharePath -ChangeAccess 'Authenticated Users' -FullAccess 'Administrators' | Out-Null
}

Write-Host "`nDone. Next:" -ForegroundColor Green
Write-Host "  .\New-BulkADUsers.ps1 -CsvPath .\users.csv -Domain $DnsDomain -OUPath '$DomainDN'" -ForegroundColor Green
