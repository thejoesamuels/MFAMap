# ============================================================================
# MFAMap.ps1
# Authentication method mapper for Microsoft Entra ID
#
# Modes:
#   1 — Microsoft Authenticator + Windows Hello for Business
#   2 — Windows Hello for Business only
#   3 — Microsoft Authenticator only
#   4 — Passkey (FIDO2 or Authenticator device-bound passkey)
#   5 — Full method audit (all authentication methods)
#
# Usage:
#   .\MFAMap.ps1 -GroupId "your-group-object-id"
#   .\MFAMap.ps1 -GroupId "your-group-object-id" -OutputPath "C:\Reports\report.html"
#
# Requirements:
#   Install-Module Microsoft.Graph -Scope CurrentUser -Force
# ============================================================================

param(
    [Parameter(Mandatory = $false)]
    [string]$GroupId = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "",

    [Parameter(Mandatory = $false)]
    [switch]$Demo,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1,5)]
    [int]$Mode = 0
)

if (-not $Demo -and [string]::IsNullOrEmpty($GroupId)) {
    Write-Host "  ERROR: -GroupId is required unless running with -Demo." -ForegroundColor Red
    exit 1
}

Add-Type -AssemblyName System.Web

Get-Module Microsoft.Graph.Authentication -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1 | Import-Module -Force
Get-Module Microsoft.Graph.Groups         -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1 | Import-Module -Force

# ── Mode selection ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  MFAMap" -ForegroundColor Cyan
Write-Host "  Authentication Method Mapper" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Select tracking mode:" -ForegroundColor White
Write-Host "  [1]  Authenticator App + Windows Hello for Business" -ForegroundColor Gray
Write-Host "  [2]  Windows Hello for Business only" -ForegroundColor Gray
Write-Host "  [3]  Authenticator App only" -ForegroundColor Gray
Write-Host "  [4]  Passkey (FIDO2 or Authenticator device-bound passkey)" -ForegroundColor Gray
Write-Host "  [5]  Full method audit (all authentication methods)" -ForegroundColor Gray
Write-Host ""

if ($Mode -ge 1 -and $Mode -le 5) {
    $mode = $Mode
} else {
    do { $modeInput = Read-Host "  Enter choice (1-5)" } while ($modeInput -notin @('1','2','3','4','5'))
    $mode = [int]$modeInput
}

$modeLabel = switch ($mode) {
    1 { "Authenticator + WHfB" }
    2 { "Windows Hello for Business" }
    3 { "Microsoft Authenticator" }
    4 { "Passkey" }
    5 { "Full Method Audit" }
}
$modeShort = switch ($mode) {
    1 { "Mode1-Auth-WHfB" }
    2 { "Mode2-WHfB" }
    3 { "Mode3-Auth" }
    4 { "Mode4-Passkey" }
    5 { "Mode5-Audit" }
}

Write-Host ""
Write-Host "  Mode: $modeLabel" -ForegroundColor Cyan
Write-Host ""

if (-not $Demo) {

# ── Connect ───────────────────────────────────────────────────────────────────
Write-Host "  Connecting to Microsoft Graph..." -ForegroundColor DarkGray

try {
    Connect-MgGraph -Scopes "GroupMember.Read.All", "UserAuthenticationMethod.Read.All", "User.Read.All", "Group.Read.All", "Organization.Read.All" -NoWelcome -ErrorAction Stop
    $connectedAs = (Get-MgContext).Account
    Write-Host "  Connected as $connectedAs" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Failed to connect to Microsoft Graph." -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}
Write-Host ""

# ── Tenant name ───────────────────────────────────────────────────────────────
Write-Host "  Fetching tenant details..." -ForegroundColor DarkGray
try {
    $orgResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization?`$select=displayName" -ErrorAction Stop
    $tenantName = $orgResponse.value[0].displayName
    if ([string]::IsNullOrEmpty($tenantName)) { $tenantName = "" } else { Write-Host "  Tenant: $tenantName" -ForegroundColor Green }
} catch {
    Write-Host "  WARNING: Could not retrieve tenant name." -ForegroundColor Yellow
    $tenantName = ""
}

# ── Group name ────────────────────────────────────────────────────────────────
Write-Host "  Fetching group details..." -ForegroundColor DarkGray
try {
    $groupResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId`?`$select=displayName" -ErrorAction Stop
    $groupName = $groupResponse.displayName
    Write-Host "  Group: $groupName" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Could not retrieve group name." -ForegroundColor Yellow
    $groupName = $GroupId
}

} else {
    $tenantName = "Demo Tenant"
    $groupName  = "Demo Group"
    Write-Host "  Demo mode — no credentials required." -ForegroundColor Cyan
    Write-Host ""
}

# ── Output filename ───────────────────────────────────────────────────────────
$safeName      = $groupName -replace '[^\w\s-]', '' -replace '\s+', '-'
$timestamp     = Get-Date -Format "yyyy-MM-dd_HHmm"
$suggestedName = "mfamap_${safeName}_${modeShort}_${timestamp}.html"

if ($OutputPath -eq "") {
    $dialogUsed = $false

    if ($IsWindows) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Title            = "Save MFAMap Report"
            $dlg.Filter           = "HTML file (*.html)|*.html"
            $dlg.FileName         = $suggestedName
            $dlg.InitialDirectory = (Get-Location).Path
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $OutputPath = $dlg.FileName
                $dialogUsed = $true
            } else {
                Write-Host "  Save cancelled. Exiting." -ForegroundColor Yellow
                exit 0
            }
        } catch { }
    } elseif ($IsMacOS) {
        try {
            $osResult = osascript -e "POSIX path of (choose file name with prompt `"Save MFAMap Report`" default name `"$suggestedName`")" 2>$null
            if ($LASTEXITCODE -eq 0 -and $osResult) {
                $OutputPath = $osResult.Trim()
                if (-not $OutputPath.EndsWith(".html")) { $OutputPath += ".html" }
                $dialogUsed = $true
            }
        } catch { }
    }

    if (-not $dialogUsed) {
        $OutputPath = ".\$suggestedName"
    }
}
Write-Host ""

if (-not $Demo) {

# ── Group members ─────────────────────────────────────────────────────────────
Write-Host "  Fetching group members..." -ForegroundColor DarkGray
$skippedMembers = @()
try {
    $memberObjects = @(Get-MgGroupMember -GroupId $GroupId -All -ErrorAction Stop)

    $members = foreach ($m in $memberObjects) {
        try {
            $response = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($m.Id)?`$select=id,displayName,userPrincipalName" -ErrorAction Stop
            [PSCustomObject]@{
                Id                = $response.id
                DisplayName       = $response.displayName
                UserPrincipalName = $response.userPrincipalName
            }
        } catch {
            $skippedMembers += $m.Id
        }
    }
    $members = @($members | Where-Object { $_ -ne $null })
} catch {
    Write-Host "  ERROR: Could not retrieve group members. Check the Group ID is correct." -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

if ($skippedMembers.Count -gt 0) {
    Write-Host "  WARNING: $($skippedMembers.Count) group member(s) could not be resolved and will be excluded from the report:" -ForegroundColor Yellow
    $skippedMembers | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
    Write-Host ""
}

$totalCount = $members.Count
if ($totalCount -eq 0) {
    Write-Host "  ERROR: No users found in this group. Check the Group ID." -ForegroundColor Red
    exit 1
}
Write-Host "  Found $totalCount members." -ForegroundColor Green
Write-Host ""

# ── Auth methods ──────────────────────────────────────────────────────────────
Write-Host "  Checking authentication methods..." -ForegroundColor DarkGray

$users = @()
$errorUsers = @()
$i = 0

foreach ($member in $members) {
    $i++
    Write-Progress -Activity "MFAMap" -Status "Checking $($member.DisplayName) ($i of $totalCount)" -PercentComplete (($i / $totalCount) * 100)

    $hasAuthenticator = $false
    $hasWHfB          = $false
    $hasPasskey       = $false
    $fetchError       = $false
    $isTotpOnly       = $false
    $hasFido2         = $false
    $hasSoftwareOath  = $false
    $hasSms           = $false
    $hasVoice         = $false
    $hasEmail         = $false

    # Only fetch what we need based on mode
    if ($mode -in @(1,3,4)) {
        try {
            $authResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/microsoftAuthenticatorMethods" -ErrorAction Stop
            $authMethods = @($authResp.value)
            $hasAuthenticator = $authMethods.Count -gt 0
            $hasPasskey = ($authMethods | Where-Object { $_.deviceTag -eq 'SoftwareTokenPasskey' -or $_.authenticationMode -eq 'deviceBoundPushNotification' }).Count -gt 0
        } catch {
            $fetchError = $true
        }

        if (-not $hasAuthenticator -and -not $fetchError) {
            try {
                $oathResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/softwareOathMethods" -ErrorAction Stop
                if (@($oathResp.value).Count -gt 0) {
                    $hasAuthenticator = $true
                    $isTotpOnly       = $true
                }
            } catch {
                $fetchError = $true
            }
        }
    }

    if ($mode -in @(1,2)) {
        try {
            $whfbResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/windowsHelloForBusinessMethods" -ErrorAction Stop
            $hasWHfB = @($whfbResp.value).Count -gt 0
        } catch {
            $fetchError = $true
        }
    }

    if ($mode -eq 4) {
        try {
            $fido2Resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/fido2Methods" -ErrorAction Stop
            if (@($fido2Resp.value).Count -gt 0) { $hasPasskey = $true }
        } catch {
            $fetchError = $true
        }
    }

    if ($mode -eq 5) {
        try {
            $authResp5 = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/microsoftAuthenticatorMethods" -ErrorAction Stop
            $hasAuthenticator = @($authResp5.value).Count -gt 0
        } catch { $fetchError = $true }

        try {
            $whfbResp5 = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/windowsHelloForBusinessMethods" -ErrorAction Stop
            $hasWHfB = @($whfbResp5.value).Count -gt 0
        } catch { $fetchError = $true }

        try {
            $fido2Resp5 = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/fido2Methods" -ErrorAction Stop
            $hasFido2 = @($fido2Resp5.value).Count -gt 0
        } catch { $fetchError = $true }

        try {
            $oathResp5 = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/softwareOathMethods" -ErrorAction Stop
            $hasSoftwareOath = @($oathResp5.value).Count -gt 0
        } catch { $fetchError = $true }

        try {
            $phoneResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/phoneMethods" -ErrorAction Stop
            $phoneMethods = @($phoneResp.value)
            $hasSms   = ($phoneMethods | Where-Object { $_.phoneType -eq 'mobile' }).Count -gt 0
            $hasVoice = ($phoneMethods | Where-Object { $_.phoneType -in @('alternateMobile','office') }).Count -gt 0
        } catch { $fetchError = $true }

        try {
            $emailResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/emailMethods" -ErrorAction Stop
            $hasEmail = @($emailResp.value).Count -gt 0
        } catch { $fetchError = $true }

        $isLegacyOnly5 = (-not $hasAuthenticator -and -not $hasWHfB -and -not $hasFido2 -and -not $hasSoftwareOath) -and ($hasSms -or $hasVoice -or $hasEmail)
        $noMethods5    = (-not $hasAuthenticator -and -not $hasWHfB -and -not $hasFido2 -and -not $hasSoftwareOath -and -not $hasSms -and -not $hasVoice -and -not $hasEmail)
    }

    if ($fetchError) {
        $errorUsers += [PSCustomObject]@{
            Name  = $member.DisplayName
            Email = $member.UserPrincipalName
        }
    } else {
        $users += [PSCustomObject]@{
            Name             = $member.DisplayName
            Email            = $member.UserPrincipalName
            HasAuthenticator = $hasAuthenticator
            HasWHfB          = $hasWHfB
            HasPasskey       = $hasPasskey
            IsTotpOnly       = $isTotpOnly
            HasFido2         = $hasFido2
            HasSoftwareOath  = $hasSoftwareOath
            HasSms           = $hasSms
            HasVoice         = $hasVoice
            HasEmail         = $hasEmail
            IsLegacyOnly     = if ($mode -eq 5) { $isLegacyOnly5 } else { $false }
            NoMethods        = if ($mode -eq 5) { $noMethods5    } else { $false }
        }
    }
}

Write-Progress -Activity "MFAMap" -Completed

if ($errorUsers.Count -gt 0) {
    Write-Host ""
    Write-Host "  WARNING: Could not retrieve auth methods for $($errorUsers.Count) user(s) — excluded from report:" -ForegroundColor Yellow
    $errorUsers | ForEach-Object { Write-Host "    - $($_.Name) ($($_.Email))" -ForegroundColor Yellow }
}

} else {

# ── Demo users ────────────────────────────────────────────────────────────────
$users = @(
    # Complete — Auth + WHfB
    [PSCustomObject]@{ Name="Alice Johnson";  Email="alice.johnson@demo.internal";  HasAuthenticator=$true;  HasWHfB=$true;  HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    [PSCustomObject]@{ Name="Ben Carter";     Email="ben.carter@demo.internal";     HasAuthenticator=$true;  HasWHfB=$true;  HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    [PSCustomObject]@{ Name="Carol Davies";   Email="carol.davies@demo.internal";   HasAuthenticator=$true;  HasWHfB=$true;  HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    [PSCustomObject]@{ Name="David Evans";    Email="david.evans@demo.internal";    HasAuthenticator=$true;  HasWHfB=$true;  HasPasskey=$true;  IsTotpOnly=$false; HasFido2=$true;  HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    [PSCustomObject]@{ Name="Emma Foster";    Email="emma.foster@demo.internal";    HasAuthenticator=$true;  HasWHfB=$true;  HasPasskey=$true;  IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    [PSCustomObject]@{ Name="Sophie Adams";   Email="sophie.adams@demo.internal";   HasAuthenticator=$true;  HasWHfB=$true;  HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    [PSCustomObject]@{ Name="Tom Wilson";     Email="tom.wilson@demo.internal";     HasAuthenticator=$true;  HasWHfB=$true;  HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    # Partial — Auth only
    [PSCustomObject]@{ Name="Frank Green";    Email="frank.green@demo.internal";    HasAuthenticator=$true;  HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    [PSCustomObject]@{ Name="Grace Hill";     Email="grace.hill@demo.internal";     HasAuthenticator=$true;  HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$true;  HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    # Partial — WHfB only
    [PSCustomObject]@{ Name="Harry Irving";   Email="harry.irving@demo.internal";   HasAuthenticator=$false; HasWHfB=$true;  HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    # TOTP only (Mode 3 special badge)
    [PSCustomObject]@{ Name="Isabel Jones";   Email="isabel.jones@demo.internal";   HasAuthenticator=$true;  HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$true;  HasFido2=$false; HasSoftwareOath=$true;  HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    # Passkey registered (Mode 4)
    [PSCustomObject]@{ Name="Jack King";      Email="jack.king@demo.internal";      HasAuthenticator=$false; HasWHfB=$false; HasPasskey=$true;  IsTotpOnly=$false; HasFido2=$true;  HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    [PSCustomObject]@{ Name="Karen Lee";      Email="karen.lee@demo.internal";      HasAuthenticator=$true;  HasWHfB=$false; HasPasskey=$true;  IsTotpOnly=$false; HasFido2=$true;  HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$false },
    # Legacy only (Mode 5)
    [PSCustomObject]@{ Name="Liam Moore";     Email="liam.moore@demo.internal";     HasAuthenticator=$false; HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$true;  HasVoice=$false; HasEmail=$false; IsLegacyOnly=$true;  NoMethods=$false },
    [PSCustomObject]@{ Name="Maya North";     Email="maya.north@demo.internal";     HasAuthenticator=$false; HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$true;  HasEmail=$false; IsLegacyOnly=$true;  NoMethods=$false },
    [PSCustomObject]@{ Name="Noah Oliver";    Email="noah.oliver@demo.internal";    HasAuthenticator=$false; HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$true;  HasVoice=$false; HasEmail=$true;  IsLegacyOnly=$true;  NoMethods=$false },
    # No methods registered
    [PSCustomObject]@{ Name="Olivia Price";   Email="olivia.price@demo.internal";   HasAuthenticator=$false; HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$true  },
    [PSCustomObject]@{ Name="Patrick Quinn";  Email="patrick.quinn@demo.internal";  HasAuthenticator=$false; HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$true  },
    [PSCustomObject]@{ Name="Rachel Smith";   Email="rachel.smith@demo.internal";   HasAuthenticator=$false; HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$true  },
    [PSCustomObject]@{ Name="Sam Taylor";     Email="sam.taylor@demo.internal";     HasAuthenticator=$false; HasWHfB=$false; HasPasskey=$false; IsTotpOnly=$false; HasFido2=$false; HasSoftwareOath=$false; HasSms=$false; HasVoice=$false; HasEmail=$false; IsLegacyOnly=$false; NoMethods=$true  }
)
$errorUsers     = @()
$skippedMembers = @()
Write-Host "  Loaded $($users.Count) demo users." -ForegroundColor Green
Write-Host ""

}

# ── Categorise ────────────────────────────────────────────────────────────────
switch ($mode) {
    1 {
        $notStarted = @($users | Where-Object { -not $_.HasAuthenticator -and -not $_.HasWHfB })
        $partial    = @($users | Where-Object { ($_.HasAuthenticator -or $_.HasWHfB) -and -not ($_.HasAuthenticator -and $_.HasWHfB) })
        $complete   = @($users | Where-Object { $_.HasAuthenticator -and $_.HasWHfB })
    }
    2 {
        $notStarted = @($users | Where-Object { -not $_.HasWHfB })
        $partial    = @()
        $complete   = @($users | Where-Object { $_.HasWHfB })
    }
    3 {
        $notStarted = @($users | Where-Object { -not $_.HasAuthenticator })
        $partial    = @()
        $complete   = @($users | Where-Object { $_.HasAuthenticator })
    }
    4 {
        $notStarted = @($users | Where-Object { -not $_.HasPasskey })
        $partial    = @()
        $complete   = @($users | Where-Object { $_.HasPasskey })
    }
    5 {
        $notStarted      = @()
        $partial         = @()
        $complete        = @()
        $noMethodsGroup  = @($users | Where-Object { $_.NoMethods })
        $legacyOnlyGroup = @($users | Where-Object { $_.IsLegacyOnly })
        $modernGroup     = @($users | Where-Object { -not $_.NoMethods -and -not $_.IsLegacyOnly })
    }
}

$totalUsers      = $users.Count
$notStartedCount = $notStarted.Count
$partialCount    = $partial.Count
$completeCount   = $complete.Count

$pctComplete = if ($totalUsers -gt 0) { [math]::Round(($completeCount / $totalUsers) * 100, 1) } else { 0 }
$pctPartial  = if ($totalUsers -gt 0) { [math]::Round(($partialCount  / $totalUsers) * 100, 1) } else { 0 }

Write-Host ""
Write-Host "  Results:" -ForegroundColor Cyan
Write-Host "    Total:        $totalUsers" -ForegroundColor White
if ($mode -eq 5) {
    Write-Host "    No methods:   $($noMethodsGroup.Count)"  -ForegroundColor Red
    Write-Host "    Legacy only:  $($legacyOnlyGroup.Count)" -ForegroundColor Yellow
    Write-Host "    Modern:       $($modernGroup.Count)"     -ForegroundColor Green
} else {
    Write-Host "    Not registered: $notStartedCount" -ForegroundColor Red
    if ($partialCount -gt 0) { Write-Host "    Partial:      $partialCount" -ForegroundColor Yellow }
    Write-Host "    Complete:     $completeCount"   -ForegroundColor Green
}
Write-Host ""

# ── Mode-specific accent colour ───────────────────────────────────────────────
$accentColor = switch ($mode) {
    1 { "#57BD84" }  # green
    2 { "#57BD84" }  # green
    3 { "#57BD84" }  # green
    4 { "#57BD84" }  # green
    5 { "#659AD2" }  # blue
}
$accentDim = switch ($mode) {
    1 { "rgba(87,189,132,0.12)" }
    2 { "rgba(87,189,132,0.12)" }
    3 { "rgba(87,189,132,0.12)" }
    4 { "rgba(87,189,132,0.12)" }
    5 { "rgba(101,154,210,0.12)" }
}

# ── HTML helpers ──────────────────────────────────────────────────────────────
function Get-Badge([bool]$registered) {
    if ($registered) { return '<span class="badge yes">&#10003; Registered</span>' }
    else             { return '<span class="badge no">&#10005; Not registered</span>' }
}

function Get-MethodCells($u, [int]$m) {
    switch ($m) {
        1 { return "<div>$(Get-Badge $u.HasAuthenticator)</div><div>$(Get-Badge $u.HasWHfB)</div>" }
        2 { return "<div>$(Get-Badge $u.HasWHfB)</div>" }
        3 {
            if ($u.IsTotpOnly) { return "<div><span class=`"badge warn`">&#10003; TOTP only</span></div>" }
            else               { return "<div>$(Get-Badge $u.HasAuthenticator)</div>" }
        }
        4 { return "<div>$(Get-Badge $u.HasPasskey)</div>" }
        5 {
            $tick = "&#10003;"
            $dash = "&ndash;"
            $auth  = if ($u.HasAuthenticator) { $tick } else { $dash }
            $whfb  = if ($u.HasWHfB)          { $tick } else { $dash }
            $fido  = if ($u.HasFido2)          { $tick } else { $dash }
            $oath  = if ($u.HasSoftwareOath)   { $tick } else { $dash }
            $sms   = if ($u.HasSms)            { $tick } else { $dash }
            $voice = if ($u.HasVoice)          { $tick } else { $dash }
            $email = if ($u.HasEmail)          { $tick } else { $dash }
            return "<div>$auth</div><div>$whfb</div><div>$fido</div><div>$oath</div><div>$sms</div><div>$voice</div><div>$email</div>"
        }
    }
}

function Get-TableHeader([int]$m) {
    switch ($m) {
        1 { return "<div>User</div><div>Authenticator App</div><div>Windows Hello</div><div>Status</div>" }
        2 { return "<div>User</div><div>Windows Hello</div><div>Status</div>" }
        3 { return "<div>User</div><div>Authenticator App</div><div>Status</div>" }
        4 { return "<div>User</div><div>Passkey</div><div>Status</div>" }
        5 { return "<div>User</div><div>Microsoft Authenticator</div><div>WHfB</div><div>FIDO2</div><div>Soft. OATH</div><div>SMS</div><div>Voice</div><div>Email OTP</div><div>Status</div>" }
    }
}

function Get-GridCols([int]$m) {
    switch ($m) {
        1       { return "1fr 170px 170px 110px" }
        5       { return "1fr 90px 80px 80px 110px 60px 70px 90px 110px" }
        default { return "1fr 200px 110px" }
    }
}

function Get-Rows($userList, [string]$statusType, [int]$m) {
    if ($userList.Count -eq 0) {
        $msg = switch ($statusType) {
            "none"        { "Everyone has started enrolment &#127881;" }
            "partial"     { "No partial enrolments" }
            "done"        { "No completed enrolments yet" }
            "no-methods"  { "No users without a registered method &#127881;" }
            "legacy-only" { "No legacy-only users" }
            "modern"      { "No users with modern methods yet" }
        }
        return "<div class=`"empty`">$msg</div>"
    }
    $rows = ""
    foreach ($u in $userList) {
        $methodCells = Get-MethodCells $u $m
        $pill = switch ($statusType) {
            "done"        { if ($m -eq 1) { '<span class="pill done">Complete</span>' } else { '<span class="pill done">Registered</span>' } }
            "partial"     { '<span class="pill partial">Partial</span>' }
            "none"        { '<span class="pill none">Not registered</span>' }
            "no-methods"  { '<span class="pill none">No methods</span>' }
            "legacy-only" { '<span class="pill partial">Legacy only</span>' }
            "modern"      { '<span class="pill done">&#10003;</span>' }
        }
        $safeName  = [System.Web.HttpUtility]::HtmlEncode($u.Name)
        $safeEmail = [System.Web.HttpUtility]::HtmlEncode($u.Email)
        $dataAttrs = ""
        if ($m -eq 5) {
            $da = if ($u.HasAuthenticator) { 1 } else { 0 }
            $dw = if ($u.HasWHfB)          { 1 } else { 0 }
            $df = if ($u.HasFido2)         { 1 } else { 0 }
            $do = if ($u.HasSoftwareOath)  { 1 } else { 0 }
            $ds = if ($u.HasSms)           { 1 } else { 0 }
            $dv = if ($u.HasVoice)         { 1 } else { 0 }
            $de = if ($u.HasEmail)         { 1 } else { 0 }
            $dn = if ($u.NoMethods)        { 1 } else { 0 }
            $dataAttrs = " data-auth=`"$da`" data-whfb=`"$dw`" data-fido2=`"$df`" data-oath=`"$do`" data-sms=`"$ds`" data-voice=`"$dv`" data-email=`"$de`" data-none=`"$dn`""
        }
        $rows += @"
        <div class="row"$dataAttrs>
          <div class="cell"><span class="name">$safeName</span><span class="email">$safeEmail</span></div>
          $methodCells
          <div>$pill</div>
        </div>
"@
    }
    return $rows
}

$gridCols        = Get-GridCols $mode
$tableHeaderHtml = Get-TableHeader $mode
$rowsNotStarted  = Get-Rows $notStarted "none"    $mode
$rowsPartial     = Get-Rows $partial    "partial" $mode
$rowsComplete    = Get-Rows $complete   "done"    $mode

if ($mode -eq 5) {
    $rowsNoMethods  = Get-Rows $noMethodsGroup  "no-methods"  5
    $rowsLegacy     = Get-Rows $legacyOnlyGroup "legacy-only" 5
    $rowsModern     = Get-Rows $modernGroup     "modern"      5
}

$safeGroupName  = [System.Web.HttpUtility]::HtmlEncode($groupName)
$safeTenantName = [System.Web.HttpUtility]::HtmlEncode($tenantName)
$safeModeLabel  = [System.Web.HttpUtility]::HtmlEncode($modeLabel)
$generatedAt    = Get-Date -Format "dd MMM yyyy 'at' HH:mm"

$headerSubtitle = if ($tenantName) { "$safeTenantName &middot; $safeGroupName" } else { $safeGroupName }

# ── Stat cards / method count banner ─────────────────────────────────────────
if ($mode -eq 5) {
    $cntAuth  = ($users | Where-Object { $_.HasAuthenticator }).Count
    $cntWHfB  = ($users | Where-Object { $_.HasWHfB }).Count
    $cntFido  = ($users | Where-Object { $_.HasFido2 }).Count
    $cntOath  = ($users | Where-Object { $_.HasSoftwareOath }).Count
    $cntSms   = ($users | Where-Object { $_.HasSms }).Count
    $cntVoice = ($users | Where-Object { $_.HasVoice }).Count
    $cntEmail = ($users | Where-Object { $_.HasEmail }).Count
    $cntNone  = $noMethodsGroup.Count
}

if ($mode -eq 1) {
    $statCards = @"
    <div class="stat total"><div class="stat-label">Total Users</div><div class="stat-number">$totalUsers</div><div class="stat-sub">in target group</div></div>
    <div class="stat remaining"><div class="stat-label">Not Registered</div><div class="stat-number">$notStartedCount</div><div class="stat-sub">not registered</div></div>
    <div class="stat partial"><div class="stat-label">Partial</div><div class="stat-number">$partialCount</div><div class="stat-sub">one method only</div></div>
    <div class="stat complete"><div class="stat-label">Fully Enrolled</div><div class="stat-number">$completeCount</div><div class="stat-sub">authenticator + WHfB</div></div>
"@
} elseif ($mode -eq 5) {
    $statCards = @"
    <div class="stat complete" data-filter="auth" onclick="filterBy('auth')" title="Filter by Microsoft Authenticator"><div class="stat-label">Microsoft Authenticator</div><div class="stat-number">$cntAuth</div><div class="stat-sub">users</div></div>
    <div class="stat complete" data-filter="whfb" onclick="filterBy('whfb')" title="Filter by WHfB"><div class="stat-label">WHfB</div><div class="stat-number">$cntWHfB</div><div class="stat-sub">users</div></div>
    <div class="stat complete" data-filter="fido2" onclick="filterBy('fido2')" title="Filter by FIDO2"><div class="stat-label">FIDO2</div><div class="stat-number">$cntFido</div><div class="stat-sub">users</div></div>
    <div class="stat complete" data-filter="oath" onclick="filterBy('oath')" title="Filter by Software OATH"><div class="stat-label">Software OATH</div><div class="stat-number">$cntOath</div><div class="stat-sub">users</div></div>
    <div class="stat partial" data-filter="sms" onclick="filterBy('sms')" title="Filter by SMS"><div class="stat-label">SMS</div><div class="stat-number">$cntSms</div><div class="stat-sub">users</div></div>
    <div class="stat partial" data-filter="voice" onclick="filterBy('voice')" title="Filter by Voice"><div class="stat-label">Voice</div><div class="stat-number">$cntVoice</div><div class="stat-sub">users</div></div>
    <div class="stat partial" data-filter="email" onclick="filterBy('email')" title="Filter by Email OTP"><div class="stat-label">Email OTP</div><div class="stat-number">$cntEmail</div><div class="stat-sub">users</div></div>
    <div class="stat remaining" data-filter="none" onclick="filterBy('none')" title="Filter: No Methods"><div class="stat-label">No Methods</div><div class="stat-number">$cntNone</div><div class="stat-sub">users</div></div>
"@
} else {
    $statCards = @"
    <div class="stat total"><div class="stat-label">Total Users</div><div class="stat-number">$totalUsers</div><div class="stat-sub">in target group</div></div>
    <div class="stat remaining"><div class="stat-label">Not Registered</div><div class="stat-number">$notStartedCount</div><div class="stat-sub">not registered</div></div>
    <div class="stat complete"><div class="stat-label">Registered</div><div class="stat-number">$completeCount</div><div class="stat-sub">$safeModeLabel</div></div>
    <div class="stat coverage"><div class="stat-label">Coverage</div><div class="stat-number">$pctComplete%</div><div class="stat-sub">of group enrolled</div></div>
"@
}

# ── Partial section (mode 1 only) ─────────────────────────────────────────────
$partialSection = if ($mode -eq 1) { @"
  <div class="section">
    <div class="section-header">
      <span class="section-title partial">Partially Enrolled</span>
      <span class="section-count partial">$partialCount</span>
    </div>
    <div class="table">
      <div class="table-header" style="grid-template-columns: $gridCols">$tableHeaderHtml</div>
      $rowsPartial
    </div>
  </div>
"@ } else { "" }

$progressPartialDiv   = if ($mode -eq 1) { '<div class="progress-partial"></div>' } else { "" }
$progressPartialLabel = if ($mode -eq 1) { " &middot; <span style=`"color:var(--amber)`">$partialCount partial</span>" } else { "" }
$completedLabel       = if ($mode -eq 1) { "Fully Enrolled" } else { "Registered" }

if ($mode -eq 5) {
    $noMethodsCount  = $noMethodsGroup.Count
    $legacyOnlyCount = $legacyOnlyGroup.Count
    $modernCount     = $modernGroup.Count
}

# ── Error users section (shown only if fetch errors occurred) ─────────────────
$errorSection = ""
if ($errorUsers.Count -gt 0) {
    $errorRows = ($errorUsers | ForEach-Object {
        $safeName  = [System.Web.HttpUtility]::HtmlEncode($_.Name)
        $safeEmail = [System.Web.HttpUtility]::HtmlEncode($_.Email)
        "<div class=`"row`"><div class=`"cell`"><span class=`"name`">$safeName</span><span class=`"email`">$safeEmail</span></div><div colspan=`"3`" style=`"color:var(--muted);font-size:0.8rem`">Auth method check failed &mdash; excluded from results</div></div>"
    }) -join "`n"
    $errorCount = $errorUsers.Count
    $errorSection = @"
  <div class="section">
    <div class="section-header">
      <span class="section-title" style="color:var(--amber)">Could Not Check</span>
      <span class="section-count" style="background:var(--amber-dim);color:var(--amber)">$errorCount</span>
    </div>
    <p style="font-size:0.8rem;color:var(--muted);margin-bottom:0.75rem">Auth method queries failed for these users. They are excluded from all counts. Re-run the script to retry.</p>
    <div class="table">
      $errorRows
    </div>
  </div>
"@
}

# ── Main sections HTML ────────────────────────────────────────────────────────
if ($mode -eq 5) {
    $mainSections = @"
  <p style="font-size:12px;color:var(--text-muted);margin-bottom:16px;">$totalUsers users &middot; <span style="color:var(--amber)">$legacyOnlyCount legacy-only</span> &middot; <span style="color:var(--red)">$noMethodsCount with no methods</span></p>

  <div id="filterBar" class="filter-bar" style="display:none">
    Filtering by <strong id="filterLabel"></strong>
    <button onclick="filterBy(activeFilter)">Clear</button>
  </div>

  <div class="section">
    <div class="section-header">
      <span class="section-title remaining">No Methods Registered</span>
      <span class="section-count remaining">$noMethodsCount</span>
    </div>
    <div class="table">
      <div class="table-header">$tableHeaderHtml</div>
      $rowsNoMethods
    </div>
  </div>

  <div class="section">
    <div class="section-header">
      <span class="section-title partial">Legacy Only</span>
      <span class="section-count partial">$legacyOnlyCount</span>
    </div>
    <div class="table">
      <div class="table-header">$tableHeaderHtml</div>
      $rowsLegacy
    </div>
  </div>

  $errorSection

  <div class="section">
    <div class="section-header">
      <button class="collapse-toggle" onclick="toggle()">
        <span class="section-title complete">Modern Methods</span>
        <span class="section-count complete">$modernCount</span>
        <span class="chevron open" id="chev">&#9658;</span>
      </button>
    </div>
    <div class="collapse-body open" id="completedBody">
      <div class="table">
        <div class="table-header">$tableHeaderHtml</div>
        $rowsModern
      </div>
    </div>
  </div>
"@
} else {
    $mainSections = @"
  <div class="progress-wrap">
    <div class="progress-label">
      <span>Enrolment Progress</span>
      <span><span style="color:var(--accent)">$completeCount complete</span>$progressPartialLabel &middot; <span style="color:var(--red)">$notStartedCount remaining</span></span>
    </div>
    <div class="progress-track">
      <div class="progress-complete"></div>
      $progressPartialDiv
    </div>
  </div>

  <div class="section">
    <div class="section-header">
      <span class="section-title remaining">Not Registered</span>
      <span class="section-count remaining">$notStartedCount</span>
    </div>
    <div class="table">
      <div class="table-header">$tableHeaderHtml</div>
      $rowsNotStarted
    </div>
  </div>

  $partialSection

  $errorSection

  <div class="section">
    <div class="section-header">
      <button class="collapse-toggle" onclick="toggle()">
        <span class="section-title complete">$completedLabel</span>
        <span class="section-count complete">$completeCount</span>
        <span class="chevron open" id="chev">&#9658;</span>
      </button>
    </div>
    <div class="collapse-body open" id="completedBody">
      <div class="table">
        <div class="table-header">$tableHeaderHtml</div>
        $rowsComplete
      </div>
    </div>
  </div>
"@
}



    $uiAccent    = "#F5CF18"
    $uiAccentDim = "rgba(245,207,24,0.12)"
    $bgNavy      = "#1A1A1A"
    $bgLight     = "#242424"
    $bgLighter   = "#2E2E2E"
    $logoHtml    = '<div class="logo">MFAMap</div>'
    $headerTitle = "Authentication Method Map"
    $footerText  = 'vibecoded by <span>JS</span> &#9889;'
    $pageTitle   = "MFAMap &mdash; $safeGroupName"


# ── Build HTML ────────────────────────────────────────────────────────────────
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$pageTitle</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=DM+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
  :root {
    --navy: $bgNavy; --navy-light: $bgLight; --navy-lighter: $bgLighter;
    --accent: $accentColor; --accent-dim: $accentDim;
    --ui-accent: $uiAccent; --ui-accent-dim: $uiAccentDim;
    --red: #E66558; --red-dim: rgba(230,101,88,0.12);
    --amber: #FF8F52; --amber-dim: rgba(255,143,82,0.12);
    --yellow: #EAD654; --yellow-dim: rgba(234,214,84,0.12);
    --text: #FFFFFF; --text-muted: #9E9E9E; --text-dim: #606060;
    --border: rgba(255,255,255,0.06);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--navy); color: var(--text); font-family: 'DM Sans', sans-serif; min-height: 100vh; }
  .header { background: var(--navy-light); border-bottom: 1px solid var(--border); padding: 14px 28px; display: flex; align-items: center; justify-content: space-between; }
  .header-left { display: flex; align-items: center; gap: 14px; }
  .logo { background: var(--ui-accent); border-radius: 8px; display: flex; align-items: center; justify-content: center; flex-shrink: 0; padding: 6px 12px; font-family: 'JetBrains Mono', monospace; font-size: 13px; font-weight: 700; color: #1A1A1A; letter-spacing: -0.02em; }
  .header-title { font-size: 15px; font-weight: 600; letter-spacing: -0.01em; }
  .header-subtitle { font-size: 12px; color: var(--text-muted); margin-top: 2px; }
  .header-right { display: flex; align-items: center; gap: 12px; }
  .mode-badge { font-size: 11px; font-weight: 500; padding: 4px 10px; border-radius: 99px; background: var(--ui-accent-dim); color: var(--ui-accent); }
  .generated { font-family: 'JetBrains Mono', monospace; font-size: 11px; color: var(--text-dim); }
  .main { padding: 24px 28px; max-width: 1400px; margin: 0 auto; }
  .stats { display: grid; grid-template-columns: repeat(4,1fr); gap: 10px; margin-bottom: 20px; }
  .stat { background: var(--navy-light); border: 1px solid var(--border); border-radius: 10px; padding: 16px 18px; position: relative; overflow: hidden; }
  .stat::before { content:''; position:absolute; top:0; left:0; right:0; height:2px; }
  .stat.total::before { background: var(--text-dim); }
  .stat.remaining::before { background: var(--red); }
  .stat.partial::before { background: var(--amber); }
  .stat.complete::before { background: var(--accent); }
  .stat-label { font-size: 10px; font-weight: 500; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.07em; margin-bottom: 8px; }
  .stat-number { font-family: 'JetBrains Mono', monospace; font-size: 34px; font-weight: 700; line-height: 1; margin-bottom: 5px; }
  .stat.total .stat-number { color: var(--text); }
  .stat.remaining .stat-number { color: var(--red); }
  .stat.partial .stat-number { color: var(--amber); }
  .stat.complete .stat-number { color: var(--accent); }
  .stat-sub { font-size: 11px; color: var(--text-dim); }
  .progress-wrap { background: var(--navy-light); border: 1px solid var(--border); border-radius: 10px; padding: 14px 18px; margin-bottom: 22px; }
  .progress-label { display: flex; justify-content: space-between; font-size: 12px; color: var(--text-muted); margin-bottom: 10px; }
  .progress-track { height: 7px; background: var(--navy-lighter); border-radius: 99px; overflow: hidden; display: flex; }
  .progress-complete { height: 100%; background: var(--accent); border-radius: 99px 0 0 99px; width: $pctComplete%; }
  .progress-partial { height: 100%; background: var(--amber); width: $pctPartial%; }
  .section { margin-bottom: 20px; }
  .section-header { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
  .section-title { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.07em; }
  .section-title.remaining { color: var(--red); }
  .section-title.partial { color: var(--amber); }
  .section-title.complete { color: var(--accent); }
  .section-count { font-family: 'JetBrains Mono', monospace; font-size: 10px; padding: 2px 8px; border-radius: 99px; font-weight: 600; }
  .section-count.remaining { background: var(--red-dim); color: var(--red); }
  .section-count.partial { background: var(--amber-dim); color: var(--amber); }
  .section-count.complete { background: var(--accent-dim); color: var(--accent); }
  .stat.coverage::before { background: var(--yellow); }
  .stat.coverage .stat-number { color: var(--yellow); }
  .section-title.coverage { color: var(--yellow); }
  .section-count.coverage { background: var(--yellow-dim); color: var(--yellow); }
  .table { background: var(--navy-light); border: 1px solid var(--border); border-radius: 10px; overflow: hidden; }
  .table-header { padding: 9px 18px; border-bottom: 1px solid var(--border); font-size: 10px; font-weight: 500; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.07em; display: grid; }
  .row { display: grid; padding: 12px 18px; border-bottom: 1px solid var(--border); align-items: center; }
  .row:last-child { border-bottom: none; }
  .row:hover { background: rgba(255,255,255,0.02); }
  .cell { display: flex; flex-direction: column; justify-content: center; }
  .name { font-size: 14px; font-weight: 500; }
  .email { font-size: 11px; color: var(--text-muted); margin-top: 2px; font-family: 'JetBrains Mono', monospace; }
  .badge { display: inline-flex; align-items: center; gap: 5px; font-size: 12px; font-weight: 500; padding: 3px 9px; border-radius: 6px; width: fit-content; }
  .badge.yes { background: var(--accent-dim); color: var(--accent); }
  .badge.no { background: var(--red-dim); color: var(--red); }
  .badge.warn { background: var(--amber-dim); color: var(--amber); }
  .pill { font-size: 11px; font-weight: 600; padding: 3px 10px; border-radius: 99px; display: inline-block; width: fit-content; }
  .pill.done { background: var(--accent-dim); color: var(--accent); }
  .pill.partial { background: var(--amber-dim); color: var(--amber); }
  .pill.none { background: var(--red-dim); color: var(--red); }
  .collapse-toggle { display: flex; align-items: center; gap: 10px; cursor: pointer; user-select: none; background: none; border: none; color: inherit; font-family: inherit; padding: 0; }
  .chevron { font-size: 10px; color: var(--text-dim); transition: transform 0.2s; display: inline-block; }
  .chevron.open { transform: rotate(90deg); }
  .collapse-body { display: none; }
  .collapse-body.open { display: block; }
  .empty { padding: 22px; text-align: center; font-size: 13px; color: var(--text-dim); }
  .footer { text-align: center; padding: 18px; font-size: 11px; color: var(--text-dim); font-family: 'JetBrains Mono', monospace; }
  .footer span { color: var(--ui-accent); }
  .table-header, .row { grid-template-columns: $gridCols; }
  .stat[data-filter] { cursor: pointer; transition: border-color 0.15s, box-shadow 0.15s; }
  .stat[data-filter]:hover { border-color: rgba(255,255,255,0.15); }
  .stat[data-filter].active.complete  { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent); }
  .stat[data-filter].active.partial   { border-color: var(--amber);  box-shadow: 0 0 0 1px var(--amber); }
  .stat[data-filter].active.remaining { border-color: var(--red);    box-shadow: 0 0 0 1px var(--red); }
  .filter-bar { display: flex; align-items: center; gap: 10px; font-size: 12px; color: var(--text-muted); margin-bottom: 16px; }
  .filter-bar strong { color: var(--text); }
  .filter-bar button { background: none; border: 1px solid var(--border); color: var(--text-muted); font-size: 11px; padding: 2px 8px; border-radius: 6px; cursor: pointer; font-family: inherit; }
  .filter-bar button:hover { border-color: rgba(255,255,255,0.2); color: var(--text); }
    .print-btn { background: none; border: 1px solid var(--border); color: var(--text-muted); font-size: 11px; padding: 4px 12px; border-radius: 6px; cursor: pointer; font-family: inherit; transition: border-color 0.15s, color 0.15s; }
  .print-btn:hover { border-color: rgba(255,255,255,0.2); color: var(--text); }
  @media print {
    :root { --navy: #ffffff; --navy-light: #f5f5f5; --navy-lighter: #ebebeb; --text: #1a1a1a; --text-muted: #555; --text-dim: #888; --border: rgba(0,0,0,0.1); }
    .print-btn, .filter-bar { display: none !important; }
    .stat[data-filter] { cursor: default; }
    .collapse-body { display: block !important; }
    .chevron { display: none; }
    .section { break-inside: avoid; }
    .row { break-inside: avoid; }
    .header { border-bottom: 1px solid #ddd; }
  }
</style>
</head>
<body>

<div class="header">
  <div class="header-left">
    $logoHtml
    <div>
      <div class="header-title">$headerTitle</div>
      <div class="header-subtitle">$headerSubtitle</div>
    </div>
  </div>
  <div class="header-right">
    <span class="mode-badge">$safeModeLabel</span>
    <div class="generated">Generated $generatedAt</div>
    <button class="print-btn" onclick="window.print()">Save as PDF</button>
  </div>
</div>

<div class="main">

  <div class="stats">
    $statCards
  </div>

  $mainSections

</div>

<div class="footer">
  Generated <span>$generatedAt</span> &middot; $footerText
</div>

<script>
  window.onbeforeprint = function() {
    document.querySelectorAll('.collapse-body').forEach(function(b) { b.classList.add('open'); });
    document.querySelectorAll('.row').forEach(function(r) { r.style.display = ''; });
  };

  function toggle() {
    document.getElementById('completedBody').classList.toggle('open');
    document.getElementById('chev').classList.toggle('open');
  }

  let activeFilter = null;
  const filterLabels = {
    auth: 'Microsoft Authenticator', whfb: 'WHfB', fido2: 'FIDO2', oath: 'Software OATH',
    sms: 'SMS', voice: 'Voice', email: 'Email OTP', none: 'No Methods'
  };

  function filterBy(method) {
    activeFilter = (activeFilter === method) ? null : method;
    applyFilter();
  }

  function applyFilter() {
    document.querySelectorAll('.row[data-auth]').forEach(row => {
      row.style.display = (!activeFilter || row.getAttribute('data-' + activeFilter) === '1') ? '' : 'none';
    });

    if (activeFilter) {
      const body = document.getElementById('completedBody');
      const chev = document.getElementById('chev');
      if (body) { body.classList.add('open'); chev.classList.add('open'); }
    }

    document.querySelectorAll('.stat[data-filter]').forEach(card => {
      card.classList.toggle('active', card.getAttribute('data-filter') === activeFilter);
    });

    document.querySelectorAll('.section').forEach(section => {
      const all = section.querySelectorAll('.row[data-auth]');
      const countEl = section.querySelector('.section-count');
      if (!countEl || all.length === 0) return;
      if (!countEl.dataset.original) countEl.dataset.original = countEl.textContent;
      countEl.textContent = activeFilter
        ? Array.from(all).filter(r => r.style.display !== 'none').length + ' / ' + countEl.dataset.original
        : countEl.dataset.original;
    });

    const bar = document.getElementById('filterBar');
    if (bar) {
      bar.style.display = activeFilter ? 'flex' : 'none';
      if (activeFilter) document.getElementById('filterLabel').textContent = filterLabels[activeFilter];
    }
  }
</script>
</body>
</html>
"@

# ── Write file ────────────────────────────────────────────────────────────────
try {
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -ErrorAction Stop
} catch {
    Write-Host "  ERROR: Could not write output file." -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

Write-Host "  Report saved to: $OutputPath" -ForegroundColor Cyan
Write-Host ""

if (-not $Demo) {
    try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}

    if (Get-MgContext) {
        Write-Host "  WARNING: Could not disconnect from Microsoft Graph. Run Disconnect-MgGraph manually." -ForegroundColor Yellow
    } else {
        Write-Host "  Disconnected from Microsoft Graph." -ForegroundColor DarkGray
    }
}

Write-Host "  Done." -ForegroundColor Green
Write-Host ""
