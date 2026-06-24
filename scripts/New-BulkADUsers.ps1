<#
.SYNOPSIS
    Bulk-creates Active Directory users (plus their department OU and security group) from a CSV.

.DESCRIPTION
    Reads a CSV of new starters and, for each row:
      * creates the department Organisational Unit if it does not already exist,
      * creates a department security group if it does not already exist,
      * creates the user account with a UPN and a "must change password at next logon" flag,
      * adds the user to their department security group.

    The script is idempotent (safe to re-run): existing users are skipped, and OUs/groups are only
    created when missing. It supports -WhatIf so you can preview every change before running for real.

    Written for a home-lab domain (corp.local) to demonstrate Active Directory administration and
    PowerShell automation.

.PARAMETER CsvPath
    Path to the input CSV. Required columns: FirstName, LastName, Department, JobTitle.

.PARAMETER Domain
    The AD DNS domain name, e.g. corp.local. Used to build each user's UserPrincipalName.

.PARAMETER OUPath
    Distinguished name of the container under which department OUs are created,
    e.g. "DC=corp,DC=local" (domain root) or "OU=Company,DC=corp,DC=local".

.PARAMETER DefaultPassword
    Initial password assigned to every new account. Users must change it at next logon.

.EXAMPLE
    .\New-BulkADUsers.ps1 -CsvPath .\users.csv -Domain corp.local -OUPath "DC=corp,DC=local" -WhatIf
    Previews what would be created without making any changes.

.EXAMPLE
    .\New-BulkADUsers.ps1 -CsvPath .\users.csv -Domain corp.local -OUPath "DC=corp,DC=local" -Verbose
    Creates the users for real and prints detailed progress.

.NOTES
    Author : Tegan Wilton
    Requires: ActiveDirectory PowerShell module (RSAT), run on or against a Domain Controller.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [string]$Domain,

    [Parameter(Mandatory)]
    [string]$OUPath,

    [string]$DefaultPassword = 'P@ssw0rd-Change-Me!'
)

# --- Setup -------------------------------------------------------------------
Import-Module ActiveDirectory -ErrorAction Stop

$securePwd = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
$users     = Import-Csv -Path $CsvPath

Write-Verbose "Loaded $($users.Count) row(s) from $CsvPath"

# --- Process each starter ----------------------------------------------------
foreach ($u in $users) {

    # Build account naming: first initial + surname, lowercase, no spaces, max 20 chars (SAM limit)
    $sam = ($u.FirstName.Substring(0,1) + $u.LastName).ToLower() -replace '\s', ''
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }

    $upn     = "$sam@$Domain"
    $display = "$($u.FirstName) $($u.LastName)"
    $deptOU  = "OU=$($u.Department),$OUPath"

    # 1) Ensure the department OU exists
    $ouExists = Get-ADOrganizationalUnit -Filter "Name -eq '$($u.Department)'" `
                    -SearchBase $OUPath -ErrorAction SilentlyContinue
    if (-not $ouExists) {
        if ($PSCmdlet.ShouldProcess($deptOU, 'Create Organisational Unit')) {
            New-ADOrganizationalUnit -Name $u.Department -Path $OUPath `
                -ProtectedFromAccidentalDeletion $false
            Write-Verbose "Created OU: $deptOU"
        }
    }

    # 2) Skip users that already exist (keeps the script safe to re-run)
    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Warning "User '$sam' already exists — skipping."
        continue
    }

    # 3) Create the user account
    if ($PSCmdlet.ShouldProcess($display, 'Create AD user')) {
        New-ADUser `
            -Name                  $display `
            -GivenName             $u.FirstName `
            -Surname               $u.LastName `
            -SamAccountName        $sam `
            -UserPrincipalName     $upn `
            -DisplayName           $display `
            -Title                 $u.JobTitle `
            -Department            $u.Department `
            -Path                  $deptOU `
            -AccountPassword       $securePwd `
            -ChangePasswordAtLogon $true `
            -Enabled               $true

        Write-Host "Created user: $display ($sam)" -ForegroundColor Green

        # 4) Ensure the department security group exists, then add the user
        $groupName = "$($u.Department)-Team"
        if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path $deptOU
            Write-Verbose "Created group: $groupName"
        }
        Add-ADGroupMember -Identity $groupName -Members $sam
        Write-Verbose "Added $sam to $groupName"
    }
}

Write-Host "`nDone." -ForegroundColor Cyan
