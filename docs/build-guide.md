# Active Directory Home Lab — Step-by-Step Build Guide

A complete walkthrough to build the lab from nothing. Take a screenshot at each ✅ step — they go
straight into the README and give you talking points for interviews.

**Time:** a weekend · **Cost:** €0 (evaluation ISOs) · **Difficulty:** beginner–intermediate

---

> ⚡ **Prefer to script it?** After building the VM (steps 0–2), you can replace the manual steps 3–7
> by running `scripts/Install-LabDomain.ps1` (installs AD DS + promotes the DC, then reboots) followed
> by `scripts/Initialize-LabAD.ps1` (DHCP, OUs, groups, GPO, share). Doing it by hand once is the
> better way to *learn* it — but the scripts show you can automate a full build.

## 0. Prerequisites

- A host PC with **16 GB RAM** ideally (8 GB works but is tight) and ~80 GB free disk.
- A hypervisor — any of: **Hyper-V** (built into Windows Pro), **VMware Workstation Player**, or
  **VirtualBox**.
- ISOs (free evaluations from Microsoft):
  - **Windows Server 2022 Evaluation** (180 days)
  - **Windows 11 Enterprise Evaluation** (90 days)
- Create an **internal/host-only virtual network** so the VMs talk to each other privately.

---

## 1. Build the Domain Controller VM

1. New VM → 2 vCPU, 4 GB RAM, 60 GB disk → attach the **Windows Server 2022** ISO.
2. Install Windows Server 2022 → choose **"Desktop Experience"** (gives you the GUI).
3. Set a strong local Administrator password and sign in.
4. ✅ **Rename the computer** to `DC01` and restart:
   ```powershell
   Rename-Computer -NewName "DC01" -Restart
   ```

## 2. Set a static IP

The DC must have a fixed address and point DNS at **itself**.

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.10.10 `
  -PrefixLength 24 -DefaultGateway 192.168.10.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1
```
✅ Screenshot `ipconfig /all`.

## 3. Install AD DS and promote to a Domain Controller

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Install-ADDSForest `
  -DomainName "corp.local" `
  -DomainNetbiosName "CORP" `
  -InstallDns `
  -Force
```
The server reboots and comes back up as a Domain Controller. **DNS is installed automatically.**
✅ Screenshot **Server Manager** showing AD DS + DNS.

## 4. Install and configure DHCP

```powershell
Install-WindowsFeature DHCP -IncludeManagementTools

# Authorise the DHCP server in AD and add the standard security groups
Add-DhcpServerInDC -DnsName "DC01.corp.local" -IPAddress 192.168.10.10
netsh dhcp add securitygroups
Restart-Service dhcpserver

# Create a scope for client machines
Add-DhcpServerv4Scope -Name "LAB-LAN" -StartRange 192.168.10.100 `
  -EndRange 192.168.10.200 -SubnetMask 255.255.255.0
Set-DhcpServerv4OptionValue -DnsServer 192.168.10.10 -Router 192.168.10.1 `
  -DnsDomain "corp.local"
```
✅ Screenshot the **DHCP** console with the active scope.

## 5. Create OUs, users and groups

You can click through **Active Directory Users and Computers (ADUC)**, but the smart move is to
**automate it** — that's your portfolio differentiator.

1. Copy `scripts/New-BulkADUsers.ps1` and `scripts/users.csv` onto the DC.
2. **Preview** first (no changes made):
   ```powershell
   .\New-BulkADUsers.ps1 -CsvPath .\users.csv -Domain corp.local -OUPath "DC=corp,DC=local" -WhatIf
   ```
3. Run it for real:
   ```powershell
   .\New-BulkADUsers.ps1 -CsvPath .\users.csv -Domain corp.local -OUPath "DC=corp,DC=local" -Verbose
   ```
✅ Screenshot the green "Created user…" output **and** ADUC showing the new OUs/users.

## 6. Create a file share with NTFS permissions

1. Create `C:\Shares\Finance` on the DC (or a member server).
2. Share it; set **Share** permissions to *Authenticated Users → Change*.
3. Set **NTFS** permissions so only the `Finance-Team` group has Modify; remove broad access.
4. From a client, map it: `net use F: \\DC01\Finance`.
✅ Screenshot the Security tab showing group-based NTFS permissions.

## 7. Apply Group Policy

Open **Group Policy Management** and create/link these GPOs:
- **Password Policy** — min length, complexity, lockout threshold (link at domain root).
- **Mapped Drive** — auto-map the Finance share for `Finance-Team` (User Config → Preferences).
- **Desktop Restriction** — e.g. hide Control Panel for a test OU (to show you can target policy).

✅ Screenshot Group Policy Management with your linked GPOs.

## 8. Build and join the Windows 11 client

1. New VM → Windows 11 Evaluation → put it on the same internal network.
2. Confirm it got a **DHCP lease** from your scope (`ipconfig`).
3. Join the domain:
   ```powershell
   Add-Computer -DomainName "corp.local" -Restart
   ```
4. Log in as one of your created users (e.g. `corp\jmurphy`) — first login forces a password change.
✅ Screenshot the client logged in on the domain.

## 9. Verify everything works

```powershell
gpupdate /force          # pull latest policy
gpresult /r              # confirm which GPOs applied
nslookup corp.local      # confirm DNS
```
✅ Screenshot `gpresult /r` showing applied policies.

---

## 10. Document & publish
- Drop your screenshots into `docs/screenshots/` and reference them in the README.
- Write 2–3 lines under **What I learned** in your own words (interviewers ask about this).
- Push to GitHub (commands at the bottom of the README) and pin the repo.

🎉 You now have a real, demonstrable Active Directory environment **and** an automation script — the
single most relevant project for an IT Support / Systems Administrator role.
