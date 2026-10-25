# Play Console answers: Data safety, permissions, content rating

Draft answers for the forms in Play Console › Policy › App content. Check
each against how you run Hermsy before submitting; you are responsible for
them.

## Data safety

**Does your app collect or share any of the required user data types?** Yes.

Google counts data that leaves the phone as "collected", even when it goes
to a server the user runs. So declare what Hermsy sends to the user's own
Hermes server, plus what Firebase handles:

| Data type | Collected | Shared | Why | Optional? |
|---|---|---|---|---|
| Messages › Other in-app messages | Yes | No | App functionality | Required to use the app |
| Photos and videos › Photos | Yes | No | App functionality | Optional (only when attached) |
| Audio › Voice or sound recordings | Yes | No | App functionality | Optional (only with Hermes speech-to-text; on-device is the default) |
| Device or other IDs | Yes | No | App functionality (notifications: the FCM push token goes to the user's Hermes and, for each wake-up, through illbytes' push service to Firebase) | Optional (only with notifications on) |

If you leave cloud voices in the app: "Other in-app messages" is also
**shared** (with OpenAI or ElevenLabs, for text-to-speech), only when the
user chooses such a voice.

- **Is all of the user data encrypted in transit?** Yes (HTTPS).
- **Do you provide a way for users to request that their data is
  deleted?** Yes: chats and Inbox messages are deleted in the app;
  uninstalling removes all local data; server-side data is under the
  user's own control.
- **Data processed ephemerally?** The push token, in illbytes' push service:
  yes (used to send one wake-up, not stored). Everything else: no.
- **Advertising or analytics?** None.

## Permissions declarations

- **Foreground service types** (Android 14+): `microphone` and
  `mediaPlayback`. Use: "During a voice call with the user's AI agent, the
  app keeps listening and speaking while the screen is off or the app is in
  the background. The call is started by the user, shown in an ongoing
  notification with an End call button, and stops when the call ends."
  Google asks for a short video of this: record a call, lock the phone, show
  the notification and End call.
- **Camera, microphone, notifications**: standard runtime permissions, asked
  when first used.

## Content rating questionnaire (IARC)

- Category: **Utility, productivity, communication, or other**.
- Violence, sexual content, profanity, drugs, gambling: **No** (the app
  shows what the user's own AI agent writes; it has no content of its own).
- Does the app let users interact or exchange content with other people?
  **No** (only with the user's own agent).
- Does it share the user's location? **No**.
- Does it contain AI-generated content? **Yes**: replies from the user's own
  AI agent.

Expected rating: Everyone / PEGI 3, or close to it.

## Target audience

Ages **18 and over** (simplest; the app is for people who run their own
server). This keeps Hermsy out of the Families policy requirements.

## App access (for Google's reviewers)

Hermsy does nothing without a Hermes server, so reviewers need one. In
"App access", choose "All or some functionality is restricted" and give
them a server address and API key for a test Hermes server (not your own),
with a note: "Open Hermsy, create any PIN, then Settings › Hermes › enter the
address and key."

## Ads

**No**, the app contains no ads.
