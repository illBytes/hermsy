# Hermsy privacy policy

_Effective 25 October 2026. Hermsy is made by illbytes._

Hermsy is an app for talking to **Hermes Agent**, an AI agent that you run on
a server of your own. This policy explains what Hermsy does with your
information. In short: illbytes does not collect your conversations or
your voice. Hermsy sends your messages to the server you choose and keeps
the rest encrypted on your phone.

## What illbytes collects

Only what it takes to wake your phone for a notification (see
Notifications below): your phone's push token, passed through illbytes' push
service and not stored. Hermsy has no illbytes account, no advertising and no
analytics. illbytes cannot see your conversations, your voice or your
settings.

## Where your information goes

**Your Hermes server.** The messages you write, the text of what you say,
and any pictures you attach are sent over an encrypted connection (HTTPS)
to the Hermes server whose address you enter in Hermsy. That server is run
by you, or by whoever you choose; its own policies and settings decide how
long it keeps your conversations.

**Your voice.** With Hermsy's voice models downloaded, calls and the
microphone button turn speech into text on your phone, and the recording
itself does not leave the device. Without them, the recording is sent to
your Hermes server to be turned into text there.

**Cloud voices (optional).** If you choose an OpenAI or ElevenLabs voice for
calls, the text of Hermsy's replies is sent, through your own server, to that
company to be spoken, using your own key with them. Their privacy policies
apply to that text. The free voices built into Hermsy run entirely on your
phone.

**Notifications.** To let your agent reach you, Hermsy registers your phone
with Google's Firebase Cloud Messaging, which gives it a push token, and
gives that token to your Hermes server. When your agent sends you something,
your server asks illbytes' push service to wake your phone, and the push
service asks Google. The push service is given the token and nothing else;
it keeps no record of tokens or of who was woken, apart from short-lived
rate-limit counts. The push itself carries no message, title or other
content: your phone then fetches what is new from your own server. If your
server turns the push service off, nothing is sent to illbytes and Hermsy
catches up when you open it.

## What stays on your phone

Your chat history, the Inbox, Hermsy's Brief and your settings are stored on
your phone. Chats, the Inbox and the Brief are encrypted with a key kept in
Android's secure hardware-backed storage. Your server address, its key and
your PIN (stored only as a salted hash) are kept in that secure storage.
Hermsy's data is not included in Android backups.

## Permissions

- **Microphone**: for dictation and voice calls, only while you use them.
  During a call Hermsy keeps listening with the screen off, shown by an
  ongoing "Call with Hermsy" notification.
- **Camera**: to take a picture to send, or to scan the QR code that connects
  Hermsy to your Hermes, only when you choose to. A scanned code is read on
  the phone; the camera image never leaves it.
- **Notifications**: to show messages your agent sends.
- **Fingerprint**: to unlock Hermsy; your fingerprint never reaches Hermsy.

## Reporting a reply

You can report any reply, Inbox message or Brief as offensive or wrong.
Hermsy then opens your email app with a message to illbytes containing the
reason and the text you are reporting. It reaches illbytes only if you send
it, and illbytes uses it only to look into the report.

## Deleting your information

Delete a chat or an Inbox message in Hermsy to remove it from your phone.
Uninstalling Hermsy removes everything it stored on your phone. Conversations
on your Hermes server are deleted there, by you.

## Children

Hermsy is not meant for children under 13.

## Changes and contact

If this policy changes, the new version will be posted here with its date.
Questions: support@illbytes.com.
