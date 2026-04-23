# ============================================================================
# EnrolWatch-Authenticator.ps1
# Microsoft Authenticator enrolment tracker for Microsoft Entra ID
# Generates a self-contained HTML dashboard from a target Entra group
#
# Usage:
#   .\EnrolWatch.ps1 -GroupId "your-group-object-id"
#   .\EnrolWatch.ps1 -GroupId "your-group-object-id" -OutputPath "C:\Reports\report.html"
#
# Requirements:
#   Install-Module Microsoft.Graph -Scope CurrentUser
#
# Only Microsoft.Graph.Authentication and Microsoft.Graph.Groups are loaded
# at runtime. All other Graph calls use Invoke-MgGraphRequest directly.
# ============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$GroupId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ""
)

# ── Load System.Web for HtmlEncode (must be before any function calls) ────────
Add-Type -AssemblyName System.Web

# ── Explicitly import required modules ───────────────────────────────────────
# Only Authentication and Groups needed — all other calls use Invoke-MgGraphRequest directly
Get-Module Microsoft.Graph.Authentication -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1 | Import-Module -Force
Get-Module Microsoft.Graph.Groups -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1 | Import-Module -Force

# ── Connect to Graph ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  EnrolWatch" -ForegroundColor Cyan
Write-Host "  MFA Enrolment Tracker" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Connecting to Microsoft Graph..." -ForegroundColor DarkGray

try {
    Connect-MgGraph -Scopes "GroupMember.Read.All", "UserAuthenticationMethod.Read.All", "User.Read.All", "Group.Read.All", "Organization.Read.All" -NoWelcome -ErrorAction Stop
} catch {
    Write-Host "  ERROR: Failed to connect to Microsoft Graph." -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    exit 1
}

Write-Host "  Connected." -ForegroundColor Green
Write-Host ""

# ── Get tenant name ───────────────────────────────────────────────────────────
Write-Host "  Fetching tenant details..." -ForegroundColor DarkGray

try {
    # Use Invoke-MgGraphRequest to avoid needing the DirectoryManagement module
    $orgResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization?`$select=displayName" -ErrorAction Stop
    $tenantName = $orgResponse.value[0].displayName
    if ([string]::IsNullOrEmpty($tenantName)) {
        Write-Host "  WARNING: Tenant name was empty." -ForegroundColor Yellow
        $tenantName = ""
    } else {
        Write-Host "  Tenant: $tenantName" -ForegroundColor Green
    }
} catch {
    Write-Host "  WARNING: Could not retrieve tenant name: $_" -ForegroundColor Yellow
    $tenantName = ""
}

# ── Get group name ────────────────────────────────────────────────────────────
Write-Host "  Fetching group details..." -ForegroundColor DarkGray

try {
    $group = Get-MgGroup -GroupId $GroupId -Property DisplayName -ErrorAction Stop
    $groupName = $group.DisplayName
    Write-Host "  Group: $groupName" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Could not retrieve group name." -ForegroundColor Yellow
    $groupName = $GroupId
}

# ── Build output path from group name + timestamp if not specified ────────────
if ($OutputPath -eq "") {
    $safeName  = $groupName -replace '[^\w\s-]', '' -replace '\s+', '-'
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $OutputPath = ".\enrolwatch_${safeName}_${timestamp}.html"
}

Write-Host ""

# ── Get group members ─────────────────────────────────────────────────────────
Write-Host "  Fetching group members..." -ForegroundColor DarkGray

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
            # Not a user object (e.g. nested group or device) — skip silently
        }
    }

    $members = @($members | Where-Object { $_ -ne $null })
} catch {
    Write-Host "  ERROR: Could not retrieve group members. Check the Group ID is correct." -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red
    Disconnect-MgGraph | Out-Null
    exit 1
}

$totalCount = ($members | Measure-Object).Count

if ($totalCount -eq 0) {
    Write-Host "  ERROR: No users found in this group. Check the Group ID." -ForegroundColor Red
    Disconnect-MgGraph | Out-Null
    exit 1
}

Write-Host "  Found $totalCount members." -ForegroundColor Green
Write-Host ""

# ── Get auth methods for each user ───────────────────────────────────────────
Write-Host "  Checking authentication methods..." -ForegroundColor DarkGray

$users = @()
$i = 0

foreach ($member in $members) {
    $i++
    Write-Progress -Activity "EnrolWatch" -Status "Checking $($member.DisplayName) ($i of $totalCount)" -PercentComplete (($i / $totalCount) * 100)

    try {
        $hasAuthenticator = $false
        $hasWHfB          = $false

        try {
            $authResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($member.Id)/authentication/microsoftAuthenticatorMethods" -ErrorAction Stop
            $hasAuthenticator = $authResponse.value.Count -gt 0
        } catch {}

        $users += [PSCustomObject]@{
            Name             = $member.DisplayName
            Email            = $member.UserPrincipalName
            HasAuthenticator = $hasAuthenticator
        }
    } catch {
        Write-Host "  WARNING: Could not get methods for $($member.DisplayName)" -ForegroundColor Yellow
        $users += [PSCustomObject]@{
            Name             = $member.DisplayName
            Email            = $member.UserPrincipalName
            HasAuthenticator = $false
        }
    }
}

Write-Progress -Activity "EnrolWatch" -Completed

# ── Categorise ────────────────────────────────────────────────────────────────
$notStarted = @($users | Where-Object { -not $_.HasAuthenticator })
$partial    = @()
$complete   = @($users | Where-Object { $_.HasAuthenticator })

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
Write-Host "    Partial:      $partialCount"    -ForegroundColor Yellow
Write-Host "    Complete:     $completeCount"   -ForegroundColor Green
Write-Host ""

# ── HTML helpers ──────────────────────────────────────────────────────────────
function Get-Badge([bool]$registered) {
    if ($registered) {
        return '<span class="badge yes">&#10003; Registered</span>'
    } else {
        return '<span class="badge no">&#10005; Not registered</span>'
    }
}

function Get-Rows($userList, [string]$statusType) {
    if ($userList.Count -eq 0) {
        $msg = switch ($statusType) {
            "none"    { "Everyone has registered Authenticator &#127881;" }
            "partial" { "No partial enrolments" }
            "done"    { "No completed enrolments yet" }
        }
        return "<div class=`"empty`">$msg</div>"
    }

    $rows = ""
    foreach ($u in $userList) {
        $authBadge = Get-Badge $u.HasAuthenticator
        $pill = switch ($statusType) {
            "done"    { '<span class="pill done">Registered</span>' }
            "none"    { '<span class="pill none">Not registered</span>' }
        }
        $safeName  = [System.Web.HttpUtility]::HtmlEncode($u.Name)
        $safeEmail = [System.Web.HttpUtility]::HtmlEncode($u.Email)
        $rows += @"
        <div class="row">
          <div class="cell"><span class="name">$safeName</span><span class="email">$safeEmail</span></div>
          <div class="cell">$authBadge</div>
          <div class="cell">$pill</div>
        </div>
"@
    }
    return $rows
}

$rowsNotStarted = Get-Rows $notStarted "none"
$rowsPartial    = Get-Rows $partial    "partial"
$rowsComplete   = Get-Rows $complete   "done"

$safeGroupName  = [System.Web.HttpUtility]::HtmlEncode($groupName)
$safeTenantName = [System.Web.HttpUtility]::HtmlEncode($tenantName)
$generatedAt   = Get-Date -Format "dd MMM yyyy 'at' HH:mm"

# ── Build HTML ────────────────────────────────────────────────────────────────
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>EnrolWatch Authenticator &mdash; $safeGroupName</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600;700&family=DM+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
<style>
  :root {
    --navy:         #252436;
    --navy-light:   #2f2d47;
    --navy-lighter: #3a3756;
    --teal:         #43C0B9;
    --teal-dim:     rgba(67,192,185,0.15);
    --red:          #e05c6a;
    --red-dim:      rgba(224,92,106,0.12);
    --amber:        #f0a843;
    --amber-dim:    rgba(240,168,67,0.12);
    --text:         #e8e6f0;
    --text-muted:   #8b89a0;
    --text-dim:     #5a5870;
    --border:       rgba(255,255,255,0.06);
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    background: var(--navy);
    color: var(--text);
    font-family: 'DM Sans', sans-serif;
    min-height: 100vh;
  }

  .header {
    background: var(--navy-light);
    border-bottom: 1px solid var(--border);
    padding: 14px 28px;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .header-left { display: flex; align-items: center; gap: 14px; }

  .logo {
    width: 34px; height: 34px;
    background: var(--teal);
    border-radius: 8px;
    display: flex; align-items: center; justify-content: center;
    font-size: 18px;
    flex-shrink: 0;
  }

  .header-title { font-size: 15px; font-weight: 600; letter-spacing: -0.01em; }
  .header-subtitle { font-size: 12px; color: var(--text-muted); margin-top: 2px; }

  .generated {
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
    color: var(--text-dim);
  }

  .main { padding: 24px 28px; max-width: 1400px; margin: 0 auto; }

  .stats { display: grid; grid-template-columns: repeat(4,1fr); gap: 10px; margin-bottom: 20px; }

  .stat {
    background: var(--navy-light);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 16px 18px;
    position: relative; overflow: hidden;
  }

  .stat::before { content:''; position:absolute; top:0; left:0; right:0; height:2px; }
  .stat.total::before     { background: var(--text-dim); }
  .stat.remaining::before { background: var(--red); }
  .stat.partial::before   { background: var(--amber); }
  .stat.complete::before  { background: var(--teal); }

  .stat-label {
    font-size: 10px; font-weight: 500;
    color: var(--text-muted);
    text-transform: uppercase; letter-spacing: 0.07em;
    margin-bottom: 8px;
  }

  .stat-number {
    font-family: 'JetBrains Mono', monospace;
    font-size: 34px; font-weight: 700; line-height: 1; margin-bottom: 5px;
  }

  .stat.total     .stat-number { color: var(--text); }
  .stat.remaining .stat-number { color: var(--red); }
  .stat.partial   .stat-number { color: var(--amber); }
  .stat.complete  .stat-number { color: var(--teal); }
  .stat-sub { font-size: 11px; color: var(--text-dim); }

  .progress-wrap {
    background: var(--navy-light);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 14px 18px; margin-bottom: 22px;
  }

  .progress-label {
    display: flex; justify-content: space-between;
    font-size: 12px; color: var(--text-muted); margin-bottom: 10px;
  }

  .progress-label span.c { color: var(--teal); }
  .progress-label span.p { color: var(--amber); }
  .progress-label span.r { color: var(--red); }

  .progress-track {
    height: 7px; background: var(--navy-lighter);
    border-radius: 99px; overflow: hidden; display: flex;
  }

  .progress-complete {
    height: 100%; background: var(--teal);
    border-radius: 99px 0 0 99px;
    width: $pctComplete%;
  }

  .progress-partial {
    height: 100%; background: var(--amber);
    width: $pctPartial%;
  }

  .section { margin-bottom: 20px; }
  .section-header { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }

  .section-title {
    font-size: 12px; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.07em;
  }

  .section-title.remaining { color: var(--red); }
  .section-title.partial   { color: var(--amber); }
  .section-title.complete  { color: var(--teal); }

  .section-count {
    font-family: 'JetBrains Mono', monospace;
    font-size: 10px; padding: 2px 8px;
    border-radius: 99px; font-weight: 600;
  }

  .section-count.remaining { background: var(--red-dim);   color: var(--red); }
  .section-count.partial   { background: var(--amber-dim); color: var(--amber); }
  .section-count.complete  { background: var(--teal-dim);  color: var(--teal); }

  .table {
    background: var(--navy-light);
    border: 1px solid var(--border);
    border-radius: 10px; overflow: hidden;
  }

  .table-header {
    display: grid;
    grid-template-columns: 1fr 170px 110px;
    padding: 9px 18px;
    border-bottom: 1px solid var(--border);
    font-size: 10px; font-weight: 500;
    color: var(--text-dim);
    text-transform: uppercase; letter-spacing: 0.07em;
  }

  .row {
    display: grid;
    grid-template-columns: 1fr 170px 110px;
    padding: 12px 18px;
    border-bottom: 1px solid var(--border);
    align-items: center;
  }

  .row:last-child { border-bottom: none; }
  .row:hover { background: rgba(255,255,255,0.02); }

  .cell { display: flex; flex-direction: column; justify-content: center; }

  .name  { font-size: 14px; font-weight: 500; }
  .email { font-size: 11px; color: var(--text-muted); margin-top: 2px; font-family: 'JetBrains Mono', monospace; }

  .badge {
    display: inline-flex; align-items: center; gap: 5px;
    font-size: 12px; font-weight: 500;
    padding: 3px 9px; border-radius: 6px;
    width: fit-content;
  }

  .badge.yes { background: var(--teal-dim); color: var(--teal); }
  .badge.no  { background: var(--red-dim);  color: var(--red); }

  .pill {
    font-size: 11px; font-weight: 600;
    padding: 3px 10px; border-radius: 99px;
    display: inline-block; width: fit-content;
  }

  .pill.done    { background: var(--teal-dim);  color: var(--teal); }
  .pill.partial { background: var(--amber-dim); color: var(--amber); }
  .pill.none    { background: var(--red-dim);   color: var(--red); }

  .collapse-toggle {
    display: flex; align-items: center; gap: 10px;
    cursor: pointer; user-select: none;
    background: none; border: none; color: inherit;
    font-family: inherit; padding: 0;
  }

  .chevron { font-size: 10px; color: var(--text-dim); transition: transform 0.2s; display: inline-block; }
  .chevron.open { transform: rotate(90deg); }
  .collapse-body { display: none; }
  .collapse-body.open { display: block; }

  .empty {
    padding: 22px; text-align: center;
    font-size: 13px; color: var(--text-dim);
  }

  .footer {
    text-align: center; padding: 18px;
    font-size: 11px; color: var(--text-dim);
    font-family: 'JetBrains Mono', monospace;
  }

  .footer span { color: var(--teal); }
</style>
</head>
<body>

<div class="header">
  <div class="header-left">
    <div class="logo">&#9889;</div>
    <div>
      <div class="header-title">MFA Enrolment Tracker</div>
      <div class="header-subtitle">$(if ($tenantName) { "$safeTenantName &middot; " })$safeGroupName</div>
    </div>
  </div>
  <div class="generated">Generated $generatedAt</div>
</div>

<div class="main">

  <div class="stats">
    <div class="stat total">
      <div class="stat-label">Total Users</div>
      <div class="stat-number">$totalUsers</div>
      <div class="stat-sub">in target group</div>
    </div>
    <div class="stat remaining">
      <div class="stat-label">Not Started</div>
      <div class="stat-number">$notStartedCount</div>
      <div class="stat-sub">still to catch</div>
    </div>
    <div class="stat complete">
      <div class="stat-label">Registered</div>
      <div class="stat-number">$completeCount</div>
      <div class="stat-sub">authenticator registered</div>
    </div>
    <div class="stat partial">
      <div class="stat-label">Coverage</div>
      <div class="stat-number">$pctComplete%</div>
      <div class="stat-sub">of group enrolled</div>
    </div>
  </div>

  <div class="progress-wrap">
    <div class="progress-label">
      <span>Authenticator Enrolment Progress</span>
      <span><span class="c">$completeCount complete</span> &middot; <span class="p">$partialCount partial</span> &middot; <span class="r">$notStartedCount remaining</span></span>
    </div>
    <div class="progress-track">
      <div class="progress-complete"></div>
      <div class="progress-partial"></div>
    </div>
  </div>

  <div class="section">
    <div class="section-header">
      <span class="section-title remaining">Still to Catch</span>
      <span class="section-count remaining">$notStartedCount</span>
    </div>
    <div class="table">
      <div class="table-header">
        <div>User</div><div>Authenticator App</div><div>Status</div>
      </div>
      $rowsNotStarted
    </div>
  </div>

  <div class="section">
    <div class="section-header">
      <span class="section-title partial">Partially Enrolled</span>
      <span class="section-count partial">$partialCount</span>
    </div>
    <div class="table">
      <div class="table-header">
        <div>User</div><div>Authenticator App</div><div>Status</div>
      </div>
      $rowsPartial
    </div>
  </div>

  <div class="section">
    <div class="section-header">
      <button class="collapse-toggle" onclick="toggle()">
        <span class="section-title complete">Registered</span>
        <span class="section-count complete">$completeCount</span>
        <span class="chevron" id="chev">&#9658;</span>
      </button>
    </div>
    <div class="collapse-body" id="completedBody">
      <div class="table">
        <div class="table-header">
          <div>User</div><div>Authenticator App</div><div>Status</div>
        </div>
        $rowsComplete
      </div>
    </div>
  </div>

</div>

<div class="footer">
  Generated <span>$generatedAt</span> &middot; vibecoded by JS ⚡️
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
    Disconnect-MgGraph | Out-Null
    exit 1
}

Write-Host "  Report saved to: $OutputPath" -ForegroundColor Cyan
Write-Host ""

Disconnect-MgGraph | Out-Null
Write-Host "  Done." -ForegroundColor Green
Write-Host ""
