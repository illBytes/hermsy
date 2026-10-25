# Publishing Hermsy on Google Play

Everything for the Play Store is here:

| File | What it is |
|---|---|
| `listing.md` | Store name, descriptions, category, screenshot captions |
| `privacy-policy.md` | The privacy policy to host at a public URL |
| `data-safety.md` | Answers for Data safety, permissions, content rating, app access |
| `firebase-setup.md` | Registering Hermsy in Firebase, for notifications |
| `screenshots/dark`, `screenshots/light` | 8 phone screenshots each, 1080×1920, made-up content |
| `graphics/icon_512.png` | The 512×512 app icon |
| `graphics/feature_graphic.png` | The 1024×500 feature graphic |

## The app

- **App ID:** `com.illbytes.hermsy_app` (permanent once published)
- **Build:** `tool/build_play.sh` makes
  `build/app/outputs/bundle/prodRelease/app-prod-release.aab`, signed with
  the illbytes upload key, and checks no server address or key is inside.
- **Version:** bump `version:` in `pubspec.yaml` before each upload; the
  number after `+` must go up every time (1.0.0+1, then 1.0.1+2, …).

## Before the first upload

1. **Back up the upload key.** `android/upload-keystore.jks` and
   `android/key.properties` (it holds the password) are not in git. Put both
   in Bitwarden. Without them you cannot upload updates. (Play App Signing
   can reset an upload key, but it takes days.)
2. **Register the new app IDs in Firebase**, for notifications: follow
   `firebase-setup.md`. Until then the app builds without push.
3. **Host the privacy policy** at a public URL (your illbytes site, or a
   page served by your relay) and put the URL in the listing. Make sure
   support@illbytes.com receives mail: reports and Google's notices go
   there.
4. **Give Google's reviewers a test Hermes server** (address and key) for
   "App access". Not your own server: they would use your agent.
5. **Record a short video** of a call continuing with the screen locked,
   for the foreground service declaration (see `data-safety.md`).

## In Play Console

1. Create the app: name "Hermsy", app (not game), free.
2. Let Google manage the app signing key (Play App Signing, the default).
3. Fill in App content from `data-safety.md`, and the store listing from
   `listing.md` with the graphics above.
4. Upload the bundle to **Internal testing** first and install it from Play
   on your phone. It is a different app from the Hermsy you have now (new
   ID, Google's signature), so it starts fresh; uninstall the old one once
   you are happy.
5. Then promote it to Production. With the illbytes organisation account
   there is no 12-tester, 14-day closed test to run first.

## What other people need

Chat and calls work with any Hermes server whose API server is on and
reachable over HTTPS. Notifications, the Inbox's messages and the Brief also
need the Hermsy plugin (github.com/illBytes/hermsy-hermes), and pushes go
through the push service at push.hermsy.illbytes.com, which must stay up.
With hermes-spawn, `hermes-spawn connect <name>` does all of it and prints a
QR code that Hermsy scans. See `docs/hermsy-for-anyone.md`. The test server
you give reviewers should have the plugin.

## Google's AI-generated content policy

Done: every AI reply has a flag under it and **Report** in its long-press
menu; Inbox messages and the Brief can be reported too. A report opens an
email to support@illbytes.com with the reason and the reply filled in.
Read those reports: Google expects you to act on them.
