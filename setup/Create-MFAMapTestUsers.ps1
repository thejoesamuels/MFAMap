# ============================================================================
# Create-MFAMapTestUsers.ps1
# Test user setup script for MFAMap
#
# Creates 10 test users and a test group in Microsoft Entra ID with the
# authentication method states required by TESTING.md. Automates everything
# that the Graph API allows (SMS, Voice, Email OTP, Software OATH/TOTP).
# Methods that require device interaction (Authenticator push, Windows Hello
# for Business, FIDO2) are listed as manual steps in the summary output.
#
# Usage:
#   .\Create-MFAMapTestUsers.ps1
#
# Requirements:
#   - PowerShell 7+
#   - Install-Module Microsoft.Graph -Scope CurrentUser -Force
#   - User Administrator or Authentication Administrator role
#   - Edit the configuration variables below before running
# ============================================================================

# ── Configuration — edit these before running ─────────────────────────────────
$TenantDomain     = "yourtenantname.onmicrosoft.com"   # your tenant's .onmicrosoft.com domain
$TestPassword     = "YourTestPassword123!"          # initial password for all test accounts
$SmsPhoneNumber   = "+11234567890"              # E.164 format — used for SmsOnly + Mixed
$VoicePhoneNumber = "+11234567890"              # E.164 format — used for VoiceOnly
$TestEmailAddress = "your-test-email@example.com"   # used for EmailOnly
# ─────────────────────────────────────────────────────────────────────────────

# ── Module load ───────────────────────────────────────────────────────────────
Get-Module Microsoft.Graph.Authentication -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1 | Import-Module -Force
Get-Module Microsoft.Graph.Groups         -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1 | Import-Module -Force

# ── Connect ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  MFAMap — Test User Setup" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Connecting to Microsoft Graph..." -ForegroundColor DarkGray

try {
    Connect-MgGraph `
        -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "GroupMember.ReadWrite.All", "UserAuthenticationMethod.ReadWrite.All", "Policy.Read.All" `
        -NoWelcome `
        -ErrorAction Stop
    $connectedAs = (Get-MgContext).Account
    Write-Host "  Connected as $connectedAs" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to connect to Microsoft Graph." -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ── Helper: TOTP code generation (RFC 6238 / HMAC-SHA1) ──────────────────────
function ConvertFrom-Base32 {
    param ([string]$Base32)
    $alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bits = ""
    foreach ($char in $Base32.ToUpper().ToCharArray()) {
        $idx = $alphabet.IndexOf($char)
        if ($idx -lt 0) { continue }
        $bits += [Convert]::ToString($idx, 2).PadLeft(5, '0')
    }
    $bytes = @()
    for ($i = 0; $i + 8 -le $bits.Length; $i += 8) {
        $bytes += [Convert]::ToByte($bits.Substring($i, 8), 2)
    }
    return [byte[]]$bytes
}

function Get-TotpCode {
    param ([string]$Base32Secret)
    $key       = ConvertFrom-Base32 $Base32Secret
    $counter   = [long][Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 30)
    $timeBytes = [byte[]]::new(8)
    for ($i = 7; $i -ge 0; $i--) {
        $timeBytes[$i] = [byte]($counter -band 0xFF)
        $counter       = $counter -shr 8
    }
    $hmac      = New-Object System.Security.Cryptography.HMACSHA1
    $hmac.Key  = $key
    $hash      = $hmac.ComputeHash($timeBytes)
    $offset    = $hash[$hash.Length - 1] -band 0x0F
    $code      = (($hash[$offset]     -band 0x7F) -shl 24) -bor
                 (($hash[$offset + 1] -band 0xFF) -shl 16) -bor
                 (($hash[$offset + 2] -band 0xFF) -shl 8)  -bor
                  ($hash[$offset + 3] -band 0xFF)
    return ($code % 1000000).ToString("000000")
}

function New-Base32Secret {
    $bytes = [byte[]]::new(20)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $bits   = ($bytes | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ""
    $result = ""
    for ($i = 0; $i + 5 -le $bits.Length; $i += 5) {
        $result += $alphabet[[Convert]::ToByte($bits.Substring($i, 5), 2)]
    }
    return $result
}

# ── Helper: create or retrieve a user ────────────────────────────────────────
function New-TestUser {
    param ([string]$DisplayName)
    $upn = "$($DisplayName.ToLower() -replace '[^a-z0-9]', '-')@$TenantDomain"

    try {
        $existing = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$upn`?`$select=id,displayName,userPrincipalName" -ErrorAction Stop
        Write-Host "    $DisplayName — already exists, skipping creation" -ForegroundColor Yellow
        return [PSCustomObject]@{ Id = $existing.id; DisplayName = $existing.displayName; UPN = $existing.userPrincipalName; Created = $false }
    } catch {}

    try {
        $body = @{
            displayName         = $DisplayName
            mailNickname        = $DisplayName.ToLower() -replace '[^a-z0-9]', '-'
            userPrincipalName   = $upn
            accountEnabled      = $true
            passwordProfile     = @{
                password                      = $TestPassword
                forceChangePasswordNextSignIn = $false
            }
        }
        $user = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users" -Body $body -ErrorAction Stop
        Write-Host "    $DisplayName — created ($upn)" -ForegroundColor Green
        return [PSCustomObject]@{ Id = $user.id; DisplayName = $user.displayName; UPN = $user.userPrincipalName; Created = $true }
    } catch {
        Write-Host "    ERROR creating $DisplayName`: $_" -ForegroundColor Red
        return $null
    }
}

# ── Create test users ─────────────────────────────────────────────────────────
Write-Host "  Creating test users..." -ForegroundColor DarkGray
Write-Host ""

$userDefs = @(
    "MFAMap-Test-FullModern",
    "MFAMap-Test-AuthOnly",
    "MFAMap-Test-WHfBOnly",
    "MFAMap-Test-NoMethods",
    "MFAMap-Test-TotpOnly",
    "MFAMap-Test-Fido2",
    "MFAMap-Test-SmsOnly",
    "MFAMap-Test-VoiceOnly",
    "MFAMap-Test-EmailOnly",
    "MFAMap-Test-Mixed"
)

$testUsers = @{}
foreach ($name in $userDefs) {
    $u = New-TestUser -DisplayName $name
    if ($u) { $testUsers[$name] = $u }
}
Write-Host ""

# ── Create or retrieve test group ─────────────────────────────────────────────
Write-Host "  Setting up MFAMap-Test-Group..." -ForegroundColor DarkGray

$groupId = $null
try {
    $groupSearch = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq 'MFAMap-Test-Group'&`$select=id,displayName" -ErrorAction Stop
    if ($groupSearch.value.Count -gt 0) {
        $groupId = $groupSearch.value[0].id
        Write-Host "    Group already exists — using existing ($groupId)" -ForegroundColor Yellow
    }
} catch {}

if (-not $groupId) {
    try {
        $groupBody = @{
            displayName     = "MFAMap-Test-Group"
            mailEnabled     = $false
            mailNickname    = "mfamap-test-group"
            securityEnabled = $true
        }
        $newGroup = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups" -Body $groupBody -ErrorAction Stop
        $groupId  = $newGroup.id
        Write-Host "    Created MFAMap-Test-Group ($groupId)" -ForegroundColor Green
    } catch {
        Write-Host "    ERROR creating group: $_" -ForegroundColor Red
        $groupId = $null
    }
}

if ($groupId) {
    Write-Host "    Adding members to group..." -ForegroundColor DarkGray
    try {
        $existingMembers = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members?`$select=id" -ErrorAction Stop).value | ForEach-Object { $_.id })
    } catch {
        $existingMembers = @()
    }

    foreach ($u in $testUsers.Values) {
        if ($existingMembers -contains $u.Id) {
            Write-Host "      $($u.DisplayName) — already a member" -ForegroundColor Yellow
            continue
        }
        try {
            $refBody = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($u.Id)" }
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" -Body $refBody -ErrorAction Stop | Out-Null
            Write-Host "      $($u.DisplayName) — added" -ForegroundColor Green
        } catch {
            Write-Host "      ERROR adding $($u.DisplayName) to group: $_" -ForegroundColor Red
        }
    }
}
Write-Host ""

# Brief pause — newly created accounts sometimes take a moment to propagate
# before authentication method endpoints become available
Write-Host "  Waiting for accounts to propagate..." -ForegroundColor DarkGray
Start-Sleep -Seconds 8
Write-Host ""

# ── Auth method setup ─────────────────────────────────────────────────────────
Write-Host "  Configuring authentication methods..." -ForegroundColor DarkGray
Write-Host ""

# Check which methods are enabled in the tenant's Authentication Methods Policy.
# Disabled methods cannot be set via the API — those users get added to manual steps.
function Test-AuthMethodEnabled {
    param ([string]$MethodId)
    try {
        $p = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/$MethodId" -ErrorAction Stop
        return ($p.state -eq "enabled")
    } catch {
        return $null  # unknown — will attempt and handle errors at set time
    }
}

Write-Host "  Checking Authentication Methods Policy..." -ForegroundColor DarkGray
$authMethodPolicy = @{
    Sms          = Test-AuthMethodEnabled -MethodId "sms"
    Voice        = Test-AuthMethodEnabled -MethodId "voice"
    Email        = Test-AuthMethodEnabled -MethodId "email"
    SoftwareOath = Test-AuthMethodEnabled -MethodId "softwareOath"
}
$policyLabels = @{ Sms = "SMS"; Voice = "Voice"; Email = "Email OTP"; SoftwareOath = "Software OATH" }
foreach ($key in @("Sms", "Voice", "Email", "SoftwareOath")) {
    $state = switch ($authMethodPolicy[$key]) {
        $true  { "enabled" }
        $false { "DISABLED — will skip, added to manual steps" }
        default { "unknown (will attempt)" }
    }
    $color = if ($authMethodPolicy[$key] -eq $false) { "Yellow" } else { "DarkGray" }
    Write-Host "    $($policyLabels[$key]): $state" -ForegroundColor $color
}
Write-Host ""

$methodResults = @{}
foreach ($name in $testUsers.Keys) { $methodResults[$name] = @() }
$policySkipped = @()

function Set-PhoneMethod {
    param ([string]$UserId, [string]$UserName, [string]$PhoneNumber, [string]$PhoneType, [string]$Label)
    try {
        $existing = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/phoneMethods" -ErrorAction Stop
        $already  = @($existing.value) | Where-Object { $_.phoneType -eq $PhoneType }
        if ($already) {
            Write-Host "      $UserName — $Label already set" -ForegroundColor Yellow
            return $true
        }
    } catch {}

    try {
        $body = @{ phoneNumber = $PhoneNumber; phoneType = $PhoneType }
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/phoneMethods" -Body $body -ErrorAction Stop | Out-Null
        Write-Host "      $UserName — $Label set" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "      ERROR setting $Label for $UserName`: $_" -ForegroundColor Red
        return $false
    }
}

function Set-EmailMethod {
    param ([string]$UserId, [string]$UserName, [string]$EmailAddress)
    try {
        $existing = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/emailMethods" -ErrorAction Stop
        if (@($existing.value).Count -gt 0) {
            Write-Host "      $UserName — Email OTP already set" -ForegroundColor Yellow
            return $true
        }
    } catch {}

    try {
        $body = @{ emailAddress = $EmailAddress }
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/emailMethods" -Body $body -ErrorAction Stop | Out-Null
        Write-Host "      $UserName — Email OTP set" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "      ERROR setting Email OTP for $UserName`: $_" -ForegroundColor Red
        return $false
    }
}

function Set-SoftwareOath {
    param ([string]$UserId, [string]$UserName)
    try {
        $existing = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/softwareOathMethods" -ErrorAction Stop
        if (@($existing.value).Count -gt 0) {
            Write-Host "      $UserName — Software OATH already set" -ForegroundColor Yellow
            return $true
        }
    } catch {}

    try {
        $secret   = New-Base32Secret
        $addBody  = @{ secretKey = $secret }
        $addResp  = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/softwareOathMethods" -Body $addBody -ErrorAction Stop
        $methodId = $addResp.id

        Start-Sleep -Milliseconds 500
        $totpCode    = Get-TotpCode -Base32Secret $secret
        $activateBody = @{ verificationCode = $totpCode }
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$UserId/authentication/softwareOathMethods/$methodId/activate" -Body $activateBody -ErrorAction Stop | Out-Null
        Write-Host "      $UserName — Software OATH (TOTP) registered and activated" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "      ERROR setting Software OATH for $UserName`: $_" -ForegroundColor Red
        return $false
    }
}

# Test-TotpOnly: Software OATH
Write-Host "    Test-TotpOnly:" -ForegroundColor White
if ($testUsers.ContainsKey("MFAMap-Test-TotpOnly")) {
    if ($authMethodPolicy.SoftwareOath -eq $false) {
        Write-Host "      Skipped — Software OATH is disabled in the Authentication Methods Policy" -ForegroundColor Yellow
        $policySkipped += "MFAMap-Test-TotpOnly  — Register: Software OATH token (TOTP)"
    } else {
        $ok = Set-SoftwareOath -UserId $testUsers["MFAMap-Test-TotpOnly"].Id -UserName "MFAMap-Test-TotpOnly"
        if ($ok) { $methodResults["MFAMap-Test-TotpOnly"] += "Software OATH (TOTP)" }
    }
}

# Test-SmsOnly: SMS (mobile)
Write-Host "    Test-SmsOnly:" -ForegroundColor White
if ($testUsers.ContainsKey("MFAMap-Test-SmsOnly")) {
    if ($authMethodPolicy.Sms -eq $false) {
        Write-Host "      Skipped — SMS is disabled in the Authentication Methods Policy" -ForegroundColor Yellow
        $policySkipped += "MFAMap-Test-SmsOnly   — Register: SMS phone number ($SmsPhoneNumber)"
    } else {
        $ok = Set-PhoneMethod -UserId $testUsers["MFAMap-Test-SmsOnly"].Id -UserName "MFAMap-Test-SmsOnly" -PhoneNumber $SmsPhoneNumber -PhoneType "mobile" -Label "SMS (mobile)"
        if ($ok) { $methodResults["MFAMap-Test-SmsOnly"] += "SMS" }
    }
}

# Test-VoiceOnly: Voice (office — alternateMobile requires a mobile number to exist first)
Write-Host "    Test-VoiceOnly:" -ForegroundColor White
if ($testUsers.ContainsKey("MFAMap-Test-VoiceOnly")) {
    if ($authMethodPolicy.Voice -eq $false) {
        Write-Host "      Skipped — Voice is disabled in the Authentication Methods Policy" -ForegroundColor Yellow
        $policySkipped += "MFAMap-Test-VoiceOnly — Register: Office phone number ($VoicePhoneNumber)"
    } else {
        $ok = Set-PhoneMethod -UserId $testUsers["MFAMap-Test-VoiceOnly"].Id -UserName "MFAMap-Test-VoiceOnly" -PhoneNumber $VoicePhoneNumber -PhoneType "office" -Label "Voice (office)"
        if ($ok) { $methodResults["MFAMap-Test-VoiceOnly"] += "Voice" }
    }
}

# Test-EmailOnly: Email OTP
Write-Host "    Test-EmailOnly:" -ForegroundColor White
if ($testUsers.ContainsKey("MFAMap-Test-EmailOnly")) {
    if ($authMethodPolicy.Email -eq $false) {
        Write-Host "      Skipped — Email OTP is disabled in the Authentication Methods Policy" -ForegroundColor Yellow
        $policySkipped += "MFAMap-Test-EmailOnly — Register: Email OTP ($TestEmailAddress)"
    } else {
        $ok = Set-EmailMethod -UserId $testUsers["MFAMap-Test-EmailOnly"].Id -UserName "MFAMap-Test-EmailOnly" -EmailAddress $TestEmailAddress
        if ($ok) { $methodResults["MFAMap-Test-EmailOnly"] += "Email OTP" }
    }
}

# Test-Mixed: SMS (Authenticator push done manually)
Write-Host "    Test-Mixed:" -ForegroundColor White
if ($testUsers.ContainsKey("MFAMap-Test-Mixed")) {
    if ($authMethodPolicy.Sms -eq $false) {
        Write-Host "      Skipped — SMS is disabled in the Authentication Methods Policy" -ForegroundColor Yellow
        $policySkipped += "MFAMap-Test-Mixed     — Register: SMS phone number ($SmsPhoneNumber)"
    } else {
        $ok = Set-PhoneMethod -UserId $testUsers["MFAMap-Test-Mixed"].Id -UserName "MFAMap-Test-Mixed" -PhoneNumber $SmsPhoneNumber -PhoneType "mobile" -Label "SMS (mobile)"
        if ($ok) { $methodResults["MFAMap-Test-Mixed"] += "SMS" }
    }
}

Write-Host ""

# ── Disconnect ────────────────────────────────────────────────────────────────
Write-Host "  Disconnecting from Microsoft Graph..." -ForegroundColor DarkGray
try {
    Disconnect-MgGraph -ErrorAction Stop | Out-Null
    $ctx = Get-MgContext
    if ($null -eq $ctx) {
        Write-Host "  Disconnected from Microsoft Graph" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Session may still be active. Run Disconnect-MgGraph manually." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  WARNING: Could not disconnect automatically. Run Disconnect-MgGraph manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Summary: users ────────────────────────────────────────────────────────────
Write-Host "  USERS CREATED / CONFIRMED" -ForegroundColor Cyan
Write-Host ""
Write-Host ("  {0,-35} {1,-45} {2}" -f "Display name", "UPN", "Methods set now") -ForegroundColor White
Write-Host ("  {0,-35} {1,-45} {2}" -f ("-" * 34), ("-" * 44), ("-" * 20)) -ForegroundColor DarkGray

$displayOrder = @(
    "MFAMap-Test-FullModern",
    "MFAMap-Test-AuthOnly",
    "MFAMap-Test-WHfBOnly",
    "MFAMap-Test-NoMethods",
    "MFAMap-Test-TotpOnly",
    "MFAMap-Test-Fido2",
    "MFAMap-Test-SmsOnly",
    "MFAMap-Test-VoiceOnly",
    "MFAMap-Test-EmailOnly",
    "MFAMap-Test-Mixed"
)

foreach ($name in $displayOrder) {
    if (-not $testUsers.ContainsKey($name)) { continue }
    $u       = $testUsers[$name]
    $methods = if ($methodResults[$name].Count -gt 0) { $methodResults[$name] -join ", " } else { "— (manual steps required)" }
    Write-Host ("  {0,-35} {1,-45} {2}" -f $u.DisplayName, $u.UPN, $methods)
}

Write-Host ""

# ── Summary: group ID ─────────────────────────────────────────────────────────
if ($groupId) {
    Write-Host "  TEST GROUP OBJECT ID" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Copy this into MFAMap when prompted for a Group ID:" -ForegroundColor White
    Write-Host ""
    Write-Host "  $groupId" -ForegroundColor Cyan
    Write-Host ""
}

# ── Summary: manual steps ─────────────────────────────────────────────────────
Write-Host "  MANUAL STEPS REQUIRED" -ForegroundColor Yellow
Write-Host ""
Write-Host "  The following methods require a device and must be registered manually." -ForegroundColor White
Write-Host "  In Entra admin center (entra.microsoft.com):" -ForegroundColor White
Write-Host "  Users → [user] → Authentication methods → Add method" -ForegroundColor White
Write-Host ""
Write-Host "  1. MFAMap-Test-FullModern" -ForegroundColor White
Write-Host "     Register: Microsoft Authenticator (push notification)" -ForegroundColor Gray
Write-Host "     Register: Windows Hello for Business" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. MFAMap-Test-AuthOnly" -ForegroundColor White
Write-Host "     Register: Microsoft Authenticator (push notification)" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. MFAMap-Test-WHfBOnly" -ForegroundColor White
Write-Host "     Register: Windows Hello for Business" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. MFAMap-Test-Fido2" -ForegroundColor White
Write-Host "     Register: FIDO2 security key or Authenticator device-bound passkey" -ForegroundColor Gray
Write-Host ""
Write-Host "  5. MFAMap-Test-Mixed" -ForegroundColor White
Write-Host "     Register: Microsoft Authenticator (push notification)" -ForegroundColor Gray
$mixedSmsNote = if ($methodResults.ContainsKey("MFAMap-Test-Mixed") -and $methodResults["MFAMap-Test-Mixed"] -contains "SMS") {
    "(SMS has already been set automatically)"
} else {
    "(SMS also required — see policy steps below)"
}
Write-Host "     $mixedSmsNote" -ForegroundColor DarkGray
Write-Host ""

if ($policySkipped.Count -gt 0) {
    Write-Host "  POLICY-DISABLED METHODS — additional manual steps" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  These were skipped because the method is disabled in your tenant's" -ForegroundColor White
    Write-Host "  Authentication Methods Policy. Enable each one first at:" -ForegroundColor White
    Write-Host "  entra.microsoft.com → Protection → Authentication methods → [method] → Enable" -ForegroundColor White
    Write-Host "  Then add the method manually in Entra admin center, or re-run this script." -ForegroundColor White
    Write-Host ""
    foreach ($item in $policySkipped) {
        Write-Host "  - $item" -ForegroundColor Gray
    }
    Write-Host ""
}

Write-Host "  ─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
