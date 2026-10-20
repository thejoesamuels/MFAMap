# MFAMap one-page infographic: Claude Design prompt

Paste everything below the line into Claude Design to make a one-page "getting started" infographic for MFAMap. It's written for MFAMap v2.6.1. If the flags or steps change, update this prompt in the same PR.

---

Make a one-page infographic that teaches someone to use **MFAMap** from scratch. A first-time user, typically an IT admin or MSP engineer, should be able to read this one page and then run the tool, pick the right flags, and understand the report without opening any other documentation.

## Format

- One page, **A4 portrait** (210 × 297 mm). It should read well on screen and print cleanly.
- Use the **joelabs** design system if it's available. Otherwise, follow the brand notes below exactly.
- Dense but scannable: clear sections, short sentences, and real commands in monospace code blocks. No filler, no marketing copy, no invented stats or quotes.

## Brand

- MFAMap is "a joelabs project". Show the MFAMap logo top left: "MFA" in white, "Map" in yellow, yellow mark. Put "a joelabs project" in the footer. Don't redraw or distort the logo; use a plain text wordmark if the logo file isn't available.
- Page ground brand grey `#26272A`; cards and code blocks `#2F3034`; raised elements and dividers `#3A3B40`.
- Brand yellow `#FFC83D` for accents, step numbers and the logo. **Yellow is never a status colour**, and never put yellow text on white or light grey.
- Text: white for body, `#A9AAB0` for secondary text, `#85868D` for labels.
- Status colours, used only when showing report statuses and always with a text label: enrolled/registered green `#7CD591`, partial/legacy only amber `#E88B0E`, not registered/no methods red `#F56A7E`, modern methods blue `#6DABDF`.
- Fonts: **DM Sans** for text, **JetBrains Mono** for commands and file names.

## Content, in this order

### 1. Header
- MFAMap logo, and the title "Getting started with MFAMap".
- One-line description: "A free PowerShell tool that maps MFA and authentication method registration across a Microsoft Entra group or your whole tenant, as a single HTML report."

### 2. Before you start (a compact checklist)
- PowerShell 7 (recommended) or Windows PowerShell 5.1.
- An admin account with at least the **Authentication Administrator** or **Global Reader** role.
- The Microsoft Graph PowerShell module, installed once:
  `Install-Module Microsoft.Graph -Scope CurrentUser -Force`
- Reassurance line: "Read-only. MFAMap signs in as you and can't change anything in the tenant. No app registration needed."

### 3. Run it in five steps (numbered, the visual centrepiece)
1. **Download** the latest MFAMap from **mfamap.uk**. Get the newest version each time.
2. **Make a folder for the customer** and put `MFAMap.ps1` in it, e.g. `C:\MFAMap\Contoso`.
3. **Open PowerShell and go to that folder:** `cd C:\MFAMap\Contoso`
4. **Run the script:**
   `PowerShell -ExecutionPolicy Bypass -File .\MFAMap.ps1 -AllUsers`
   Note: "Bypass applies to this run only and changes nothing on the machine."
5. **Pick a mode, sign in, save.** Choose a tracking mode (1–5) at the prompt, sign in with your Microsoft admin account, then choose where to save the report. Open the `.html` file in any browser.

### 4. Choose who to audit (the two scopes, side by side)
- **Whole tenant:** `-AllUsers`. Every enabled member account. Guests and disabled accounts are left out.
- **One group:** `-GroupId "object-id"`. The group's Object ID is on its Overview page in entra.microsoft.com → Groups. Only direct members are included, not nested groups.
- One line underneath: "Use one or the other, not both."

### 5. Flags (a reference table, the most important part after the steps)

| Flag | What it does | Example |
|---|---|---|
| `-AllUsers` | Audit every enabled member account in the tenant. Can't be combined with `-GroupId` | `.\MFAMap.ps1 -AllUsers` |
| `-GroupId` | Audit the direct members of one Entra group | `.\MFAMap.ps1 -GroupId "object-id"` |
| `-LicensedOnly` | Leave out accounts with no licence. Without it, they're included and tagged **Unlicensed** | `.\MFAMap.ps1 -AllUsers -LicensedOnly` |
| `-Mode` | Choose the tracking mode (1–5) up front so the script doesn't ask | `.\MFAMap.ps1 -AllUsers -Mode 5` |
| `-OutputPath` | Save to a specific file and skip the save dialog. `.html` is added if missing | `-OutputPath "C:\MFAMap\Contoso\mfamap.html"` |
| `-Demo` | Preview a report with made-up users. No sign-in needed | `.\MFAMap.ps1 -Demo -Mode 5` |

Flags can be combined, e.g. `.\MFAMap.ps1 -AllUsers -LicensedOnly -Mode 5`.

### 6. Tracking modes (a compact five-row list)
1. **Authenticator + Windows Hello for Business.** Full enrolment, with a "Partially enrolled" section for users who have only one of the two.
2. **Windows Hello for Business only**
3. **Microsoft Authenticator only.** Software OATH/TOTP tokens count, with a "TOTP only" badge.
4. **Passkey.** FIDO2 keys or device-bound passkeys in Authenticator.
5. **Full method audit.** All seven methods, grouped into **Modern methods**, **Legacy only** (SMS, voice, email only) and **No methods**. *Start here if you're not sure.*

### 7. Reading the report (small annotated callouts, not a screenshot)
- **Status labels**, shown as coloured pills with their text: Registered / Fully enrolled (green), Partial or Legacy only (amber), Not registered or No methods (red), Modern methods (blue, mode 5).
- **Unlicensed tag:** a small grey tag next to a name means the account has no licence but can still sign in. Shared mailboxes, service accounts and leavers often show up here. If the account doesn't need to sign in, block sign-in instead of registering MFA.
- **Risk filters (mode 5):** SMS only, Voice only and Legacy only buttons show who would be locked out if you turned that method off. **Copy UPNs** and **Download CSV** export the list, ready for an Entra group import.
- **Save as PDF** button in the report header.

### 8. Track progress over time (one short panel)
- Each run also saves a `.json` snapshot next to the report.
- Run again later, saving to **the same folder** with the same scope and mode, and MFAMap automatically makes a **delta report** (`_delta.html`). It shows who enrolled, who lapsed, who joined or left, and progress then vs now.
- Tip: "One folder per customer, run monthly."
- Note: "`-LicensedOnly` runs are only compared with other `-LicensedOnly` runs."

### 9. Footer
- "Reports contain real names, emails and MFA status, so treat them as internal data."
- **mfamap.uk** · "a joelabs project"

## Layout guidance

- The five-step run (section 3) and the flags table (section 5) are the two hero areas. Give them the most space and the strongest hierarchy.
- Suggested flow: header across the top; "Before you start" and "Choose who to audit" as a two-column band; the five steps; the flags table full width; then modes, reading the report and tracking progress as a three-column band; footer.
- Every command must be copied exactly as written above: same spelling, capitalisation, quotes and backslashes. Don't invent flags, modes or features that aren't listed here.
- Keep it to one page. If space is tight, shorten the descriptions in sections 6–8 before cutting anything from sections 3–5.
