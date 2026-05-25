# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MFAMap is a single-file PowerShell script (`code/MFAMap.ps1`) that maps and audits authentication method registration across a target Entra group via Microsoft Graph and generates a self-contained HTML report. No build system, no tests, no package manager.

## Running the script

```powershell
# Basic run — prompts for mode, auto-names output file
.\code\MFAMap.ps1 -GroupId "your-group-object-id"

# Custom output path
.\code\MFAMap.ps1 -GroupId "your-group-object-id" -OutputPath "C:\Reports\report.html"

# If execution policy blocks it
PowerShell -ExecutionPolicy Bypass -File .\code\MFAMap.ps1 -GroupId "your-group-object-id"
```

One-time dependency install:
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

## Script architecture

The script runs linearly in a single file with no functions extracted for reuse except HTML-generation helpers at the bottom. The flow is:

1. **Mode selection** — interactive prompt, sets `$mode` (1–4), `$modeLabel`, `$modeShort`
2. **Connect** — `Connect-MgGraph` with delegated permissions; only `Microsoft.Graph.Authentication` and `Microsoft.Graph.Groups` are imported (avoids version conflicts — all other calls use `Invoke-MgGraphRequest` directly)
3. **Data fetching** — tenant name, group name, group members (resolved to UPN via individual user calls), then per-user auth method queries
4. **Categorisation** — users bucketed into `$notStarted`, `$partial` (mode 1 only), `$complete`
5. **HTML generation** — a PowerShell heredoc builds the full HTML with inline CSS, mode-specific accent colours, and a small JS collapse toggle
6. **Disconnect** — `Disconnect-MgGraph` called automatically; verifies disconnection

## Key implementation details

**Auth method detection logic:**
- Authenticator (modes 1, 3): checks `/authentication/microsoftAuthenticatorMethods` first; if empty, falls back to `/authentication/softwareOathMethods` (covers TOTP/OATH tokens as a registered MFA method)
- WHfB (modes 1, 2): `/authentication/windowsHelloForBusinessMethods`
- Passkey (mode 4): checks `authenticationMode == 'deviceBoundPushNotification'` on authenticator methods AND `/authentication/fido2Methods`
- Mode 1 "Partially Enrolled" = has one of Authenticator or WHfB but not both

**HTML output** is fully self-contained — inline CSS with CSS custom properties for theming, no external assets except Google Fonts CDN (font request only, no user data sent). The output file contains real user names and email addresses so treat it as internal data.

**Module strategy**: only the two required submodules are imported at runtime. All Graph API calls beyond auth and group membership go through `Invoke-MgGraphRequest` rather than Graph SDK cmdlets to avoid module version conflict issues.
