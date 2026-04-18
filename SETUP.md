# MFA Enrolment Dashboard — Setup Guide

## What this is

A single HTML file that signs in with your Microsoft admin account, then polls Microsoft Graph every 60 seconds to track Authenticator app and Windows Hello for Business registration for everyone in a target Entra group. No server, no backend, no installation required. Open it in a browser and leave it running.

---

## Prerequisites

- A Microsoft 365 admin account with at least **Authentication Administrator** or **Global Reader** role
- Access to the **Entra ID portal** (entra.microsoft.com) to create an app registration
- The **Object ID** of the Entra group you want to track

---

## Step 1 — Create the App Registration

1. Go to [entra.microsoft.com](https://entra.microsoft.com) → **Applications** → **App registrations** → **New registration**
2. Give it a name, e.g. `MFA Dashboard`
3. Under **Supported account types**, select **Accounts in this organizational directory only**
4. Under **Redirect URI**, select **Single-page application (SPA)** from the dropdown, then enter:
   - If running the file **locally**: `http://localhost`
   - If hosting the file on a web server: the full URL to the file (e.g. `https://yoursite.com/mfa-dashboard.html`)
5. Click **Register**

> **Note your Application (client) ID and Directory (tenant) ID** from the Overview page — you'll need these shortly.

---

## Step 2 — Grant API Permissions

1. In your new app registration, go to **API permissions** → **Add a permission** → **Microsoft Graph** → **Delegated permissions**
2. Add the following three permissions:
   - `User.Read`
   - `UserAuthenticationMethod.Read.All`
   - `GroupMember.Read.All`
3. Click **Grant admin consent** (the button with the green tick) — this avoids each user being prompted to consent individually

Your permissions page should show all three as **Granted** with a green tick.

---

## Step 3 — Get your Group Object ID

1. In Entra ID, go to **Groups** and find the group containing the staff you want to track
2. Open the group and copy the **Object ID** from the Overview page

---

## Step 4 — Configure the dashboard file

Open `mfa-dashboard.html` in a text editor (Notepad, VS Code, anything works).

Near the top of the file, find this block:

```javascript
const CONFIG = {
  clientId:  "YOUR_CLIENT_ID_HERE",
  tenantId:  "YOUR_TENANT_ID_HERE",
  groupId:   "YOUR_GROUP_ID_HERE",
  refreshInterval: 60
};
```

Replace the three placeholder values with your actual IDs from the steps above. For example:

```javascript
const CONFIG = {
  clientId:  "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  tenantId:  "f0e1d2c3-b4a5-6789-0abc-def123456789",
  groupId:   "11223344-5566-7788-99aa-bbccddeeff00",
  refreshInterval: 60
};
```

Save the file.

---

## Step 5 — Running the dashboard

### Option A — Open directly in a browser (simplest)

Double-click the HTML file to open it. If your browser blocks the MSAL popup due to local file restrictions, use **Option B** instead.

### Option B — Serve locally (recommended)

If you have Python installed, open a terminal in the folder containing the file and run:

```bash
python -m http.server 8080
```

Then open `http://localhost:8080/mfa-dashboard.html` in your browser.

> Make sure `http://localhost` is listed as a redirect URI in your app registration (Step 1). If using port 8080 specifically and that doesn't work, try adding `http://localhost:8080` as an additional redirect URI.

---

## Using the dashboard

1. Open the file in your browser
2. Click **Sign in with Microsoft** and sign in with your admin account
3. The dashboard will load and begin auto-refreshing every 60 seconds
4. Use **↺ Refresh Now** after you've enrolled someone in front of you to update immediately
5. The **Still to Catch** section leads — these are the people with nothing registered yet
6. **Partially Enrolled** shows staff who have one method but not the other
7. **Fully Enrolled** is collapsed by default — click it to expand if needed

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Sign-in popup blocked | Browser blocking popups | Allow popups for the file/localhost URL |
| `AADSTS50011` redirect URI error | Redirect URI mismatch | Add the exact URL you're using to the app registration |
| `Insufficient privileges` error | Permissions not granted | Re-check admin consent was granted in Step 2 |
| Users show as not started incorrectly | API permissions issue | Ensure `UserAuthenticationMethod.Read.All` has admin consent |
| Group shows 0 members | Wrong group ID | Double check the Object ID in Entra ID |

---

## Notes on what counts as registered

| Method | Detected as |
|---|---|
| Microsoft Authenticator app | Authenticator App ✓ |
| Windows Hello for Business | Windows Hello ✓ |
| FIDO2 security key | Windows Hello ✓ (shown under WHfB column as it serves the same purpose) |
| SMS / Phone / TOTP only | Neither column — user will show as **Not started** |

A user is marked **Fully Enrolled** only when both Authenticator App and Windows Hello (or FIDO2) are registered.

---

## Refresh interval

The default is 60 seconds. To change it, edit the `refreshInterval` value in the config block at the top of the file. Minimum recommended is 30 seconds to avoid throttling the Graph API.
