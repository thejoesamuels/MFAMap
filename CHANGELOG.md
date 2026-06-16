# Changelog

---

## [2.2.1] — 2026-06-16

### Fixes

**Splash screen** — the terminal now displays an ASCII art MFAMap header on startup, replacing the plain single-line version. Makes it immediately clear which script you're running and which version.

**PDF print alignment (Mode 5)** — method columns in Full Method Audit reports now line up correctly with their headers when printing to PDF. Long email addresses that previously bled into the adjacent column are now clipped cleanly. Page breaks no longer orphan section headers from their tables.

---

## [2.2.0] — 2026-06-15

### New features

**Delta reports** — running the script against a group that was previously audited now automatically generates a second report showing what changed. Who enrolled, who dis-enrolled, who changed methods — all compared against the last snapshot. No extra flags needed; snapshots are saved alongside the HTML report and discovered automatically by naming convention.

### Fixes

**Windows save dialog** — fixed the dialog not appearing when running under PowerShell 5.1 (`powershell.exe`), where `$IsWindows` is undefined and the dialog block was silently skipped. The dialog now renders on top of other windows so it can't be hidden behind the terminal, and errors from the dialog runspace are surfaced rather than swallowed.

---

## [2.1.0] — 2026-06-09

### New features

**PDF export** — every report now includes a "Save as PDF" button in the header. Clicking it opens the browser print dialog pre-configured for PDF output. The dark theme is preserved exactly as it appears on screen. All collapsed sections expand automatically before the dialog opens, and any active filters are cleared so the full dataset is captured.

**Demo mode** — a new `-Demo` switch runs the script without connecting to Microsoft Graph, using a set of 20 synthetic users instead. Covers every display path across all five modes: complete, partial, TOTP-only, passkey, legacy-only, and no methods. Useful for previewing layouts, testing, or showing the tool to someone without needing a live tenant.

**`-Mode` parameter** — pass `-Mode 1` through `-Mode 5` to skip the interactive mode prompt entirely. Works in both normal and demo mode, useful for scripted or unattended runs.

---

## [2.0.0] — 2026-05-26

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
