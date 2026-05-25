# EnrolWatch — Testing Guide

A practical reference for verifying functionality while developing and extending EnrolWatch.

---

## Contents

1. [Test environment setup](#1-test-environment-setup)
2. [Quick smoke test](#2-quick-smoke-test)
3. [Manual functional tests — all four modes](#3-manual-functional-tests--all-four-modes)
4. [Edge case tests](#4-edge-case-tests)
5. [HTML report verification checklist](#5-html-report-verification-checklist)
6. [Pester unit tests](#6-pester-unit-tests)
7. [Development workflow checklist](#7-development-workflow-checklist)

---

## 1. Test environment setup

### Test groups to create in Entra ID

Maintain a small set of dedicated test groups so you can run the script against predictable data. You need direct control over the group membership and the auth methods of those users.

| Group name | Purpose |
|---|---|
| `EnrolWatch-Test-Empty` | No members — tests the "no users" error path |
| `EnrolWatch-Test-Mixed` | ~5–10 users with a known mix of enrolment states |
| `EnrolWatch-Test-AllEnrolled` | All users have every auth method — tests 100% coverage display |
| `EnrolWatch-Test-NoneEnrolled` | All users have no auth methods — tests 0% coverage display |

For `EnrolWatch-Test-Mixed`, assign users like this so you can verify each category:

| User | Authenticator | WHfB | FIDO2/Passkey | Expected state (Mode 1) |
|---|---|---|---|---|
| Test User A | ✓ | ✓ | — | Complete |
| Test User B | ✓ | ✗ | — | Partial |
| Test User C | ✗ | ✓ | — | Partial |
| Test User D | ✗ | ✗ | — | Not started |
| Test User E | — | — | ✓ | Complete (Mode 4) |

> Record the Object IDs for each group somewhere handy (a local `.env` or notes file) — you'll use them constantly.

### Required permissions

Your test admin account needs at minimum:

- `Authentication Administrator` or `Global Reader` role in the tenant
- Access to query all five scopes the script requests (these are delegated — no app registration needed)

### Module version check

Before starting any test session:

```powershell
Get-Module Microsoft.Graph.Authentication -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
Get-Module Microsoft.Graph.Groups -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
```

Both should return a version. If either returns nothing, run:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

---

## 2. Quick smoke test

Run this first whenever you've made a change. It validates the full script path against your mixed test group.

```powershell
.\EnrolWatch.ps1 -GroupId "<EnrolWatch-Test-Mixed Object ID>"
```

**Expected console output (in order):**

```
  EnrolWatch
  MFA Enrolment Tracker

  Select tracking mode: ...
  Enter choice (1-4): _         ← prompts you

  Mode: Authenticator + WHfB

  Connecting to Microsoft Graph...
  Connected as admin@yourtenant.com

  Fetching tenant details...
  Tenant: Your Tenant Name

  Fetching group details...
  Group: EnrolWatch-Test-Mixed

  Fetching group members...
  Found N members.

  Checking authentication methods...
  [progress bar]

  Results:
    Total:        N
    Not started:  N
    Partial:      N
    Complete:     N

  Report saved to: .\enrolwatch_EnrolWatch-Test-Mixed_Mode1-Auth-WHfB_YYYY-MM-DD_HHMM.html

  Disconnected from Microsoft Graph.
  Done.
```

**Fail signals to watch for:**

- Any line starting with `  ERROR:` — the script exits without producing a report
- `  WARNING: Could not disconnect` — Graph session leak; run `Disconnect-MgGraph` manually before the next test
- Report file not created in the current directory
- `$errorUsers` warning mentioning known test users — may indicate a permission issue

---

## 3. Manual functional tests — all four modes

Run each test, then verify the generated HTML file. Tick off each expected behaviour before moving to the next mode.

### Mode 1 — Authenticator + Windows Hello for Business

```powershell
.\EnrolWatch.ps1 -GroupId "<mixed-group-id>"
# Enter: 1
```

**Verify in console:**
- Mode label shows `Authenticator + WHfB`
- Results show `Total`, `Not started`, `Partial`, and `Complete` counts
- Counts add up: `Not started + Partial + Complete = Total`

**Verify in HTML report:**
- Four stat cards: Total, Not Started, Partial, Fully Enrolled
- Progress bar has two segments: teal (complete) and amber (partial)
- "Still to Catch" section lists users with neither method
- "Partially Enrolled" section lists users with exactly one method
- Table headers: `User / Authenticator App / Windows Hello / Status`
- Each row shows two badges (one per method)
- Badge colour: green for registered, red for not registered
- "Fully Enrolled" section is collapsed by default; clicking expands it
- Mode badge in header reads `Authenticator + WHfB`
- Accent colour is teal (`#43C0B9`)

**Test User B** (Authenticator only): should appear in Partial with ✓ Authenticator, ✗ Windows Hello  
**Test User C** (WHfB only): should appear in Partial with ✗ Authenticator, ✓ Windows Hello

---

### Mode 2 — Windows Hello for Business only

```powershell
.\EnrolWatch.ps1 -GroupId "<mixed-group-id>"
# Enter: 2
```

**Verify in console:**
- Mode label shows `Windows Hello for Business`
- No `Partial:` line in results (partial is always 0 for single-method modes)

**Verify in HTML report:**
- Three stat cards: Total, Not Registered, Registered
- Fourth card shows `Coverage` with a percentage
- No "Partially Enrolled" section in the HTML
- Table headers: `User / Windows Hello / Status`
- Each row has one badge column
- Users with WHfB appear in "Registered" (complete) section
- Users without WHfB appear in "Still to Catch" section
- Accent colour is purple (`#7b6ff0`)
- Mode badge reads `Windows Hello for Business`

> **Cross-check:** Test User A (has WHfB) → Registered. Test User D (no WHfB) → Still to Catch.

---

### Mode 3 — Microsoft Authenticator only

```powershell
.\EnrolWatch.ps1 -GroupId "<mixed-group-id>"
# Enter: 3
```

**Verify in console:**
- Mode label shows `Microsoft Authenticator`

**Verify in HTML report:**
- Table headers: `User / Authenticator App / Status`
- Accent colour is teal (`#43C0B9`)
- Mode badge reads `Microsoft Authenticator`
- Users with Authenticator or OATH token → Registered
- Users without either → Still to Catch
- No partial section

> **Note on OATH fallback:** If a user has a software OATH token but no Authenticator app, the script counts them as having Authenticator (`hasAuthenticator = true` via the `softwareOathMethods` fallback). Verify this with a test user that has only a software OATH token.

---

### Mode 4 — Passkey

```powershell
.\EnrolWatch.ps1 -GroupId "<mixed-group-id>"
# Enter: 4
```

**Verify in console:**
- Mode label shows `Passkey`

**Verify in HTML report:**
- Table headers: `User / Passkey / Status`
- Accent colour is amber (`#f0a843`)
- Mode badge reads `Passkey`
- Users with FIDO2 key → Registered
- Users with Authenticator device-bound passkey (`authenticationMode: deviceBoundPushNotification` or `deviceTag: SoftwareTokenPasskey`) → Registered
- Users with neither → Still to Catch
- No partial section

> **FIDO2 vs Authenticator passkeys:** These come from two separate Graph endpoints. Test with at least one user for each type to confirm both paths work.

---

## 4. Edge case tests

### 4a. Empty group

```powershell
.\EnrolWatch.ps1 -GroupId "<EnrolWatch-Test-Empty Object ID>"
# Enter any mode
```

**Expected:** Script exits with `ERROR: No users found in this group. Check the Group ID.` No HTML file created.

---

### 4b. Invalid Group ID

```powershell
.\EnrolWatch.ps1 -GroupId "00000000-0000-0000-0000-000000000000"
# Enter any mode
```

**Expected:** Script exits with `ERROR: Could not retrieve group members.` (the group ID returns a 404 from Graph). No HTML file created.

---

### 4c. All users fully enrolled

```powershell
.\EnrolWatch.ps1 -GroupId "<EnrolWatch-Test-AllEnrolled Object ID>"
# Enter: 1
```

**Expected in HTML:**
- "Still to Catch" section shows the empty-state message: `Everyone has started enrolment 🎉`
- "Partially Enrolled" section shows `No partial enrolments`
- Progress bar is 100% teal with no amber segment
- Stat cards: Not Started = 0, Complete = Total

---

### 4d. No users enrolled

```powershell
.\EnrolWatch.ps1 -GroupId "<EnrolWatch-Test-NoneEnrolled Object ID>"
# Enter: 3
```

**Expected in HTML:**
- "Still to Catch" section lists all users
- "Registered" section shows `No completed enrolments yet`
- Progress bar is empty (no coloured segment)
- Coverage stat card shows `0%`

---

### 4e. Special characters in display names and emails

Add a test user with a display name containing HTML special characters (e.g. `O'Brien <Test> & Co`). Run any mode.

**Expected:**
- Name displays correctly in the HTML without breaking the layout
- HTML source shows the encoded form: `O&#39;Brien &lt;Test&gt; &amp; Co`
- No `<script>` or raw `<` in the rendered user name

This verifies the `[System.Web.HttpUtility]::HtmlEncode()` calls on lines 326–327 and 391–392 of the script.

---

### 4f. Custom output path

```powershell
.\EnrolWatch.ps1 -GroupId "<mixed-group-id>" -OutputPath "C:\Temp\test-report.html"
# Enter: 2
```

**Expected:** File created at the specified path, not in the current directory. Console confirms: `Report saved to: C:\Temp\test-report.html`.

---

### 4g. Output path with unwritable location

```powershell
.\EnrolWatch.ps1 -GroupId "<mixed-group-id>" -OutputPath "Z:\nonexistent\report.html"
# Enter: 1
```

**Expected:** Script exits with `ERROR: Could not write output file.` No file created.

---

### 4h. Graph auth method fetch failure (error users)

Temporarily revoke `UserAuthenticationMethod.Read.All` from your test account, or target a user whose object is in a different tenant. Run any mode.

**Expected:**
- Console shows: `WARNING: Could not retrieve auth methods for N user(s)`
- HTML report includes a "Could Not Check" section in amber
- Affected users are excluded from all counts
- Total in stats reflects only successfully queried users

---

### 4i. Group with non-user members (guests, service principals)

If your test group contains guest users or service principals (which lack a `/authentication/` endpoint), run the script.

**Expected:**
- Non-user members that can't be resolved via the `/users/{id}` endpoint are silently skipped with the `skippedMembers` warning
- The report still generates for the resolvable members

---

## 5. HTML report verification checklist

Open the generated report in a browser and work through this list after any change that touches HTML generation (lines 280–573 of the script).

**Layout and header**
- [ ] Header shows the EnrolWatch logo, group name, tenant name (if available), mode badge, and generation timestamp
- [ ] Mode badge matches the selected mode
- [ ] No raw PowerShell variable names visible (e.g. `$safeModeLabel` would indicate a string interpolation failure)

**Stat cards**
- [ ] Four cards present (layout differs by mode — see Mode 1 vs others above)
- [ ] All numbers are integers (no decimals except the Coverage % card)
- [ ] Card colour-coded top border: grey (total), red (not started/not registered), amber (partial/coverage), teal/purple/amber accent (complete/registered)

**Progress bar**
- [ ] Width of teal segment visually matches the complete percentage
- [ ] Mode 1 only: amber segment appears for partial users and is proportional
- [ ] Mode 2–4: no amber segment

**"Still to Catch" section**
- [ ] Count badge matches the number of rows shown
- [ ] Each row shows the user's display name and UPN
- [ ] Badge(s) show ✗ Not registered for the relevant methods

**"Partially Enrolled" section (Mode 1 only)**
- [ ] Section present and count matches
- [ ] Each row has exactly one ✓ badge and one ✗ badge

**"Registered / Fully Enrolled" section**
- [ ] Collapsed by default (body has `display: none`)
- [ ] Clicking the toggle expands/collapses it (chevron rotates)
- [ ] Count badge matches rows inside

**"Could Not Check" section (only when errors occurred)**
- [ ] Appears only when `$errorUsers.Count -gt 0`
- [ ] Amber styling (not red, not teal)
- [ ] Users listed with their name and UPN

**Footer**
- [ ] Generation timestamp matches the filename timestamp (same minute)

**Responsive check (optional but useful)**
- [ ] Resize browser window — no horizontal overflow at reasonable widths

---

## 6. Pester unit tests

EnrolWatch has no automated tests today. Pester is PowerShell's native testing framework and can cover the pure logic in the script (categorisation, HTML helpers, filename generation) without needing a live Graph connection.

### Install Pester

```powershell
Install-Module Pester -Scope CurrentUser -Force
```

Verify:

```powershell
Get-Module Pester -ListAvailable | Select-Object Name, Version
```

### Suggested test file structure

```
EnrolWatch/
├── code/
│   └── EnrolWatch.ps1
└── tests/
    ├── Categorisation.Tests.ps1
    ├── HtmlHelpers.Tests.ps1
    └── FilenameGeneration.Tests.ps1
```

### Running tests

```powershell
cd /path/to/EnrolWatch
Invoke-Pester -Path ./tests/ -Output Detailed
```

### Example: categorisation logic tests

The categorisation block (lines 227–248 of the script) is pure logic with no Graph dependency. Extract it into a function, or dot-source the script in a test context. Below is a template showing what to test.

```powershell
# tests/Categorisation.Tests.ps1
BeforeAll {
    # Build test user objects matching the script's $users structure
    function New-TestUser($name, $hasAuth, $hasWHfB, $hasPasskey) {
        [PSCustomObject]@{
            Name             = $name
            Email            = "$name@test.com"
            HasAuthenticator = $hasAuth
            HasWHfB          = $hasWHfB
            HasPasskey       = $hasPasskey
        }
    }

    $allUsers = @(
        (New-TestUser "AuthAndWHfB"    $true  $true  $false),
        (New-TestUser "AuthOnly"       $true  $false $false),
        (New-TestUser "WHfBOnly"       $false $true  $false),
        (New-TestUser "Neither"        $false $false $false),
        (New-TestUser "PasskeyOnly"    $false $false $true)
    )
}

Describe "Mode 1 — Authenticator + WHfB categorisation" {
    BeforeAll {
        $notStarted = @($allUsers | Where-Object { -not $_.HasAuthenticator -and -not $_.HasWHfB })
        $partial    = @($allUsers | Where-Object { ($_.HasAuthenticator -or $_.HasWHfB) -and -not ($_.HasAuthenticator -and $_.HasWHfB) })
        $complete   = @($allUsers | Where-Object { $_.HasAuthenticator -and $_.HasWHfB })
    }

    It "puts AuthAndWHfB in complete" {
        $complete.Name | Should -Contain "AuthAndWHfB"
    }

    It "puts AuthOnly in partial" {
        $partial.Name | Should -Contain "AuthOnly"
    }

    It "puts WHfBOnly in partial" {
        $partial.Name | Should -Contain "WHfBOnly"
    }

    It "puts Neither in notStarted" {
        $notStarted.Name | Should -Contain "Neither"
    }

    It "complete + partial + notStarted equals total (excluding passkey-only user)" {
        ($complete.Count + $partial.Count + $notStarted.Count) | Should -Be 4
    }
}

Describe "Mode 2 — WHfB only categorisation" {
    BeforeAll {
        $notStarted = @($allUsers | Where-Object { -not $_.HasWHfB })
        $complete   = @($allUsers | Where-Object { $_.HasWHfB })
    }

    It "puts AuthAndWHfB and WHfBOnly in complete" {
        $complete.Count | Should -Be 2
    }

    It "has no partial category" {
        # Mode 2 has no partial — verify notStarted + complete = total
        ($notStarted.Count + $complete.Count) | Should -Be $allUsers.Count
    }
}

Describe "Mode 3 — Authenticator only categorisation" {
    BeforeAll {
        $notStarted = @($allUsers | Where-Object { -not $_.HasAuthenticator })
        $complete   = @($allUsers | Where-Object { $_.HasAuthenticator })
    }

    It "puts AuthAndWHfB and AuthOnly in complete" {
        $complete.Count | Should -Be 2
    }
}

Describe "Mode 4 — Passkey categorisation" {
    BeforeAll {
        $notStarted = @($allUsers | Where-Object { -not $_.HasPasskey })
        $complete   = @($allUsers | Where-Object { $_.HasPasskey })
    }

    It "puts PasskeyOnly in complete" {
        $complete.Name | Should -Contain "PasskeyOnly"
    }

    It "puts non-passkey users in notStarted" {
        $notStarted.Count | Should -Be 4
    }
}
```

### Example: HTML encoding test

This tests the XSS-prevention logic directly without running the full script.

```powershell
# tests/HtmlHelpers.Tests.ps1
BeforeAll {
    Add-Type -AssemblyName System.Web
}

Describe "HTML encoding of user-supplied strings" {
    It "encodes angle brackets in display names" {
        $raw = '<script>alert(1)</script>'
        $encoded = [System.Web.HttpUtility]::HtmlEncode($raw)
        $encoded | Should -Not -Match '<script>'
        $encoded | Should -Match '&lt;script&gt;'
    }

    It "encodes ampersands" {
        $encoded = [System.Web.HttpUtility]::HtmlEncode("Smith & Jones")
        $encoded | Should -Be "Smith &amp; Jones"
    }

    It "encodes single quotes" {
        $encoded = [System.Web.HttpUtility]::HtmlEncode("O'Brien")
        $encoded | Should -Match "&#39;"
    }
}
```

### Example: filename sanitisation test

```powershell
# tests/FilenameGeneration.Tests.ps1
Describe "Output filename sanitisation" {
    It "strips special characters from group name" {
        $groupName = "Staff (UK) & Partners"
        $safeName  = $groupName -replace '[^\w\s-]', '' -replace '\s+', '-'
        $safeName | Should -Not -Match '\('
        $safeName | Should -Not -Match '&'
        $safeName | Should -Match '^[\w-]+$'
    }

    It "collapses multiple spaces into single hyphens" {
        $groupName = "My   Test   Group"
        $safeName  = $groupName -replace '[^\w\s-]', '' -replace '\s+', '-'
        $safeName | Should -Be "My-Test-Group"
    }
}
```

---

## 7. Development workflow checklist

Run through this before committing any change to `EnrolWatch.ps1`.

### Before you start

- [ ] Module versions confirmed (step 1 above)
- [ ] Test group Object IDs on hand
- [ ] A browser ready to open the HTML output

### After code changes

- [ ] Quick smoke test passes (section 2) — no errors, report generated
- [ ] Spot-check the specific mode(s) affected by the change (section 3)
- [ ] If you changed categorisation logic: run all four modes and verify counts are correct
- [ ] If you changed HTML generation: open the report in a browser and work through section 5
- [ ] If you changed Graph API calls: verify with a user who has the relevant method registered
- [ ] If you changed error handling: trigger the relevant error path and confirm graceful exit

### Specific things to recheck after common changes

| Change type | What to verify |
|---|---|
| Mode selection block | All four modes prompt correctly and set `$modeLabel` / `$modeShort` / `$accentColor` correctly |
| Auth method fetch logic | OATH fallback fires when Authenticator endpoint returns empty; Passkey detection picks up both FIDO2 and Authenticator device-bound passkeys |
| Categorisation switch | Mode 1 partial logic (XOR) is correct; Modes 2–4 have empty `$partial` array |
| `Get-Rows` function | Empty state messages match the mode (`Not registered` vs `Not started`); pill labels match |
| `Get-TableHeader` function | Column count matches `Get-GridCols` output for the same mode |
| Percentage calculations | `$pctComplete` rounds correctly at 0%, 100%, and fractional values |
| File write | UTF-8 encoding preserved (check that em-dashes and special chars render in the browser) |

### Sign-off criteria

A change is ready to commit when:

1. Smoke test passes for at least one mode
2. The affected mode(s) pass their full manual tests
3. No new `WARNING:` or `ERROR:` lines appear in console output for normal input
4. The generated HTML opens without browser console errors (check DevTools)
5. If Pester tests exist: `Invoke-Pester` passes with 0 failures
