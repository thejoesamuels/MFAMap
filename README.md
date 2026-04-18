# ⚡ EnrolWatch

**MFA enrolment tracker for Microsoft Entra ID drop-in sessions**

EnrolWatch generates a self-contained HTML dashboard showing MFA enrolment progress across a target Entra group. Run the script, get a file. Open it in any browser, share it with anyone, no server required.

Sign in once with your Microsoft admin credentials, point it at a group, and within seconds you have a clear view of who has enrolled, who is partially through, and — most importantly — who still needs catching.

---

## ✨ Key features

- 🗂️ **Single output file** — generates one self-contained HTML file with no dependencies
- 🔑 **Uses your existing credentials** — authenticates via `Connect-MgGraph` with your own admin account; no app registration required
- 🎯 **Group-scoped** — targets a specific Entra group, not your entire tenant
- 📛 **Group name in the report** — the output file header and browser tab show the name of the group, not just an ID
- 📁 **Auto-named output** — the HTML file is named with the group name and timestamp automatically
- 🚨 **"Still to catch" first** — users with nothing registered are surfaced at the top
- 🟡 **Partial enrolment detection** — users with only one method registered are called out separately
- ✅ **Completed section collapsed** — fully enrolled users are tucked away so they don't distract
- 📊 **Progress bar** — visual breakdown of complete, partial, and not-started at a glance
- 📤 **Fully portable** — the output HTML file can be opened, shared, or emailed with no auth required
- 🔄 **Re-run to refresh** — run the script again at any point to regenerate with fresh data

---

## 🔧 How it works

```
.\EnrolWatch.ps1 -GroupId "your-group-id"
        ↓
Connect-MgGraph  (sign in with your admin account)
        ↓
Microsoft Graph API
/organization                                           (tenant display name)
/groups/{id}                                            (group name)
/groups/{id}/members                                    (group membership)
/users/{id}/authentication/microsoftAuthenticatorMethods  (Authenticator registration)
/users/{id}/authentication/windowsHelloForBusinessMethods (WHfB registration)
        ↓
Self-contained HTML file written to disk
enrolwatch_GroupName_2025-01-01_0900.html
        ↓
Open in any browser — no auth, no server, no dependencies
```

---

## 🛡️ Permissions

EnrolWatch uses `Connect-MgGraph` with delegated permissions — it authenticates as you, using your existing admin account. No app registration is required.

The script requests four Graph scopes at runtime:

| Scope | Why it's needed |
|---|---|
| `Group.Read.All` | Read the group name and details |
| `GroupMember.Read.All` | Read the membership of the target group |
| `User.Read.All` | Resolve group member IDs to user display names and UPNs |
| `Organization.Read.All` | Read the tenant display name (via direct Graph API call — no extra module required) |
| `UserAuthenticationMethod.Read.All` | Read MFA registration details for each user |

All are read-only. The script cannot make any changes to users, groups, or authentication methods.

---

## 📋 Requirements

- **PowerShell 5.1+** or **PowerShell 7+**
- **Microsoft.Graph PowerShell modules** — see Quick Start below
- An account with at least **Authentication Administrator** or **Global Reader** role in the target tenant

---

## 🚀 Quick start

**1. Install the required modules** (one-time, run as yourself)

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
```

If prompted to trust the PSGallery repository, type `Y` and press Enter.

**2. Get your group's Object ID**

In [entra.microsoft.com](https://entra.microsoft.com) → **Groups** → find your group → copy the **Object ID** from the Overview page.

**3. Run the script**

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-object-id"
```

This will prompt you to sign in with your Microsoft admin account, then generate a timestamped HTML report in the current directory.

**4. Open the report**

The script prints the exact filename on completion. Open it with:

```powershell
Start-Process ".\enrolwatch_GroupName_2025-01-01_0900.html"
```

Or just double-click the file.

---

## ⚙️ Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-GroupId` | ✅ Yes | — | Object ID of the target Entra group |
| `-OutputPath` | No | Auto-generated | Override the output file path |

**Examples:**

```powershell
# Basic — output file named automatically from group name and timestamp
.\EnrolWatch.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00"

# Custom output path
.\EnrolWatch.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00" -OutputPath "C:\Reports\mfa-report.html"
```

---

## 📝 What counts as enrolled

| Method registered | Counted as |
|---|---|
| Microsoft Authenticator app | ✅ Authenticator App |
| Windows Hello for Business | ✅ Windows Hello |
| SMS / Voice Call / FIDO2 / TOTP only | ❌ Neither — user shown as **Not started** |

A user is marked **Fully Enrolled** only when both Authenticator App and Windows Hello for Business are registered. Users with only one method appear in the **Partially Enrolled** section.

---

## 🔒 Security

**No data leaves your machine.** The script queries Microsoft Graph directly from your PowerShell session and writes the output to a local HTML file. No third-party services, no telemetry, no logging endpoints.

**Delegated permissions only.** The script authenticates as you — if your account can only see certain users, so can the script. There are no application permissions or background processes.

**The output file contains no credentials.** The generated HTML is static — it contains only the data retrieved at generation time, with no tokens, secrets, or connection strings embedded.

**Treat the output file as internal data.** It contains names, email addresses, and MFA status of your users. Share it only with people who should have that information.

---

## 🔄 Refreshing during a session

Re-run the script at any point to generate a fresh report:

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-id"
```

Each run produces a new timestamped file so previous snapshots are preserved. The script stays signed in for the duration of your PowerShell session — you won't be prompted to sign in again unless the token has expired.

---

## 📦 Dependencies

| Module | Notes |
|---|---|
| [Microsoft.Graph.Authentication](https://www.powershellgallery.com/packages/Microsoft.Graph.Authentication) | `Connect-MgGraph` |
| [Microsoft.Graph.Groups](https://www.powershellgallery.com/packages/Microsoft.Graph.Groups) | `Get-MgGroup`, `Get-MgGroupMember` |
| [Microsoft.Graph.Users](https://www.powershellgallery.com/packages/Microsoft.Graph.Users) | `Get-MgUser` |
| [Microsoft.Graph.Identity.SignIns](https://www.powershellgallery.com/packages/Microsoft.Graph.Identity.SignIns) | `Get-MgUserAuthenticationMicrosoftAuthenticatorMethod`, `Get-MgUserAuthenticationWindowsHelloForBusinessMethod` |

---

## 👏 Credits

Designed and built by [Joe Samuels](https://joesamuels.co.uk) at [REDACTED](https://beaconit.co.uk).
