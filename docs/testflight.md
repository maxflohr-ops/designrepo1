# TestFlight — what only Max can do, and what the workflow does after

`.github/workflows/testflight.yml` archives, signs, exports and uploads an
internal TestFlight build. It is `workflow_dispatch` only — it never fires on a
push, because a build going to testers should be a decision.

It cannot run until four values exist. **Three of them are identifiers and one
is a private key.** I did not create any of them and cannot: the `.p8` is a
credential, and handling credentials is off-limits for me by design. You paste
it into GitHub yourself, where the workflow reads it and I never see it.

---

## 1. Apple Developer — Team ID

developer.apple.com → Membership. Copy the 10-character Team ID.

Also confirm the bundle ID `com.bountysounds.ios` is registered under
Certificates, Identifiers & Profiles → Identifiers. Enable **App Attest** on it
while you're there; the cash-out path needs it in live mode.

## 2. App Store Connect — the app record

App Store Connect → My Apps → **+** → New App.

| field | value |
|---|---|
| Platform | iOS |
| Name | Bounty Sounds |
| Primary language | English (U.S.) |
| Bundle ID | `com.bountysounds.ios` |
| SKU | anything unique, e.g. `bountysounds-ios-001` |

The upload fails with a confusing error if this record doesn't exist yet, so do
it before the first run.

## 3. App Store Connect — API key

App Store Connect → Users and Access → **Integrations** → App Store Connect API
→ **+**. Name it something like `github-actions`, role **App Manager**.

It gives you three things, and the `.p8` **downloads exactly once**:

- **Issuer ID** — a UUID at the top of the page
- **Key ID** — 10 characters, next to the key
- **AuthKey_XXXXXXXXXX.p8** — the private key file

## 4. Put them in the repo

Settings → Secrets and variables → Actions.

**Variables** tab (not secret — these are identifiers):

| name | value |
|---|---|
| `APPLE_TEAM_ID` | your 10-character Team ID |
| `APPSTORE_ISSUER_ID` | the Issuer UUID |
| `APPSTORE_API_KEY_ID` | the 10-character Key ID |

**Secrets** tab:

| name | value |
|---|---|
| `APPSTORE_API_PRIVATE_KEY` | the entire contents of the `.p8`, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

These three names are not arbitrary — they are the canonical names the upload
action's own README uses, so the companion
[`download-provisioning-profiles`](https://github.com/Apple-Actions/download-provisioning-profiles)
action reads the same key without reconfiguration if you ever need it. That
repo also ships a `configure-github.sh` one-shot setup script that sets all
three for you via the `gh` CLI, if you'd rather not click through Settings.

Paste the `.p8` as-is, newlines and all. Don't base64 it, don't strip the
header. If you ever suspect it leaked, revoke it in App Store Connect — that
invalidates it immediately and costs you nothing but a re-paste.

---

## Then

Actions → **testflight** → Run workflow. It will:

1. Check all four values exist and fail with a readable message if not.
2. Archive Release, signing automatically via the API key
   (`-allowProvisioningUpdates` lets Xcode create the distribution certificate
   and provisioning profile for you — no manual cert wrangling, no fastlane
   match).
3. Set the build number to the GitHub run number, because App Store Connect
   rejects a build number it has already seen.
4. Export a signed `.ipa` and upload it with
   [`apple-actions/upload-testflight-build`](https://github.com/Apple-Actions/upload-testflight-build)
   @v5, waiting for processing so a rejection shows up as a failed job rather
   than a silent nothing. Worth knowing what that dependency actually is: it
   lives under the `Apple-Actions` GitHub org, but it is MIT-licensed and
   authored by **Itty Bitty Apps Pty Ltd**, not by Apple. Widely used and the
   de-facto standard, but it is a third-party action running with your API key,
   so it is pinned to a major tag rather than floating.
5. Keep the `.xcarchive` as an artifact for 30 days so a crash report from a
   tester can be symbolicated.

**Internal testers get the build straight away.** No Beta App Review for people
on your team — that only applies to external testers. So this is the fast path
to the app on your phone.

---

## Two things worth knowing before you run it

**This build is the offline demo.** `BSAPIBaseURL` is empty in `Info.plist`, so
the app runs on `MockBountyAPI` with fixture data. That is the right thing for a
first internal build — it exercises every screen with no backend, no Stripe, no
TikTok. Point it at a real API later by setting that key, and only after the
backend is deployed.

**The app has now been watched running.** CI run #25 walked all 24
screen/mode combinations on an iPhone 16 Pro Max simulator: every launch
clean, no crash reports, and every screen matches the design prototype.
Screenshots are on the run as the `ios-screenshots-6.9` artifact and, in
compressed form, on the `ci/screenshots` branch. So the risk this section
used to warn about is retired — the remaining unknown is a *physical device*,
which is exactly what a TestFlight build gets you.

## Encryption declaration

`ITSAppUsesNonExemptEncryption` is set to `false` in `Info.plist`. The app
speaks HTTPS and implements no cryptography of its own, which is exempt. Having
it in the plist stops App Store Connect asking on every single upload. If you
ever add bespoke crypto, revisit it — the answer is a legal declaration, not a
formality.
