# MFAMap — Setup Guide

MFAMap is a PowerShell script that signs into Microsoft Graph with your admin account, queries a target Entra group for authentication method registration, and generates a self-contained HTML report. No app registration, no server, no dependencies.

---

## Prerequisites

- **PowerShell 7+** (recommended) or Windows PowerShell 5.1
- A Microsoft admin account with at least **Authentication Administrator** or **Global Reader** role
- Internet access to reach Microsoft Graph

---

## Step 1 — Install the Microsoft Graph module

One-time setup:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

If prompted to trust the PSGallery repository, type `Y` and press Enter. This may take a few minutes.

---

## Step 2 — Get your group's Object ID

1. Go to [entra.microsoft.com](https://entra.microsoft.com)
2. Navigate to **Groups** and find the group you want to track
3. Open the group and copy the **Object ID** from the Overview page

---

## Step 3 — Run the script

```powershell
.\code\MFAMap.ps1 -GroupId "your-group-object-id"
```

If you see an execution policy error:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\code\MFAMap.ps1 -GroupId "your-group-object-id"
```

The script will prompt you to pick a tracking mode (1–5), sign in with your Microsoft admin account, then show a save dialog. Choose where to save — or cancel to auto-name the file in the current directory.

---

## Step 4 — Open the report

The script prints the output path on completion:

```
  Report saved to: .\mfamap_Staff_Mode1-Auth-WHfB_2026-06-01_0930.html
  Snapshot saved to: .\mfamap_Staff_Mode1-Auth-WHfB_2026-06-01_0930.json
```

Double-click the HTML file or open it in any browser. No login required.

Every report also has a **Save as PDF** button in the header — click it to export via the browser print dialog. The dark theme is preserved in the output.

---

## Recommended folder structure

Keep a folder per client or per group. MFAMap writes a JSON snapshot alongside each HTML report and automatically finds it next time you run — no extra flags needed. The delta report generates itself.

```
Reports/
  Contoso/
    mfamap_AllStaff_Mode1_2026-05-01.html
    mfamap_AllStaff_Mode1_2026-05-01.json
    mfamap_AllStaff_Mode1_2026-06-01.html        ← standard report
    mfamap_AllStaff_Mode1_2026-06-01.json        ← snapshot for next time
    mfamap_AllStaff_Mode1_2026-06-01_delta.html  ← auto-generated comparison vs May
  FabrikamLtd/
    ...
```

The delta report shows who enrolled, who lapsed, progress bars comparing then vs now, and users who joined or left the group since the last snapshot.

---

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `-GroupId` | Yes (unless `-Demo`) | Object ID of the target Entra group |
| `-Mode` | No | Pass `1`–`5` to skip the interactive mode prompt |
| `-OutputPath` | No | Set output path directly and skip the save dialog |
| `-Branded` | No | Produce a REDACTED branded report |
| `-Demo` | No | Run without connecting to Graph — uses synthetic data |

**Examples:**

```powershell
# Standard run
.\code\MFAMap.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00"

# Skip mode prompt
.\code\MFAMap.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00" -Mode 3

# Custom output path
.\code\MFAMap.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00" -OutputPath "C:\Reports\Contoso\report.html"

# REDACTED branded report
.\code\MFAMap.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00" -Branded

# Demo — preview without credentials
.\code\MFAMap.ps1 -Demo -Mode 1
.\code\MFAMap.ps1 -Demo -Mode 5 -Branded
```

---

## Running on macOS

MFAMap works on PowerShell 7 on macOS. Install it via Homebrew:

```bash
brew install --cask powershell
```

Then launch with `pwsh` and follow the same steps. The save dialog uses `osascript` on macOS and falls back to auto-naming if unavailable.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Execution policy error | Script not signed | Run with `PowerShell -ExecutionPolicy Bypass -File .\code\MFAMap.ps1 -GroupId "..."` |
| `Could not retrieve group members` | Wrong Group ID or insufficient permissions | Check the Object ID in Entra; confirm your account has Authentication Administrator or Global Reader |
| `No users found in this group` | Group has no direct user members | Confirm the group has direct user members (not nested groups) |
| `WARNING: Could not retrieve tenant name` | `Organization.Read.All` not consented | Non-fatal — report generates without the tenant name |
| Module version conflicts | Multiple Graph module versions installed | Run the cleanup below |
| Sign-in window doesn't appear | Launched from embedded terminal | The sign-in window may be behind other windows — check the taskbar |
| Save dialog doesn't appear | Headless or restricted environment | Script falls back to auto-naming in the current directory |
| Delta report not generated | No previous snapshot found in the output folder | A delta only generates when a matching `.json` snapshot exists in the same directory |

**Module cleanup:**

```powershell
Get-Module Microsoft.Graph* -ListAvailable | ForEach-Object { Uninstall-Module $_.Name -RequiredVersion $_.Version -Force -ErrorAction SilentlyContinue }
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

---

## Authentication notes

**Windows (WAM):** On Windows 10/11, `Connect-MgGraph` uses the Windows Web Account Manager — a native sign-in broker rather than a browser tab. It's aware of accounts already signed into Windows, so sign-in is often silent or just a quick account picker. Tokens are cached in Windows Credential Manager, so re-running shortly after a previous run typically skips the prompt entirely.

**Switching accounts:** If you need to sign in as a different account or switch tenants, run `Disconnect-MgGraph` manually in PowerShell before the next run.

**Consent prompt:** The first time you run against a tenant you may see a consent screen from **Microsoft Graph Command Line Tools** listing many permissions. This reflects the full history of that shared app registration in the tenant, not what MFAMap specifically requests. MFAMap only asks for these five scopes: `Organization.Read.All`, `Group.Read.All`, `GroupMember.Read.All`, `User.Read.All`, `UserAuthenticationMethod.Read.All`.
