# MFAMap — Testing Strategy

This document is a complete test plan for MFAMap, covering tenant setup, test data configuration, and per-feature verification across all five modes. Intended to be run in full before merging `dev` → `main`.

---

## 1. Environment Setup

### 1.1 Tenant selection

Use the **dedicated test tenant** for all destructive or setup-heavy tests. Use the **production tenant** only for the read-only smoke tests in [Section 9](#9-production-tenant-smoke-test).

### 1.2 Prerequisites checklist

- [ ] PowerShell 7+ installed (`$PSVersionTable.PSVersion` — major version must be ≥ 7)
- [ ] Microsoft.Graph module installed (`Get-Module Microsoft.Graph -ListAvailable`)
- [ ] If not installed: `Install-Module Microsoft.Graph -Scope CurrentUser -Force`
- [ ] Admin account available with **Authentication Administrator** or **Global Reader** role in the test tenant
- [ ] Script is on disk at `.\code\MFAMap.ps1`

---

## 2. Test Tenant — Group and User Setup

Create a dedicated test group and populate it with the users below. Each user represents a specific auth method state. All setup is done via **Microsoft Entra admin center** (entra.microsoft.com) → Users → Authentication methods, or via PowerShell Graph calls.

**Test group name:** `MFAMap-Test-Group`  
Record the Object ID — this is your `$GroupId` for all test runs.

### 2.1 Test user matrix

| User | Display name | Auth App (push) | WHfB | FIDO2 | Soft. OATH (TOTP) | SMS | Voice | Email OTP |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| A | Test-FullModern | ✓ | ✓ | — | — | — | — | — |
| B | Test-AuthOnly | ✓ | — | — | — | — | — | — |
| C | Test-WHfBOnly | — | ✓ | — | — | — | — | — |
| D | Test-NoMethods | — | — | — | — | — | — | — |
| E | Test-TotpOnly | — | — | — | ✓ | — | — | — |
| F | Test-Fido2 | — | — | ✓ | — | — | — | — |
| G | Test-SmsOnly | — | — | — | — | ✓ | — | — |
| H | Test-VoiceOnly | — | — | — | — | — | ✓ | — |
| I | Test-EmailOnly | — | — | — | — | — | — | ✓ |
| J | Test-Mixed | ✓ | — | — | — | ✓ | — | — |

**Setting up Software OATH (TOTP) for User E:**  
Entra admin center → Users → Test-TotpOnly → Authentication methods → Add method → Software OATH token. Register a TOTP app (Google Authenticator, Authy, etc.) and activate it. This user should appear in `softwareOathMethods` but NOT in `microsoftAuthenticatorMethods`.

**Setting up SMS for User G:**  
Authentication methods → Add method → Phone → enter a test number → SMS.

**Setting up Voice for User H:**  
Authentication methods → Add method → Phone → enter a test number → set phone type to Alternate phone or Office phone.

**Setting up Email OTP for User I:**  
Authentication methods → Add method → Email OTP → enter a test email address.

### 2.2 Setup verification

Before running the script, confirm each user's auth state by running:

```powershell
Connect-MgGraph -Scopes "UserAuthenticationMethod.Read.All" -NoWelcome
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/<UPN>/authentication/methods"
```

---

## 3. Script Invocation

### 3.1 Basic run

- [ ] `.\code\MFAMap.ps1 -GroupId "<test-group-id>"` — script launches, mode prompt appears
- [ ] `.\code\MFAMap.ps1 -GroupId "<test-group-id>" -OutputPath "C:\Temp\test-report.html"` — output written to specified path instead of auto-named file

### 3.2 Execution policy

- [ ] If execution policy blocks the script: `PowerShell -ExecutionPolicy Bypass -File .\code\MFAMap.ps1 -GroupId "<id>"` succeeds

### 3.3 Invalid inputs

- [ ] Invalid Group ID (random GUID) → script exits with `ERROR: Could not retrieve group members`
- [ ] Empty `-GroupId ""` — PowerShell should flag the mandatory parameter as missing before the script runs

---

## 4. Mode Selection and Input Validation

- [ ] Entering `1` → accepted, proceeds with mode 1
- [ ] Entering `2` → accepted
- [ ] Entering `3` → accepted
- [ ] Entering `4` → accepted
- [ ] Entering `5` → accepted
- [ ] Entering `0` → rejected, prompt repeats
- [ ] Entering `6` → rejected, prompt repeats
- [ ] Entering a letter (e.g. `a`) → rejected, prompt repeats
- [ ] Pressing Enter with no input → rejected, prompt repeats
- [ ] After selecting a valid mode, console confirms: `Mode: <label>` in cyan

---

## 5. Connection and Disconnect

- [ ] Sign-in window appears (or silent re-auth if token cached)
- [ ] Console shows `Connected as <UPN>` in green after sign-in
- [ ] Console shows tenant name and group name after connection
- [ ] At end of run, console shows `Disconnected from Microsoft Graph`
- [ ] Run `Get-MgContext` immediately after script completes — should return nothing (session cleared)
- [ ] If disconnect fails for any reason, console shows the yellow warning prompting manual `Disconnect-MgGraph`

---

## 6. Mode 1 — Authenticator + Windows Hello for Business

**Expected categorisation with test users:**

| User | Expected section |
|---|---|
| Test-FullModern (A) | Fully Enrolled |
| Test-AuthOnly (B) | Partially Enrolled |
| Test-WHfBOnly (C) | Partially Enrolled |
| Test-TotpOnly (E) | Partially Enrolled (TOTP counts as Authenticator) |
| Test-NoMethods (D) | Not Registered |
| Test-Mixed (J) | Partially Enrolled |
| Others (F, G, H, I) | Not Registered |

**Console output:**
- [ ] Results show correct counts for Not registered / Partial / Complete

**HTML report:**
- [ ] Stat cards show: Total / Not Registered / Partial / Fully Enrolled with correct counts
- [ ] Section label reads **Not Registered** (not "Still to catch" or "Not started")
- [ ] Stat card sub-label reads **not registered** (not "still to catch")
- [ ] Partially Enrolled section present and populated
- [ ] Fully Enrolled section collapsed by default, expands on click
- [ ] Progress bar reflects complete + partial percentages visually
- [ ] Teal accent colour throughout

**Output file:**
- [ ] Filename format: `mfamap_MFAMap-Test-Group_Mode1-Auth-WHfB_<timestamp>.html`

---

## 7. Mode 2 — Windows Hello for Business Only

**Expected categorisation:**

| User | Expected section |
|---|---|
| Test-FullModern (A) | Registered |
| Test-WHfBOnly (C) | Registered |
| All others | Not Registered |

**HTML report:**
- [ ] No "Partially Enrolled" section
- [ ] Section label reads **Not Registered**
- [ ] Registered section collapsed by default
- [ ] Purple accent colour
- [ ] Coverage % in stat cards is correct

**Output file:**
- [ ] Filename contains `Mode2-WHfB`

---

## 8. Mode 3 — Authenticator Only

**Expected categorisation:**

| User | Expected section | Badge |
|---|---|---|
| Test-FullModern (A) | Registered | ✓ Registered (green) |
| Test-AuthOnly (B) | Registered | ✓ Registered (green) |
| Test-TotpOnly (E) | Registered | ✓ TOTP only (amber) |
| Test-Mixed (J) | Registered | ✓ Registered (green) |
| All others | Not Registered | ✗ Not registered (red) |

**TOTP flag (key test for Change 2):**
- [ ] Test-TotpOnly (E) appears in the **Registered** section
- [ ] Their Authenticator App cell shows an **amber** `TOTP only` badge — NOT the green `Registered` badge
- [ ] Test-AuthOnly (B) and Test-FullModern (A) show the standard **green** `Registered` badge
- [ ] Status pill for Test-TotpOnly shows `Registered` (not flagged at the pill level)

**HTML report:**
- [ ] No "Partially Enrolled" section
- [ ] Teal accent colour
- [ ] Section label reads **Not Registered**

**Output file:**
- [ ] Filename contains `Mode3-Auth`

---

## 9. Mode 4 — Passkey

**Expected categorisation:**

| User | Expected section |
|---|---|
| Test-Fido2 (F) | Registered |
| All others | Not Registered |

> If you have a user with a device-bound Authenticator passkey (`authenticationMode: deviceBoundPushNotification`) available, add them to the group and confirm they also appear in **Registered**.

**HTML report:**
- [ ] Amber accent colour
- [ ] Section label reads **Not Registered**
- [ ] No "Partially Enrolled" section

**Output file:**
- [ ] Filename contains `Mode4-Passkey`

---

## 10. Mode 5 — Full Method Audit

This mode has the most surface area to verify.

### 10.1 Method count banner

- [ ] Banner shows 8 cards (Auth App, WHfB, FIDO2, Soft. OATH, SMS, Voice, Email OTP, No Methods)
- [ ] Each count matches the expected number of users with that method registered:
  - Auth App: 3 (A, B, J)
  - WHfB: 2 (A, C)
  - FIDO2: 1 (F)
  - Software OATH: 1 (E)
  - SMS: 2 (G, J)
  - Voice: 1 (H)
  - Email OTP: 1 (I)
  - No Methods: 1 (D)
- [ ] Modern method cards (Auth App, WHfB, FIDO2, Soft. OATH) use accent colour
- [ ] Legacy method cards (SMS, Voice, Email OTP) use amber
- [ ] No Methods card uses red

### 10.2 Section: No Methods Registered

- [ ] Test-NoMethods (D) appears here
- [ ] No other users appear here
- [ ] Status pill: `No methods` in red

### 10.3 Section: Legacy Only

- [ ] Test-SmsOnly (G), Test-VoiceOnly (H), Test-EmailOnly (I) appear here
- [ ] Status pill: `Legacy only` in amber
- [ ] Test-Mixed (J) does **not** appear here (has Authenticator — modern method present)

### 10.4 Section: Modern Methods (collapsible)

- [ ] Test-FullModern (A), Test-AuthOnly (B), Test-WHfBOnly (C), Test-TotpOnly (E), Test-Fido2 (F), Test-Mixed (J) appear here
- [ ] Section is collapsed by default, expands on click
- [ ] Status pill: `✓` in accent colour

### 10.5 User table columns

For each user in any section, verify the tick/dash per column is correct:

- [ ] Test-FullModern (A): Auth ✓ · WHfB ✓ · FIDO2 – · Soft.OATH – · SMS – · Voice – · Email –
- [ ] Test-TotpOnly (E): Auth – · WHfB – · FIDO2 – · Soft.OATH ✓ · SMS – · Voice – · Email –
- [ ] Test-Mixed (J): Auth ✓ · WHfB – · FIDO2 – · Soft.OATH – · SMS ✓ · Voice – · Email –
- [ ] Test-NoMethods (D): all dashes

### 10.6 Summary line

- [ ] Descriptive line below banner reads: `10 users · 3 legacy-only · 1 with no methods` (or equivalent counts)

### 10.7 Accent and naming

- [ ] Blue accent colour (`#4B9EE8`) throughout
- [ ] Mode badge in header reads `Full Method Audit`
- [ ] Filename contains `Mode5-Audit`

---

## 11. HTML Report — Universal Checks (all modes)

Run these for at least one report from each mode.

- [ ] Report opens in Chrome, Firefox, and Edge without errors
- [ ] Header shows tenant name · group name
- [ ] Mode badge shows the correct mode label
- [ ] Generated timestamp is accurate
- [ ] Footer shows generated timestamp and credits
- [ ] Report is self-contained — opening with no internet connection falls back to system fonts gracefully; no other assets fail
- [ ] HTML file contains no credentials, tokens, or connection strings
- [ ] `<title>` reads `MFAMap — <group name>`

---

## 12. Edge Cases

### 12.1 Empty group

- [ ] Create a group with 0 members → script exits with `ERROR: No users found in this group`

### 12.2 Single-user group

- [ ] Create a group with 1 user → script completes, report generates correctly with 1 row

### 12.3 Non-user group members

- [ ] If the group contains a device or service principal object, the script logs a warning (`WARNING: N group member(s) could not be resolved`) and continues — the report excludes them without crashing

### 12.4 Auth method fetch failure

- [ ] Remove `UserAuthenticationMethod.Read.All` consent from the session (or test with an account lacking the permission) → affected users appear in a **Could Not Check** section in the HTML report; they are excluded from all counts

### 12.5 Tenant name unavailable

- [ ] Test with an account that lacks `Organization.Read.All` → script emits `WARNING: Could not retrieve tenant name` and continues; header shows group name only

### 12.6 Group name unavailable

- [ ] Pass a valid group ID for a group the account can't read the name of → header falls back to the raw Group ID; report still generates

---

## 13. Production Tenant Smoke Test

Run this section against your production/live tenant with a **read-only test account** (Global Reader or Authentication Administrator, no write permissions). Use a small, low-sensitivity group.

- [ ] Mode 1 run completes without errors
- [ ] Disconnect confirmed at end of run
- [ ] Output HTML file is written locally — confirm no data sent anywhere other than Microsoft Graph
- [ ] No changes are visible in the tenant after the run (check audit logs in Entra admin center → Monitoring → Audit logs)

---

## 14. Regression — Modes 1–4 Unchanged

Confirm the `dev` changes haven't broken existing behaviour.

- [ ] Mode 1: Partially Enrolled section still present and working
- [ ] Mode 1: Progress bar still renders
- [ ] Mode 1–4: Auto-disconnect still fires
- [ ] Mode 1–4: Output filename auto-naming still correct
- [ ] Mode 3: Non-TOTP users still get green `Registered` badge (not amber)
- [ ] No "Still to catch" or "Not started" text anywhere in any output HTML

---

## 15. Pre-Merge Checklist

Complete all sections above, then sign off here before merging `dev` → `main`.

- [ ] All Mode 1–5 test runs completed in test tenant
- [ ] TOTP badge (Change 2) verified with a real TOTP-only user
- [ ] Mode 5 method counts verified against known user states
- [ ] All edge cases tested
- [ ] Production smoke test passed
- [ ] No regressions on Modes 1–4
- [ ] Output HTML opens and renders correctly in at least two browsers
- [ ] `.gitignore` covers `mfamap_*.html` output files — confirm no report files staged accidentally
- [ ] CLAUDE.md and README updated if any behaviour changed during dev
