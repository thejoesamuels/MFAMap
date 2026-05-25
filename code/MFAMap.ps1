# ============================================================================
# MFAMap.ps1
# Authentication method mapper for Microsoft Entra ID
#
# Modes:
#   1 — Microsoft Authenticator + Windows Hello for Business
#   2 — Windows Hello for Business only
#   3 — Microsoft Authenticator only
#   4 — Passkey (FIDO2 or Authenticator device-bound passkey)
#
# Usage:
#   .\MFAMap.ps1 -GroupId "your-group-object-id"
#   .\MFAMap.ps1 -GroupId "your-group-object-id" -OutputPath "C:\Reports\report.html"
#
# Requirements:
#   Install-Module Microsoft.Graph -Scope CurrentUser -Force
# ============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$GroupId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ""
)

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
Write-Host ""

do { $modeInput = Read-Host "  Enter choice (1-4)" } while ($modeInput -notin @('1','2','3','4'))
$mode = [int]$modeInput

$modeLabel = switch ($mode) {
    1 { "Authenticator + WHfB" }
    2 { "Windows Hello for Business" }
    3 { "Microsoft Authenticator" }
    4 { "Passkey" }
}
$modeShort = switch ($mode) {
    1 { "Mode1-Auth-WHfB" }
    2 { "Mode2-WHfB" }
    3 { "Mode3-Auth" }
    4 { "Mode4-Passkey" }
}

Write-Host ""
Write-Host "  Mode: $modeLabel" -ForegroundColor Cyan
Write-Host ""

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

# ── Output filename ───────────────────────────────────────────────────────────
if ($OutputPath -eq "") {
    $safeName  = $groupName -replace '[^\w\s-]', '' -replace '\s+', '-'
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $OutputPath = ".\mfamap_${safeName}_${modeShort}_${timestamp}.html"
}
Write-Host ""

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
                if (@($oathResp.value).Count -gt 0) { $hasAuthenticator = $true }
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
        }
    }
}

Write-Progress -Activity "MFAMap" -Completed

if ($errorUsers.Count -gt 0) {
    Write-Host ""
    Write-Host "  WARNING: Could not retrieve auth methods for $($errorUsers.Count) user(s) — excluded from report:" -ForegroundColor Yellow
    $errorUsers | ForEach-Object { Write-Host "    - $($_.Name) ($($_.Email))" -ForegroundColor Yellow }
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
}

$totalUsers      = $users.Count
$notStartedCount = $notStarted.Count
$partialCount    = $partial.Count
$completeCount   = $complete.Count

$pctComplete = if ($totalUsers -gt 0) { [math]::Round(($completeCount / $totalUsers) * 100, 1) } else { 0 }
$pctPartial  = if ($totalUsers -gt 0) { [math]::Round(($partialCount  / $totalUsers) * 100, 1) } else { 0 }

Write-Host ""
Write-Host "  Results:" -ForegroundColor Cyan
Write-Host "    Total:        $totalUsers"      -ForegroundColor White
Write-Host "    Not started:  $notStartedCount" -ForegroundColor Red
if ($partialCount -gt 0) { Write-Host "    Partial:      $partialCount" -ForegroundColor Yellow }
Write-Host "    Complete:     $completeCount"   -ForegroundColor Green
Write-Host ""

# ── Mode-specific accent colour ───────────────────────────────────────────────
$accentColor = switch ($mode) {
    1 { "#43C0B9" }  # teal
    2 { "#7b6ff0" }  # purple
    3 { "#43C0B9" }  # teal
    4 { "#f0a843" }  # amber
}
$accentDim = switch ($mode) {
    1 { "rgba(67,192,185,0.15)" }
    2 { "rgba(123,111,240,0.15)" }
    3 { "rgba(67,192,185,0.15)" }
    4 { "rgba(240,168,67,0.15)" }
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
        3 { return "<div>$(Get-Badge $u.HasAuthenticator)</div>" }
        4 { return "<div>$(Get-Badge $u.HasPasskey)</div>" }
    }
}

function Get-TableHeader([int]$m) {
    switch ($m) {
        1 { return "<div>User</div><div>Authenticator App</div><div>Windows Hello</div><div>Status</div>" }
        2 { return "<div>User</div><div>Windows Hello</div><div>Status</div>" }
        3 { return "<div>User</div><div>Authenticator App</div><div>Status</div>" }
        4 { return "<div>User</div><div>Passkey</div><div>Status</div>" }
    }
}

function Get-GridCols([int]$m) {
    if ($m -eq 1) { return "1fr 170px 170px 110px" }
    else          { return "1fr 200px 110px" }
}

function Get-Rows($userList, [string]$statusType, [int]$m) {
    if ($userList.Count -eq 0) {
        $msg = switch ($statusType) {
            "none"    { "Everyone has started enrolment &#127881;" }
            "partial" { "No partial enrolments" }
            "done"    { "No completed enrolments yet" }
        }
        return "<div class=`"empty`">$msg</div>"
    }
    $rows = ""
    foreach ($u in $userList) {
        $methodCells = Get-MethodCells $u $m
        $pill = switch ($statusType) {
            "done"    { if ($m -eq 1) { '<span class="pill done">Complete</span>' } else { '<span class="pill done">Registered</span>' } }
            "partial" { '<span class="pill partial">Partial</span>' }
            "none"    { if ($m -eq 1) { '<span class="pill none">Not started</span>' } else { '<span class="pill none">Not registered</span>' } }
        }
        $safeName  = [System.Web.HttpUtility]::HtmlEncode($u.Name)
        $safeEmail = [System.Web.HttpUtility]::HtmlEncode($u.Email)
        $rows += @"
        <div class="row">
          <div class="cell"><span class="name">$safeName</span><span class="email">$safeEmail</span></div>
          $methodCells
          <div>$pill</div>
        </div>
"@
    }
    return $rows
}

$gridCols       = Get-GridCols $mode
$tableHeaderHtml = Get-TableHeader $mode
$rowsNotStarted  = Get-Rows $notStarted "none"    $mode
$rowsPartial     = Get-Rows $partial    "partial" $mode
$rowsComplete    = Get-Rows $complete   "done"    $mode

$safeGroupName  = [System.Web.HttpUtility]::HtmlEncode($groupName)
$safeTenantName = [System.Web.HttpUtility]::HtmlEncode($tenantName)
$safeModeLabel  = [System.Web.HttpUtility]::HtmlEncode($modeLabel)
$generatedAt    = Get-Date -Format "dd MMM yyyy 'at' HH:mm"

$headerSubtitle = if ($tenantName) { "$safeTenantName &middot; $safeGroupName" } else { $safeGroupName }

# ── Stat cards ────────────────────────────────────────────────────────────────
if ($mode -eq 1) {
    $statCards = @"
    <div class="stat total"><div class="stat-label">Total Users</div><div class="stat-number">$totalUsers</div><div class="stat-sub">in target group</div></div>
    <div class="stat remaining"><div class="stat-label">Not Started</div><div class="stat-number">$notStartedCount</div><div class="stat-sub">still to catch</div></div>
    <div class="stat partial"><div class="stat-label">Partial</div><div class="stat-number">$partialCount</div><div class="stat-sub">one method only</div></div>
    <div class="stat complete"><div class="stat-label">Fully Enrolled</div><div class="stat-number">$completeCount</div><div class="stat-sub">authenticator + WHfB</div></div>
"@
} else {
    $statCards = @"
    <div class="stat total"><div class="stat-label">Total Users</div><div class="stat-number">$totalUsers</div><div class="stat-sub">in target group</div></div>
    <div class="stat remaining"><div class="stat-label">Not Registered</div><div class="stat-number">$notStartedCount</div><div class="stat-sub">still to catch</div></div>
    <div class="stat complete"><div class="stat-label">Registered</div><div class="stat-number">$completeCount</div><div class="stat-sub">$safeModeLabel</div></div>
    <div class="stat partial"><div class="stat-label">Coverage</div><div class="stat-number">$pctComplete%</div><div class="stat-sub">of group enrolled</div></div>
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

$progressPartialDiv = if ($mode -eq 1) { '<div class="progress-partial"></div>' } else { "" }
$progressPartialLabel = if ($mode -eq 1) { " &middot; <span style=`"color:var(--amber)`">$partialCount partial</span>" } else { "" }
$completedLabel = if ($mode -eq 1) { "Fully Enrolled" } else { "Registered" }

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

# ── Build HTML ────────────────────────────────────────────────────────────────
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>MFAMap &mdash; $safeGroupName</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=DM+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
  :root {
    --navy: #252436; --navy-light: #2f2d47; --navy-lighter: #3a3756;
    --accent: $accentColor; --accent-dim: $accentDim;
    --red: #e05c6a; --red-dim: rgba(224,92,106,0.12);
    --amber: #f0a843; --amber-dim: rgba(240,168,67,0.12);
    --text: #e8e6f0; --text-muted: #8b89a0; --text-dim: #5a5870;
    --border: rgba(255,255,255,0.06);
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--navy); color: var(--text); font-family: 'DM Sans', sans-serif; min-height: 100vh; }
  .header { background: var(--navy-light); border-bottom: 1px solid var(--border); padding: 14px 28px; display: flex; align-items: center; justify-content: space-between; }
  .header-left { display: flex; align-items: center; gap: 14px; }
  .logo { width: 34px; height: 34px; background: var(--accent); border-radius: 8px; display: flex; align-items: center; justify-content: center; font-size: 18px; flex-shrink: 0; }
  .header-title { font-size: 15px; font-weight: 600; letter-spacing: -0.01em; }
  .header-subtitle { font-size: 12px; color: var(--text-muted); margin-top: 2px; }
  .header-right { display: flex; align-items: center; gap: 12px; }
  .mode-badge { font-size: 11px; font-weight: 500; padding: 4px 10px; border-radius: 99px; background: var(--accent-dim); color: var(--accent); }
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
  .footer span { color: var(--accent); }
  .table-header, .row { grid-template-columns: $gridCols; }
</style>
</head>
<body>

<div class="header">
  <div class="header-left">
    <div class="logo">&#9889;</div>
    <div>
      <div class="header-title">Authentication Method Map</div>
      <div class="header-subtitle">$headerSubtitle</div>
    </div>
  </div>
  <div class="header-right">
    <span class="mode-badge">$safeModeLabel</span>
    <div class="generated">Generated $generatedAt</div>
  </div>
</div>

<div class="main">

  <div class="stats">
    $statCards
  </div>

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
      <span class="section-title remaining">Still to Catch</span>
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
        <span class="chevron" id="chev">&#9658;</span>
      </button>
    </div>
    <div class="collapse-body" id="completedBody">
      <div class="table">
        <div class="table-header">$tableHeaderHtml</div>
        $rowsComplete
      </div>
    </div>
  </div>

</div>

<div class="footer">
  Generated <span>$generatedAt</span> &middot; vibecoded by JS &#9889;
</div>

<script>
  function toggle() {
    document.getElementById('completedBody').classList.toggle('open');
    document.getElementById('chev').classList.toggle('open');
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

try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}

if (Get-MgContext) {
    Write-Host "  WARNING: Could not disconnect from Microsoft Graph. Run Disconnect-MgGraph manually." -ForegroundColor Yellow
} else {
    Write-Host "  Disconnected from Microsoft Graph." -ForegroundColor DarkGray
}

Write-Host "  Done." -ForegroundColor Green
Write-Host ""
