# Google Play store listing

Draft text for Play Console › Grow › Store presence › Main store listing.
Character limits are Google's.

## App name (30 max)

**Hermsy: AI Agent Chat & Voice** (30)

Keep "Hermes" out of the title (Hermès, the fashion house, guards the
name); "for Hermes Agent" in the descriptions says what it works with.

## Short description (80 max)

Chat and talk with your own self-hosted AI agent. Built for Hermes Agent.  (73)

## Full description (4,000 max)

Hermsy is the phone app for Hermes Agent, the AI agent you run on your own
server. Chat with it, talk to it, and let it reach you, all from a quiet,
beautiful app that keeps your conversations yours.

**Your agent, your server**
Hermsy connects to the Hermes server you host. There is no Hermsy account
and no Hermsy cloud: your messages go to your own server.

**Talk, don't type**
Start a voice call and simply talk. Hermsy listens and speaks on your phone,
waits while you think, and hangs up when you say goodbye. Calls keep going
with the screen off, and work with Bluetooth and wired headsets.

**Dictation that stays on your phone**
Download Hermsy's free voice models once, and speech is turned into text on
the device: your voice never leaves it. Calls run on the same models.

**The Brief**
Wake up to a short summary of your day: what's on, what's due, and what your
agent suggests. Add it to your home screen as a widget.

**Messages your agent sends on its own**
Scheduled jobs and reminders from Hermes arrive as notifications and wait in
the Inbox, with an unread count. Reply to any of them in its own thread.

**Private by design**
- Locked with a PIN or your fingerprint
- Chats, the Inbox and the Brief are encrypted on your phone
- Notifications show no message text on the lock screen
- No ads, no analytics, no tracking

**Your agent, as you made it**
The name and personality you give your agent in Hermes carry through the
whole app.

**Made with care**
Light and dark themes that follow your phone, a living glow that shows what
your agent is doing, haptics, and a choice of voices, from free on-device
voices to optional cloud voices through your own server.

Hermsy needs a Hermes Agent server (version 0.19 or newer) to connect to.
Set one up at hermes-agent.nousresearch.com. For notifications, the Inbox
and the Brief, add the free Hermsy plugin to it
(github.com/illBytes/hermsy-hermes). Running Hermes with hermes-spawn? One
command, hermes-spawn connect, sets it all up and shows a QR code: scan it
in Hermsy and you're connected.

## Category and tags

- Category: **Productivity**
- Tags: AI assistant, Personal assistant, Voice assistant, Productivity tools

## Contact details

- Email: support@illbytes.com
- Website: _illbytes site, if any_
- Privacy policy URL: where you host `privacy-policy.md` (see README)

## Graphics

| Asset | File | Play requirement |
|---|---|---|
| App icon | `graphics/icon_512.png` | 512×512 PNG |
| Feature graphic | `graphics/feature_graphic.png` | 1024×500 |
| Phone screenshots | `screenshots/dark/01–08` (or `light/`) | 2–8, 1080×1920 (9:16) |

Screenshot order and captions (Play shows them in order):

1. `01_chat`: Chat with your own AI agent
2. `02_call`: Talk to it on a live voice call
3. `03_brief`: Your day at a glance with the Brief
4. `04_history`: Every conversation, pinned and searchable
5. `05_inbox`: Messages your agent sends on its own
6. `06_settings`: Simple settings, with a live summary of each
7. `07_presence`: A living glow that shows what your agent is doing
8. `08_lock`: Locked with a PIN or your fingerprint

Every screenshot shows made-up content only. Regenerate them with:

```bash
SHOTS_DIR=store/screenshots/dark flutter test tool/shots/store_shots_test.dart
SHOTS_THEME=light SHOTS_DIR=store/screenshots/light flutter test tool/shots/store_shots_test.dart
```

## Release notes for the first version

Hermsy's first release: chat and voice calls with your Hermes agent, the
Brief and its home-screen widget, the Inbox, and an app that stays locked
and encrypted on your phone.
