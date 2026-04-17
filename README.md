# 🎯 EnrolWatch

**Live MFA enrolment tracker for Microsoft Entra ID drop-in sessions**

EnrolWatch gives you a real-time view of MFA enrolment progress across a target group — all from a single HTML file that runs entirely in your browser. No server. No database. No data leaves the browser.

Sign in with your Microsoft admin account, point it at an Entra group, and instantly see who has enrolled, who is partially through, and — most importantly — who still needs catching.

---

## ✨ Key features

- 🗂️ **Single file** — the entire app is one HTML file with no backend required
- 🔑 **Delegated auth only** — authenticates as the signed-in user via MSAL.js; no application-level permissions
- 🎯 **Group-scoped** — targets a specific Entra group, not your entire tenant
- 🔄 **Auto-refresh** — re-queries Microsoft Graph every 60 seconds without any page reload
- ⚡ **Manual refresh** — instantly re-query after enrolling someone in front of you
- 📊 **Live progress bar** — visual breakdown of complete, partial, and not-started at a glance
- 🚨 **"Still to catch" first** — not-started users are surfaced at the top, not buried at the bottom
- 🟡 **Partial enrolment detection** — users with only one method registered are called out separately
- ✅ **Completed section collapsed** — enrolled users are tucked away so they don't distract
- 🏢 **Works for any tenant** — configure with any tenant ID, client ID, and group ID

---

## 🔧 How it works

```
Browser → MSAL.js → Microsoft Entra ID  (sign-in)
                           ↓
               Microsoft Graph API
               /groups/{id}/members          (target group membership)
               /users/{id}/authentication/methods  (per-user auth methods)
                           ↓
               All processing in browser memory
               No data sent anywhere else
```

EnrolWatch fetches the membership of your target group, then queries each member's registered authentication methods in parallel. It classifies each user as **fully enrolled** (Authenticator + WHfB), **partially enrolled** (one method only), or **not started** (nothing registered), then renders the dashboard and repeats on the configured interval.

---

## 🛡️ Permissions

EnrolWatch requests three **delegated** Graph permissions. All are read-only — the app cannot make any changes to a tenant.

| Permission | Why it's needed |
|---|---|
| `User.Read` | Sign in the current user and read their basic profile |
| `UserAuthenticationMethod.Read.All` | Read MFA registration details for all users in the group |
| `GroupMember.Read.All` | Read the membership of the target Entra group |

> **Admin consent is required** before the tool can be used. A Global Administrator or Privileged Role Administrator must grant consent once. See [SETUP.md](./SETUP.md) for full instructions.

---

## 📁 Repository structure

```
enrolwatch.html       ← The entire application (single file)
README.md             ← This file
SETUP.md              ← Full technical setup guide
```

---

## 🚀 Quick start

Full step-by-step instructions are in [SETUP.md](./SETUP.md). The short version:

1. Register a single-tenant Entra app in your tenant
2. Add the three delegated API permissions and grant admin consent
3. Set the redirect URI to `http://localhost` (or your hosting URL)
4. Grab your Application (client) ID, Directory (tenant) ID, and the Object ID of your target group
5. Paste the three values into the config block at the top of `enrolwatch.html`
6. Open the file in a browser, or serve it locally with `python -m http.server 8080`

---

## 🔒 Security

### 🌐 No data leaves the browser

EnrolWatch has no backend server. It is a static HTML file. Once your browser has downloaded the page, everything runs locally. The only network calls the app makes are directly to Microsoft's own services:

- `login.microsoftonline.com` — Microsoft's authentication endpoint (sign-in)
- `graph.microsoft.com` — the Microsoft Graph API (reading group and MFA data)
- `alcdn.msauth.net` — Microsoft's own CDN for the MSAL.js library
- `fonts.googleapis.com` — Google Fonts CDN for the DM Sans and JetBrains Mono typefaces

There are no calls to any third-party infrastructure, no analytics platforms, no error reporting services, and no logging endpoints. You can verify this yourself by opening the browser Network tab (F12) while using the app and inspecting every request made.

### 🔑 Delegated permissions — not application permissions

EnrolWatch uses **delegated permissions** via the OAuth 2.0 authorisation code flow with PKCE. This means:

- The app authenticates *as the signed-in user* — it can only see what that user is permitted to see
- There is no background process, no scheduled job, and no way for the app to call Graph when a user is not actively signed in
- The app has no client secret and no certificate — there is no long-lived credential that could be leaked or misused

### 🔐 Why there's no client secret

Single-page applications running in the browser cannot hold a secret securely — the full source code is visible to anyone who opens browser developer tools. Instead, MSAL.js 2.x uses **PKCE (Proof Key for Code Exchange)**, the industry-standard approach for public clients. PKCE generates a one-time cryptographic challenge per sign-in that prevents authorisation codes from being intercepted and replayed, providing equivalent security without any secret needing to be stored.

### 💾 Token storage

Access tokens are stored in the browser's `sessionStorage`. This is deliberately more restrictive than `localStorage`:

- `sessionStorage` is scoped to a single browser tab — other tabs cannot access it
- `sessionStorage` is automatically cleared when the tab is closed
- It is not persisted to disk in the way that cookies or `localStorage` can be

### 📋 What each permission actually allows

**`User.Read`** — Reads the signed-in user's own profile. Used by MSAL to confirm the identity of the person who signed in. Cannot read other users' profiles or make any changes.

**`UserAuthenticationMethod.Read.All`** ([Microsoft docs](https://learn.microsoft.com/en-us/graph/permissions-reference#userauthenticationmethodreadall)) — Reads the authentication methods registered by users. EnrolWatch uses this to determine which MFA methods each group member has registered. It **cannot** add, modify, or delete any authentication method for any user.

**`GroupMember.Read.All`** ([Microsoft docs](https://learn.microsoft.com/en-us/graph/permissions-reference#groupmemberreadall)) — Reads the membership of groups. EnrolWatch uses this solely to retrieve the members of your configured target group. It **cannot** modify group membership, create or delete groups, or read group-owned resources.

All three are **read-only** permissions. The Microsoft Graph API enforces this at the service level — there is no write path available to a delegated token scoped to these permissions regardless of what the client attempts.

### 🚫 What EnrolWatch cannot do

To be explicit, here is what EnrolWatch **cannot** do — by design and by the hard constraints of its permission set:

- ❌ Add, modify, or delete any MFA method for any user
- ❌ Reset or change any user's password
- ❌ Create, disable, or delete user accounts
- ❌ Read email, calendar, files, Teams messages, or any user content
- ❌ Modify conditional access policies, security defaults, or any tenant configuration
- ❌ Access users outside the configured target group
- ❌ Run when no user is actively signed in
- ❌ Retain any data after the browser tab is closed

### 📊 Audit trail in the tenant

When admin consent is granted and a user signs in, the following is recorded in the tenant's own Entra audit and sign-in logs:

- The consent grant — which permissions were approved, by whom, and when
- Each sign-in — the application name (EnrolWatch), the user's UPN, and the client IP address
- Resource access events for each Graph API call made during the session

The tenant's own security team has full visibility of when their data was accessed and by whom.

---

## 📝 What counts as enrolled

| Method registered | Counted as |
|---|---|
| Microsoft Authenticator app | ✅ Authenticator App |
| Windows Hello for Business | ✅ Windows Hello |
| FIDO2 security key | ✅ Windows Hello (serves the same purpose) |
| SMS / Voice Call / Software TOTP only | ❌ Neither — user shown as **Not started** |

A user is marked **Fully Enrolled** only when both Authenticator App and Windows Hello (or FIDO2) are registered. Users with only one method appear in the **Partially Enrolled** section.

---

## 📦 Dependencies

| Dependency | Version | How loaded |
|---|---|---|
| [MSAL.js](https://github.com/AzureAD/microsoft-authentication-library-for-js) | 2.38.3 | Microsoft CDN (`alcdn.msauth.net`) |
| [DM Sans](https://fonts.google.com/specimen/DM+Sans) | Variable | Google Fonts CDN |
| [JetBrains Mono](https://fonts.google.com/specimen/JetBrains+Mono) | Variable | Google Fonts CDN |

---

## 🌐 Browser support

Any modern browser supporting MSAL.js 2.x: Edge, Chrome, Firefox, Safari. Internet Explorer is not supported.

---

## 👏 Credits

Designed and built by [Joe Samuels](https://joesamuels.co.uk) at [REDACTED](https://beaconit.co.uk).
