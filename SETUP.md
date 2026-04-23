# EnrolWatch — Setup Guide

## What this is

A PowerShell script that signs into Microsoft Graph with your admin account, queries a target Entra group for MFA registration status, and generates a self-contained HTML report. No app registration, no server, no browser auth. Run the script, open the file.

The output file is named automatically using the group name and a timestamp — e.g. `enrolwatch_Teaching-Staff_2025-06-01_0930.html`.

---

## Prerequisites

- Windows with PowerShell 5.1+, or PowerShell 7+ on any platform
- A Microsoft admin account with at least **Authentication Administrator** or **Global Reader** role in the target tenant
- Internet access to reach Microsoft Graph

---

## Step 1 — Install the required modules

Open PowerShell and run the following. You only need to do this once.

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
```

If prompted to trust the PSGallery repository, type `Y` and press Enter.

> If you already have the full `Microsoft.Graph` module installed, you're good — no need to install the individual modules above.
> 
> The tenant display name is fetched using `Invoke-MgGraphRequest`, which is part of `Microsoft.Graph.Authentication` — no additional module required for this.

---

## Step 2 — Get your group's Object ID

1. Go to [entra.microsoft.com](https://entra.microsoft.com)
2. Navigate to **Groups** and find the group containing the users you want to track
3. Open the group and copy the **Object ID** from the Overview page

---

## Step 3 — Run the script

In PowerShell, navigate to the folder containing `EnrolWatch.ps1` and run:

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-object-id"
```

**Example:**
```powershell
.\EnrolWatch.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00"
```

The script will:
1. Open a Microsoft sign-in window — sign in with your admin account
2. Fetch the group name and membership
3. Check each member's Authenticator and Windows Hello for Business registration
4. Write a timestamped HTML report to the current directory

---

## Step 4 — Open the report

The script prints the exact output filename on completion:

```
  Report saved to: .\enrolwatch_Teaching-Staff_2025-06-01_0930.html
```

Open it with:

```powershell
Start-Process ".\enrolwatch_Teaching-Staff_2025-06-01_0930.html"
```

Or double-click the file in Explorer / Finder. It opens in your default browser with no login required.

---

## Refreshing during a session

Just re-run the script:

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-object-id"
```

Each run produces a new timestamped file, so previous snapshots are preserved. You won't be prompted to sign in again as long as your PowerShell session is still active.

---

## Custom output path

Use `-OutputPath` to override the auto-generated filename:

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-object-id" -OutputPath "C:\Reports\mfa-report.html"
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Could not retrieve group members` | Wrong Group ID or insufficient permissions | Double-check the Object ID in Entra; confirm your account has Authentication Administrator or Global Reader |
| `No users found in this group` | Group contains only nested groups or devices, not direct user members | Confirm the group has direct user members in Entra |
| `WARNING: Could not get methods for [user]` | Transient API error for one user | Usually safe to ignore — the user will show as Not Started |
| Sign-in window doesn't appear | PowerShell execution policy blocking the script | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` then try again |
| `The term 'Get-MgUser' is not recognized` | Microsoft.Graph.Users module not installed | Run `Install-Module Microsoft.Graph.Users -Scope CurrentUser` |
| `The term 'Get-MgGroupMember' is not recognized` | Microsoft.Graph.Groups module not installed | Run `Install-Module Microsoft.Graph.Groups -Scope CurrentUser` |
| Fonts not loading in the HTML file | No internet connection when opening the file | The report uses Google Fonts — it still works but falls back to system fonts offline |
| Tenant name not showing in report | `Microsoft.Graph.Identity.DirectoryManagement` not installed | This module is not required — the script uses `Invoke-MgGraphRequest` directly. If the name is still blank, check `Organization.Read.All` was consented |

---

## Execution policy

If you see an error about the script not being allowed to run, set the execution policy for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Then re-run the script.

---

## Running on macOS or Linux

EnrolWatch works on PowerShell 7+ on macOS and Linux with no changes. Install PowerShell 7 via Homebrew on macOS:

```bash
brew install --cask powershell
```

Then launch it with `pwsh` and follow the same steps.
