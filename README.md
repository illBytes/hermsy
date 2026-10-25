# Hermsy

Hermsy is a phone app for your own [Hermes Agent](https://hermes-agent.nousresearch.com/): chat, voice calls, an Inbox for what Hermes sends on its own, a Brief of your day, and a Chief of Staff that texts you only when something needs you. It talks to your Hermes over HTTPS. There is no Hermsy account and no Hermsy cloud.

Published on Google Play by illbytes as **Hermsy** (`com.illbytes.hermsy_app`). This repo holds the Android app (Flutter) and the server pieces it relies on.

## How it fits

```text
Hermsy (phone) ──HTTPS + Hermes API key──▶ Your Hermes (its API server)
                                            ├─ chat, calls, chat titles, jobs ....... Hermes itself
                                            └─ /api/platforms/hermsy/events ......... the Hermsy plugin
                                                 Inbox, Brief, phones, cloud voices, setup

Your Hermes ──"wake <push token>"──▶ push.hermsy.illbytes.com ──▶ Firebase ──▶ phone
               (the plugin)            (illbytes runs this once)    the push carries nothing;
                                                                    the phone asks its own Hermes
```

- **The app** needs only a Hermes address and its API key.
- **The Hermsy plugin** (`server/hermes-plugin`, published as [illBytes/hermsy-hermes](https://github.com/illBytes/hermsy-hermes)) runs inside Hermes. It answers the app through Hermes's own API server, so there is no separate server, port or proxy route.
- **The push service** (`server/push`) is the one thing illbytes runs for everyone. Google only accepts pushes for the Play app from its publisher.

## Setting up a server

With Hermes in Docker via [hermes-spawn](https://github.com/oscarfrank/hermes-spawn), one command does everything: it switches on the API server, installs the plugin, gives Hermes an HTTPS address (Caddy, Cloudflare Tunnel or Tailscale), and prints a QR code:

```bash
hermes-spawn connect <name>
```

In Hermsy, tap **Scan QR code** (first screen, or Settings › Hermes). Without hermes-spawn, follow the [plugin README](server/hermes-plugin/hermsy/README.md). To set someone else up, see [docs/hermsy-for-anyone.md](docs/hermsy-for-anyone.md).

Chat and calls work with any Hermes whose API server is reachable over HTTPS. The Inbox, notifications, the Brief, cloud voices and the Chief of Staff need the plugin.

## Privacy

**How a notification stays private.** No message text, title or ID ever goes through Google:

1. Hermes sends something (`deliver: hermsy`). The Hermsy plugin stores it on your own Hermes.
2. The plugin asks illbytes' push service (`push.hermsy.illbytes.com`) to wake your phone, giving only the phone's push token.
3. The push service asks Firebase to deliver a push whose whole content is `{"type": "wake"}`.
4. The phone wakes, and Hermsy asks your own Hermes, over HTTPS with your API key, what is new.
5. Hermsy builds the notification on the phone from that answer.

| | Sees |
|---|---|
| Google / Firebase | That the app on a phone was woken, and when. Nothing else. |
| illbytes' push service | The phone's push token, and when it was woken. It stores neither. |
| Your Hermes | The messages (it wrote them). |
| Your lock screen | "Hermsy" only: notifications are private, so the text shows after unlocking. |

The timing is the one thing a push service can't hide. To send nothing to illbytes or Google at all, set `HERMSY_PUSH_URL=off` on Hermes: the Inbox then fills whenever you open the app.

On the phone:

- **Locked** with a PIN (stored as a salted PBKDF2 hash, with a lockout that survives restarts) or your fingerprint.
- **Encrypted:** chats, the Inbox and the Brief are encrypted (AES-GCM, key in Android's secure storage). The Hermes address and key are kept in secure storage too.
- **Not backed up:** Hermsy's data is left out of Android backups.
- **Voice stays local:** with the voice models downloaded, dictation and calls turn speech into text on the phone.
- **Nothing in between:** no Telegram, Discord or Slack.

No build carries a server or key, not even Hermsy Dev: every install starts empty, and you scan the QR code (or type the address and key) once.

## Working on the app

You need Flutter (here at `~/development/flutter/bin`, not on `PATH` in every shell) and an Android phone with USB debugging.

There are two flavors, which can be installed side by side:

| Flavor | App | ID | Build |
|---|---|---|---|
| `prod` | Hermsy (Google Play) | `com.illbytes.hermsy_app` | release, signed with the illbytes upload key |
| `dev` | Hermsy Dev | `com.illbytes.hermsy_app.dev` | debug |

```bash
flutter run --flavor dev -d <device>      # plain `flutter run` fails: a flavor is required
flutter test                              # the app's tests
```

Both start with no server. Connect a fresh install with the QR code from `hermes-spawn connect <name>` (for an address you set up yourself, add `--url https://…`); it stays saved in secure storage across updates.

### Useful tools

| | |
|---|---|
| `tool/build_play.sh` | The signed Play bundle, refusing one with `.env` inside or the wrong signer. Publishing steps: [store/README.md](store/README.md). |
| `tool/voice_models_to_phone.py` | Puts the voice models on a phone over USB (`--app <id>` for Hermsy Dev, `--shared` for any build), so nobody downloads 1.5 GB twice. |
| `SHOTS_DIR=… flutter test tool/shots/shots_test.dart` | Design screenshots of the real app, with a scripted Hermes. |
| `SHOTS_DIR=store/screenshots/dark flutter test tool/shots/store_shots_test.dart` | The Play screenshots and feature graphic, with made-up content (`SHOTS_THEME=light` for the light set). |
| `tool/export_plugin.sh <folder>` | Fills the public plugin repo from `server/hermes-plugin`. |

Push needs `android/app/google-services.json` from the illbytes Firebase project (git-ignored; see [store/firebase-setup.md](store/firebase-setup.md)). Without it the app builds and runs, and Settings › Notifications says "Not set up in this build". To test the whole path, run `hermes send -t hermsy "Hello"` on Hermes.

### How it talks to Hermes

- **Chat:** `POST /v1/chat/completions`, streamed, without a model id (Hermes uses its configured model). Each chat keeps its own Hermes session through `X-Hermes-Session-Id`, and each send is one new user line.
- **Titles and history** come from Hermes's sessions API. Titles you haven't renamed follow Hermes's.
- **Calls and dictation** run on the phone: Silero VAD, Parakeet (speech to text) and Kokoro (text to speech), through sherpa-onnx. Calls can use OpenAI or ElevenLabs voices instead, through the plugin, with the keys Hermes already has.
- **The Brief** is the reply of the Hermes cron job named exactly "Hermsy Brief" (JSON; the plugin checks it and repairs a slipped bracket). Refresh runs that job through `/api/jobs`.
- **The plugin** is reached at `POST /api/platforms/hermsy/events` with the same API key, one JSON `op` per request (`hello`, `messages`, `brief`, `register_device`, `voices`, `speak`, `setup`, …).

### Known gap: pictures and audio files

When Hermes makes a picture or a voice file and replies with its path, the app fetches it through `/files/…` and `/audio/…` routes that Caddy serves from the Hermes home folder. `hermes-spawn connect` doesn't add those routes, so for people set up that way, such files don't load (chat, calls and dictation are unaffected). The old manual Caddy routes are in this README's Git history. The better fix is to serve those files through the plugin, with the API key properly checked.

## The server pieces

| Folder | What | Where it runs |
|---|---|---|
| `server/hermes-plugin/` | The Hermsy plugin (2.x): Inbox, Brief, phones, voices, setup; ships a Hermsy skill, a Chief of Staff skill and observer scripts | Inside each person's Hermes. Publish with `tool/export_plugin.sh`, bump `version` in `plugin.yaml` and `core.py` |
| `server/push/` | The push service | Once, on the illbytes VPS: [server/push/README.md](server/push/README.md) |

Python tests (the plugin and the push service):

```bash
python3 -m venv server/.venv && server/.venv/bin/pip install -r server/requirements-dev.txt
server/.venv/bin/python -m pytest -q server/hermes-plugin/tests
server/.venv/bin/python -m pytest -q server/push/tests --rootdir server/push -c server/push/pytest.ini
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `flutter: command not found` | Flutter not on `PATH` | `export PATH="$HOME/development/flutter/bin:$PATH"` |
| `flutter run` fails asking for a flavor | Two flavors exist | `flutter run --flavor dev -d <device>` |
| App **Offline** | Wrong address or key, or Hermes down | Settings › Hermes; open `https://<address>/health` in a browser |
| Settings › Hermes says the plugin is **Not installed** | Plugin missing, disabled, or Hermes older than 0.19 | `hermes plugins list`; `hermes-spawn connect <name> --status` |
| No notifications | Notifications off on the phone, or the plugin can't reach the push service | Settings › Notifications; Hermes's `logs/agent.log` (in its home folder) should show `[Hermsy] Ready` and no `hermsy: waking … failed` lines |
| A Brief arrives as an Inbox message | The job's reply couldn't be read as a Brief | The message says so, with the reply below; check the job's prompt and model |
| `Empty reply` / reset on the API port | Hermes in Docker listening on 127.0.0.1 inside the container | `API_SERVER_HOST=0.0.0.0` in its `.env`, then restart (`hermes-spawn connect` does this) |
| Reply cut off mid-sentence | A proxy closed the long-running stream | Caddy needs `flush_interval -1` and long timeouts (`hermes-spawn connect` sets them) |
| Fingerprint missing | No PIN yet, or none enrolled | Set the PIN in the app; enroll a fingerprint in Android settings |

## Project layout

```text
lib/
  config/      the server address and key type, version
  models/      chat messages, the Brief
  presence/    the edge glow and orb (shaders, palette)
  screens/     PIN, chat, call, Inbox, Brief, Settings, scanning, voice models
  services/    Hermes and plugin clients, push, storage, encryption, delivery
  state/       the chat controller (streaming, sessions)
  voice/       calls, dictation, on-device models, audio routing
  widgets/     the UI kit, glow, setup screens
server/        the Hermsy plugin and the push service
store/         Play listing, policy, data safety, screenshots, graphics
tool/          build, export, screenshots, voice models
docs/          setting up Hermsy for anyone
```

## License

MIT. See [LICENSE](LICENSE).
