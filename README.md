# ⚡ EnrolWatch

**MFA enrolment tracker for Microsoft Entra ID**

EnrolWatch generates a self-contained HTML dashboard showing MFA enrolment progress across a target Entra group. Run the script, get a file. Open it in any browser, share it with anyone — no server, no login, no dependencies.

Two scripts are included:

| Script | Tracks |
|---|---|
| `EnrolWatch.ps1` | Microsoft Authenticator **and** Windows Hello for Business |
| `EnrolWatch-Authenticator.ps1` | Microsoft Authenticator only |

---

## ✨ Key features

- 🗂️ **Single output file** — generates one self-contained HTML file with no dependencies
- 🔑 **Uses your existing credentials** — authenticates via `Connect-MgGraph` with your own admin account; no app registration required
- 🏢 **Tenant and group name in the report** — header shows exactly which tenant and group you ran against
- 📁 **Auto-named output** — HTML file is named with the group name and timestamp automatically
- 🎯 **Group-scoped** — targets a specific Entra group, not your entire tenant
- 🚨 **"Still to catch" first** — users with nothing registered are surfaced at the top
- 🟡 **Partial enrolment detection** — users with only one method registered are called out separately (full version)
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
Invoke-MgGraphRequest — direct Graph API calls
/organization                                             (tenant display name)
/groups/{id}                                              (group display name)
/groups/{id}/members                                      (group membership)
/users/{id}                                               (user display name + UPN)
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

The script requests five Graph scopes at sign-in:

| Scope | Why it's needed |
|---|---|
| `Organization.Read.All` | Read the tenant display name |
| `Group.Read.All` | Read the group display name |
| `GroupMember.Read.All` | Read the membership of the target group |
| `User.Read.All` | Resolve member IDs to display names and UPNs |
| `UserAuthenticationMethod.Read.All` | Read MFA registration details for each user |

All are read-only. The script cannot make any changes to users, groups, or authentication methods.

---

## 📋 Requirements

- **PowerShell 7+** (recommended) or Windows PowerShell 5.1
- **Microsoft.Graph** PowerShell module — see Quick Start below
- An account with at least **Authentication Administrator** or **Global Reader** role in the target tenant

---

## 🚀 Quick start

**1. Install the Microsoft Graph module** (one-time)

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

**2. Get your group's Object ID**

In [entra.microsoft.com](https://entra.microsoft.com) → **Groups** → find your group → copy the **Object ID** from the Overview page.

**3. Run the script**

```powershell
.\EnrolWatch.ps1 -GroupId "your-group-object-id"
```

Sign in with your Microsoft admin account when prompted. The script generates a timestamped HTML report in the current directory.

**4. Open the report**

The script prints the exact filename on completion:

```
  Report saved to: .\enrolwatch_Staff_2025-06-01_0930.html
```

Double-click the file or open it in any browser.

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

# Authenticator only
.\EnrolWatch-Authenticator.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00"

# Custom output path
.\EnrolWatch.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00" -OutputPath "C:\Reports\mfa-report.html"
```

---

## 📝 What counts as enrolled

### EnrolWatch.ps1 (full version)

| Method registered | Counted as |
|---|---|
| Microsoft Authenticator app | ✅ Authenticator App |
| Windows Hello for Business | ✅ Windows Hello |
| SMS / Voice Call / FIDO2 / TOTP only | ❌ Neither — shown as **Not started** |

A user is **Fully Enrolled** only when both Authenticator and WHfB are registered. One method only = **Partially Enrolled**.

### EnrolWatch-Authenticator.ps1

| Method registered | Counted as |
|---|---|
| Microsoft Authenticator app | ✅ Registered |
| Anything else only | ❌ Not registered |

---

## 🔒 Security

**No data leaves your machine.** The script queries Microsoft Graph directly from your PowerShell session and writes output to a local HTML file. No third-party services, no telemetry, no logging endpoints.

**Delegated permissions only.** The script authenticates as you — it can only see what your account can see. No application permissions, no background processes, no scheduled jobs.

**The output file contains no credentials.** The generated HTML is static — it contains only the data retrieved at generation time. No tokens, secrets, or connection strings.

**Treat the output file as internal data.** It contains names, email addresses, and MFA status of your users. Share it only with people who should have that information.

**Note on the consent prompt.** EnrolWatch uses `Connect-MgGraph` which routes through the shared Microsoft Graph Command Line Tools app registration. The consent screen may show a large list of permissions — these reflect the full history of that shared app in your tenant, not what EnrolWatch specifically requests. Only the five scopes listed above are requested at runtime.

---

## 🔄 Refreshing during a session

Re-run the script to generate a fresh report. Each run produces a new timestamped file so previous snapshots are preserved. The script stays signed in for the duration of your PowerShell session — you won't be prompted to sign in again unless the token has expired.

---

## 📦 Dependencies

| Module | Used for |
|---|---|
| [Microsoft.Graph.Authentication](https://www.powershellgallery.com/packages/Microsoft.Graph.Authentication) | `Connect-MgGraph`, `Invoke-MgGraphRequest` |
| [Microsoft.Graph.Groups](https://www.powershellgallery.com/packages/Microsoft.Graph.Groups) | `Get-MgGroup`, `Get-MgGroupMember` |

All other Graph calls use `Invoke-MgGraphRequest` directly to avoid module version conflicts.

---

## 👏 Credits

Designed and built by [Joe Samuels](https://joesamuels.co.uk) at [REDACTED](https://beaconit.co.uk).
