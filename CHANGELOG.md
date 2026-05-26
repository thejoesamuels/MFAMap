# Changelog

---

## [Unreleased]

### New features

- **Mode 5 — Full Method Audit**: new tracking mode covering all seven authentication methods (Microsoft Authenticator, WHfB, FIDO2, Software OATH, SMS, Voice, Email OTP). Users are grouped into Modern Methods, Legacy Only, and No Methods sections. Method count banner shows per-method totals.
- **Method filtering (Mode 5)**: stat cards in Mode 5 act as interactive filter buttons. Clicking a card filters the table to users who have that method registered; clicking again clears the filter. Section counts update dynamically to show filtered / total.
- **Native save dialog**: a file save dialog appears automatically when the script runs — pre-populated with the suggested filename. Uses `System.Windows.Forms.SaveFileDialog` on Windows and `osascript choose file name` on macOS. Falls back to auto-naming in the current directory if unavailable. Providing `-OutputPath` skips the dialog entirely.
- **Software OATH / TOTP support**: users registered with a software OATH token (TOTP) are counted as having Authenticator in modes 1 and 3, with an amber "TOTP only" badge in mode 3 to distinguish them from full Authenticator registrations.

### Improvements

- **Semantic colour scheme**: data states now use consistent functional colours across all modes — green (`#57BD84`) for registered/complete, orange (`#FF8F52`) for partial/legacy, red (`#E66558`) for not registered, yellow (`#EAD654`) for coverage. Mode 5 modern methods use blue (`#659AD2`).
- **UI chrome colour**: logo badge, mode badge, and footer accent use gold (`#F5CF18`) consistently across all modes, independent of per-mode data colours.
- **Dark grey background**: background switched from navy/purple to neutral dark grey (`#1A1A1A` / `#242424`), giving a cleaner two-tone look.
- **Text colours**: main text updated to pure white (`#FFFFFF`); subtext to neutral grey (`#9E9E9E`); dim text to `#606060`. Removes the purple tint from the previous palette.
- **Header logo**: replaced the emoji icon with a "MFAMap" text badge.
- **Coverage stat card**: split from the `partial` CSS class into its own `coverage` class so it always renders yellow, separate from the orange partial/legacy state.
- **All sections open by default**: completed/registered sections no longer start collapsed when a report is first opened.

### Fixes

- **Authenticator false negatives**: `softwareOathMethods` fallback added — users with a TOTP token but no push Authenticator were previously missed in modes 1 and 3.
- **Auto-disconnect**: script now always disconnects from Microsoft Graph on completion and verifies the session was cleared.
- **Reconnect on each run**: script re-authenticates fresh on every invocation rather than reusing a stale session.

### Developer tooling

- `testing/Create-MFAMapTestUsers.ps1`: script to provision the ten test users and group defined in `TESTING.md` against a dev tenant. Includes policy checks for SMS, Voice, Email OTP, and Software OATH — skips methods disabled in the tenant's Authentication Methods Policy and lists them as manual steps.
- `testing/README.md`: documents the setup script, its prerequisites, configuration variables, and re-run / cleanup behaviour.
- `TESTING.md`: comprehensive test plan covering all five modes, edge cases, and a pre-merge checklist.

---

## Earlier history

The following changes were made prior to formal changelog tracking.

- Renamed from **EnrolWatch** to **MFAMap**
- Added `CLAUDE.md` codebase guidance
- Added `.gitignore` to exclude generated report files and Claude project files
- Fixed Windows PowerShell 5.1 encoding (UTF-8 BOM)
- Fixed false negatives for Authenticator App registration
- Verified disconnect from Microsoft Graph after each run
- Added documentation for auto-disconnect and `softwareOathMethods` fix
