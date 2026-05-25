# Create-MFAMapTestUsers — Setup Script

This script creates the 10 test users and group required to run the MFAMap test plan in [TESTING.md](../TESTING.md). It automates everything the Graph API allows and prints numbered manual steps for the rest.

---

## What it does

- Creates 10 test user accounts in your Entra tenant (or skips them if they already exist)
- Creates `MFAMap-Test-Group` and adds all 10 users as members
- Configures the following authentication methods automatically:
  - **Software OATH (TOTP)** — for `MFAMap-Test-TotpOnly` (registered and activated)
  - **SMS** — for `MFAMap-Test-SmsOnly` and `MFAMap-Test-Mixed`
  - **Voice** — for `MFAMap-Test-VoiceOnly`
  - **Email OTP** — for `MFAMap-Test-EmailOnly`
- Prints the Group Object ID ready to paste into MFAMap
- Lists the remaining manual steps (Authenticator push, Windows Hello for Business, FIDO2)

---

## Prerequisites

- **PowerShell 7+**
- **Microsoft.Graph module** — install if not already present:
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser -Force
  ```
- An admin account with **User Administrator** or **Authentication Administrator** role in the test tenant

---

## Configuration

Open `Create-MFAMapTestUsers.ps1` and edit the variables at the top of the file:

| Variable | What it controls | Example |
|---|---|---|
| `$TenantDomain` | The `.onmicrosoft.com` domain for the test tenant — used to build UPNs | `contoso.onmicrosoft.com` |
| `$TestPassword` | Initial password assigned to all 10 accounts | `MFAMap-Test-2024!` |
| `$SmsPhoneNumber` | Phone number set as SMS method (E.164 format) | `+447700000001` |
| `$VoicePhoneNumber` | Phone number set as Voice method (E.164 format) | `+447700000002` |
| `$TestEmailAddress` | Email address set as Email OTP method | `mfamap-test@example.com` |

The phone numbers and email address don't need to be real — they just need to pass Entra's format validation. Use a consistent test number rather than a real one.

---

## Running the script

From a PowerShell 7 terminal:

```powershell
.\setup\Create-MFAMapTestUsers.ps1
```

If you get an execution policy error:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\setup\Create-MFAMapTestUsers.ps1
```

A Microsoft sign-in window will appear. Sign in with your test tenant admin account.

---

## After running

The script prints three things at the end:

1. **Users created / confirmed** — a table of all 10 users and which methods were set automatically
2. **Test Group Object ID** — copy this and use it as the `-GroupId` when running MFAMap:
   ```powershell
   .\code\MFAMap.ps1 -GroupId "<printed-id>"
   ```
3. **Manual steps** — a numbered list of the Authenticator, Windows Hello for Business, and FIDO2 registrations that require a physical device and must be done via Entra admin center

Complete the manual steps before running the full test suite. See [TESTING.md](../TESTING.md) for the per-mode verification checklists.

---

## Re-running

The script is safe to re-run. Users and group memberships that already exist are skipped with a yellow warning rather than recreated. Auth methods that are already set are also skipped.

If a Software OATH activation fails (the TOTP window is 30 seconds — rarely the activation code is generated just before the window expires), re-run the script; it will skip users and methods that are already configured and retry only what's missing.

---

## Cleanup

When you're done testing, delete the users and group manually:

**Via Entra admin center** (entra.microsoft.com):
- **Groups** → search `MFAMap-Test-Group` → Delete
- **Users** → search `MFAMap-Test` → select all → Delete

**Via PowerShell:**
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All" -NoWelcome

# Delete users
"MFAMap-Test-FullModern","MFAMap-Test-AuthOnly","MFAMap-Test-WHfBOnly","MFAMap-Test-NoMethods",
"MFAMap-Test-TotpOnly","MFAMap-Test-Fido2","MFAMap-Test-SmsOnly","MFAMap-Test-VoiceOnly",
"MFAMap-Test-EmailOnly","MFAMap-Test-Mixed" | ForEach-Object {
    $upn = "$($_.ToLower() -replace '[^a-z0-9]', '-')@<your-tenant>.onmicrosoft.com"
    try { Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$upn" }
    catch { Write-Host "Could not delete $upn" }
}

# Delete group
$group = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq 'MFAMap-Test-Group'").value[0]
Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)"

Disconnect-MgGraph
```
