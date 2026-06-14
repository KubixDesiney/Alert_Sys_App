# Enterprise SSO + MFA

Optional, per-company. **SSO** lets a customer's staff sign in with their own
corporate identity provider; **MFA** adds an **SMS** second factor. Both fit the
dedicated-instance model — each company configures its own providers in its own
Firebase project.

The app already supports both (`lib/services/enterprise_auth_service.dart` — it is
additive and does not change the email/password flow). SSO is configured by the
company's IT team **in-app** (SuperAdmin → Access & Identity); MFA is enrolled per
user from the same tab (or any profile screen).

---

## 0. Prerequisite — Identity Platform

SSO and MFA require **Google Cloud Identity Platform** (the upgraded Firebase
Auth). Firebase console → Authentication → accept the upgrade. It has its own
pricing (free tier, then per-MAU / per-SMS).

---

## 1. SSO — configured in-app, no rebuild

The company's IT team: **SuperAdmin → Access & Identity** → pick a provider
template (Microsoft Entra, Google Workspace, Okta, Keycloak, or custom OIDC/SAML)
→ set the **Provider ID** + button label → **Enable** → **Save**. The login screen
shows the SSO button live (it reads `auth_config/sso`).

One server-side step remains (it holds the client secret safely): Firebase console
→ Authentication → Sign-in method → **Add provider** (OpenID Connect or SAML) with
the **same provider id**, paste the **client ID / issuer / client secret** from the
identity provider, and register the redirect URL the tab shows
(`https://<project>.firebaseapp.com/__/auth/handler`) in **both** Firebase and the
IdP.

OIDC issuer examples: Entra `https://login.microsoftonline.com/<tenant-id>/v2.0`;
Google `https://accounts.google.com`; Okta `https://<domain>.okta.com`.

> First-time SSO users are created with **no role** — grant access from Production
> Managers before they can sign in.

---

## 2. MFA — SMS (phone second factor)

**Console:** Authentication → enable **"SMS multi-factor authentication"**.

**Android prerequisite** (or the SMS silently never sends):
- Register the app's **SHA-1 + SHA-256** — Project settings → your Android app →
  Add fingerprint. Get them with `cd android && .\gradlew signingReport` (use the
  `debug` variant for development).
- **Re-download `google-services.json`** into `android/app/` and rebuild.
- Optional: add a **test phone number** (Sign-in method → Phone → test numbers) to
  test without sending real texts.

**App flow (already coded):**
- **Enrol:** SuperAdmin → Access & Identity → **"Set up / manage 2FA"**, or push
  `MfaEnrollmentScreen` from any profile screen → enter phone in international
  format (`+216…`) → receive SMS → verify.
  (`EnterpriseAuthService.startPhoneEnrollment` / `finishPhoneEnrollment`.)
- **Sign-in:** when an enrolled user logs in (email/password *or* SSO), the app
  texts a code and prompts for it
  (`startSmsSignIn` → `resolveSmsSignIn`, wired in `login_screen.dart`).

---

## 3. Test checklist (per platform — auth bugs lock people out)

- [ ] `flutter analyze` clean (verifies the phone-MFA API vs the pinned `firebase_auth`)
- [ ] Email/password login still works unchanged (regression)
- [ ] SSO login works; a new SSO user is "no role" until an admin grants one
- [ ] SHA-1 + SHA-256 registered, `google-services.json` refreshed, app rebuilt
- [ ] Enrol a phone → sign out → sign in → SMS code prompt → success
- [ ] Wrong code is rejected cleanly; the user is not locked out
- [ ] Recovery path for a lost phone documented (an admin removes the factor / re-enrol)

---

## 4. Notes

- **Enforcement** (who *must* use MFA) is set in the Identity Platform console; the
  app only drives enrolment and the sign-in challenge.
- SMS costs per message and needs each user's phone number on file. To switch to
  **TOTP** (free, works offline) later, swap the phone calls in
  `EnterpriseAuthService` for `TotpMultiFactorGenerator` and enable TOTP in the
  console — the rest of the wiring is identical.
- SSO + MFA are per Firebase project, so different companies can run entirely
  different providers and policies with zero code changes.
