# ⚡ EnrolWatch

**MFA enrolment tracker for Microsoft Entra ID**

EnrolWatch generates a self-contained HTML dashboard showing MFA enrolment progress across a target Entra group. Run the script, pick a tracking mode, get a file. Open it in any browser, share it with anyone — no server, no login, no dependencies.

---

## ✨ Key features

- 🎛️ **Four tracking modes** — pick what to track at runtime via an interactive menu
- 🗂️ **Single output file** — generates one self-contained HTML file with no dependencies
- 🔑 **Uses your existing credentials** — authenticates via `Connect-MgGraph` with your own admin account; no app registration required
- 🏢 **Tenant and group name in the report** — header shows exactly which tenant and group you ran against
- 🎨 **Mode-themed branding** — accent colour and badge change based on what you're tracking
- 📁 **Auto-named output** — HTML file is named with the group name, mode, and timestamp automatically
- 🎯 **Group-scoped** — targets a specific Entra group, not your entire tenant
- 🚨 **"Still to catch" first** — users with nothing registered are surfaced at the top
- ✅ **Completed section collapsed** — registered users are tucked away so they don't distract
- 📊 **Progress bar** — visual breakdown of complete, partial, and not-started at a glance
- 📤 **Fully portable** — the output HTML file can be opened, shared, or emailed with no auth required
- 🔄 **Re-run to refresh** — run the script again to regenerate with fresh data
- 💾 **Session reuse** — sign in once, run as many times as you like in the same PowerShell session

---

## 🎛️ Tracking modes

When you run the script you're prompted to choose what to track:

| Mode | Tracks | Used for |
|---|---|---|
| **1** | Microsoft Authenticator + Windows Hello for Business | Full enrolment tracking with partial enrolment detection |
| **2** | Windows Hello for Business only | Tracking WHfB rollout independently |
| **3** | Microsoft Authenticator only | Tracking Authenticator rollout independently |
| **4** | Passkey | Tracking passkey adoption (FIDO2 keys or Authenticator device-bound passkeys) |

Modes 2, 3, and 4 are binary — registered or not. Mode 1 includes a **Partially Enrolled** section for users who have one method but not both.

---

## 🔧 How it works

```
.\EnrolWatch.ps1 -GroupId "your-group-id"
        ↓
Choose tracking mode (1-4)
        ↓
Connect-MgGraph  (sign in with your admin account, only first run)
        ↓
Invoke-MgGraphRequest — direct Graph API calls
/organization                                              (tenant display name)
/groups/{id}                                               (group display name)
/groups/{id}/members                                       (group membership)
/users/{id}                                                (user display name + UPN)
/users/{id}/authentication/microsoftAuthenticatorMethods   (mode 1, 3, 4)
/users/{id}/authentication/windowsHelloForBusinessMethods  (mode 1, 2)
/users/{id}/authentication/fido2Methods                    (mode 4)
        ↓
Self-contained HTML file written to disk
enrolwatch_GroupName_Mode1-Auth-WHfB_2026-04-23_0941.html
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

When prompted, pick a tracking mode (1-4). Sign in with your Microsoft admin account when prompted. The script generates a timestamped HTML report in the current directory.

**4. Open the report**

The script prints the exact filename on completion:

```
  Report saved to: .\enrolwatch_Staff_Mode1-Auth-WHfB_2026-06-01_0930.html
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
# Basic — output file named automatically from group name, mode, and timestamp
.\EnrolWatch.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00"

# Custom output path (overrides auto-naming)
.\EnrolWatch.ps1 -GroupId "11223344-5566-7788-99aa-bbccddeeff00" -OutputPath "C:\Reports\mfa-report.html"
```

---

## 📝 What counts as enrolled per mode

### Mode 1 — Authenticator + WHfB

| Method registered | Counted as |
|---|---|
| Microsoft Authenticator app | ✅ Authenticator App |
| Windows Hello for Business | ✅ Windows Hello |
| One method only | 🟡 Partially Enrolled |
| Neither | ❌ Not started |

A user is **Fully Enrolled** only when both are registered.

### Mode 2 — Windows Hello for Business only

| Method registered | Counted as |
|---|---|
| Windows Hello for Business | ✅ Registered |
| Anything else only | ❌ Not registered |

### Mode 3 — Authenticator only

| Method registered | Counted as |
|---|---|
| Microsoft Authenticator app (any mode) | ✅ Registered |
| Anything else only | ❌ Not registered |

### Mode 4 — Passkey

| Method registered | Counted as |
|---|---|
| FIDO2 security key | ✅ Registered |
| Microsoft Authenticator device-bound passkey | ✅ Registered |
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

You can also switch modes between runs without re-authenticating — just choose a different number when prompted.

---

## 📦 Dependencies

| Module | Used for |
|---|---|
| [Microsoft.Graph.Authentication](https://www.powershellgallery.com/packages/Microsoft.Graph.Authentication) | `Connect-MgGraph`, `Invoke-MgGraphRequest` |
| [Microsoft.Graph.Groups](https://www.powershellgallery.com/packages/Microsoft.Graph.Groups) | `Get-MgGroupMember` |

All other Graph calls use `Invoke-MgGraphRequest` directly to avoid module version conflicts.

---

## 👏 Credits

Designed and built by [Joe Samuels](https://joesamuels.co.uk) at [REDACTED](https://beaconit.co.uk).
