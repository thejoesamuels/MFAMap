# EnrolWatch — Setup Guide

## What this is

A PowerShell script that signs into Microsoft Graph with your admin account, queries a target Entra group for MFA registration status, and generates a self-contained HTML report. No app registration, no server, no browser auth required.

When you run it, you're prompted to choose what to track:
- **Mode 1** — Microsoft Authenticator + Windows Hello for Business
- **Mode 2** — Windows Hello for Business only
- **Mode 3** — Microsoft Authenticator only
- **Mode 4** — Passkey (FIDO2 or Authenticator device-bound passkey)

---

## Prerequisites

- **PowerShell 7+** (recommended) or Windows PowerShell 5.1
- A Microsoft admin account with at least **Authentication Administrator** or **Global Reader** role
- Internet access to reach Microsoft Graph

---

## Step 1 — Install the Microsoft Graph module

Open PowerShell and run:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

This installs the full Microsoft Graph module. If prompted to trust the PSGallery repository, type `Y` and press Enter. This may take a few minutes.

> **Note:** EnrolWatch only loads `Microsoft.Graph.Authentication` and `Microsoft.Graph.Groups` at runtime. All other Graph calls use `Invoke-MgGraphRequest` directly to avoid module version conflicts.

---

## Step 2 — Get your group's Object ID

1. Go to [entra.microsoft.com](https://entra.microsoft.com)
2. Navigate to **Groups** and find the group containing the users you want to track
3. Open the group and copy the **Object ID** from the Overview page

---

## Step 3 — Run the script

In PowerShell, navigate to the folder containing the script and run:

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-object-id"
```

If you see an execution policy error:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\EnrolWatch.ps1 -GroupId "your-group-object-id"
```

The script will:
1. Prompt you to choose a tracking mode (1-4)
2. Open a Microsoft sign-in window — sign in with your admin account
3. Fetch the tenant name, group name, and membership
4. Check each member's authentication methods (only the ones relevant to your chosen mode)
5. Write a timestamped HTML report to the current directory

---

## Step 4 — Open the report

The script prints the exact output filename on completion:

```
  Report saved to: .\enrolwatch_Staff_Mode1-Auth-WHfB_2026-06-01_0930.html
```

Double-click the file or open it in any browser. No login required.

---

## Refreshing during a session

Re-run the script at any point:

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-object-id"
```

Each run produces a new timestamped file so previous snapshots are preserved. You won't be prompted to sign in again as long as your PowerShell session is still active. You can switch modes between runs without re-authenticating.

---

## Custom output path

Use `-OutputPath` to override the auto-generated filename:

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-object-id" -OutputPath "C:\Reports\mfa-report.html"
```

---

## Running on macOS or Linux

EnrolWatch works on PowerShell 7+ on macOS and Linux. Install PowerShell 7 via Homebrew on macOS:

```bash
brew install --cask powershell
```

Then launch it with `pwsh` and follow the same steps.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Execution policy error | Script not signed | Run with `PowerShell -ExecutionPolicy Bypass -File .\EnrolWatch.ps1 -GroupId "..."` or run `Set-ExecutionPolicy -Scope CurrentUser Unrestricted` |
| `Could not retrieve group members` | Wrong Group ID or insufficient permissions | Double-check the Object ID in Entra; confirm your account has Authentication Administrator or Global Reader |
| `No users found in this group` | Module version conflict or group has no direct user members | Reinstall modules cleanly (see below); confirm group has direct user members in Entra |
| `WARNING: Could not retrieve tenant name` | `Organization.Read.All` not consented | Non-fatal — report still generates without the tenant name |
| Module version conflicts | Multiple versions of Graph modules installed | Run the cleanup commands below |
| Sign-in window doesn't appear | Running in an embedded terminal | The WAM sign-in window may appear behind other windows — check the taskbar |
| Mode 4 shows fewer enrolments than expected | Authenticator passkeys not properly tagged | The Graph API returns this info via the Authenticator method's `authenticationMode` field — older Authenticator versions may not surface this correctly |

### Module cleanup

If you hit version conflicts, clean up and reinstall:

```powershell
Get-Module Microsoft.Graph* -ListAvailable | ForEach-Object { Uninstall-Module $_.Name -RequiredVersion $_.Version -Force -ErrorAction SilentlyContinue }
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

---

## About the consent prompt

When you sign in, you may see a consent screen from **Microsoft Graph Command Line Tools** listing a large number of permissions. This is the shared app registration that the Graph PowerShell SDK uses — the list reflects its full permission history in your tenant, not what EnrolWatch specifically requests.

EnrolWatch only requests these five scopes at runtime:
- `Organization.Read.All`
- `Group.Read.All`
- `GroupMember.Read.All`
- `User.Read.All`
- `UserAuthenticationMethod.Read.All`

If a minimal consent screen is important (e.g. running against client tenants), create a dedicated app registration and pass `-ClientId` to `Connect-MgGraph`.
