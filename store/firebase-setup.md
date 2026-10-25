# Firebase setup for Hermsy

Notifications reach the phone through Firebase Cloud Messaging (FCM).
Firebase only delivers to apps registered in your project, so Hermsy's two
app IDs need adding. Your relay and server change nothing: they send
through the same project.

You keep the same Firebase project (`frank-hermes-f1343`). Its ID can't be
renamed, and doesn't need to be; it's never shown to anyone.

## 1. Open the project

1. Go to <https://console.firebase.google.com> and sign in.
2. Click the project **frank-hermes-f1343**.
3. Optional: ⚙️ (next to "Project Overview") › **Project settings** ›
   **General** › **Project name** › change it to **Hermsy**. This only
   changes the label you see.

## 2. Add Hermsy (the Play app)

1. ⚙️ › **Project settings** › **General**, scroll to **Your apps**.
2. Click **Add app** › the **Android** icon.
3. **Android package name:** `com.illbytes.hermsy_app`
   (exactly this; it can't be edited later).
4. **App nickname:** `Hermsy`.
5. **Debug signing certificate SHA-1:** leave empty (notifications don't
   need it).
6. Click **Register app**.
7. On "Download and then add config file", click **Next** (you will
   download the file in step 4). Skip the SDK step (**Next**), then
   **Continue to console**.

## 3. Add Hermsy Dev (the test app)

Repeat step 2 with:

- **Android package name:** `com.illbytes.hermsy_app.dev`
- **App nickname:** `Hermsy Dev`

## 4. Download the config file

1. ⚙️ › **Project settings** › **General** › **Your apps**.
2. Click either Hermsy app, then **google-services.json** (the download
   button). The file lists every app in the project, so one download
   covers both.
3. Put it in the project at `android/app/google-services.json`,
   replacing the one there. (It's in `.gitignore`; it stays out of git.)

## 5. Tidy up (optional)

If you added `com.illbytes.hermes_app` earlier, remove it: click it in
**Your apps** › ⚙️ › **Remove this app**. Leave `com.hermes.hermes_app`
until you've moved to Hermsy from Play: your current Frank still uses it.

## 6. Tell Claude

Then the next build turns notifications on for both apps by itself. Each
app registers with your relay the first time it opens, so nothing else is
needed on the server.
