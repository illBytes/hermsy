# Hermsy for anyone: how it fits and how to set someone up

## How it fits

```
Their phone (Hermsy) ──HTTPS + their API key──▶ Their Hermes (API server)
                                                 ├─ chat, calls, titles, jobs     (Hermes itself)
                                                 └─ /api/platforms/hermsy/events  (hermsy plugin)
                                                      Inbox, Brief, phones, voices, setup

Their Hermes ──"wake <push token>"──▶ push.hermsy.illbytes.com ──▶ Google FCM ──▶ their phone
                                       (illbytes runs this once)       push carries nothing;
                                                                       the phone asks its Hermes
```

- Each person runs only their own Hermes, with the plugin installed. Nothing else: no relay, no extra port, no proxy route.
- illbytes runs one thing for everyone: the push service. It holds the Firebase key, because Google only takes pushes for the Play app from its publisher. It never sees message text, titles, anyone's Hermes address or key.

## Once, for illbytes

1. **Push service.** Add a DNS A record `push.hermsy.illbytes.com → <the server's IP>`, then follow `server/push/README.md`: Docker, the Firebase key, and a Caddy site. Check it with `curl https://push.hermsy.illbytes.com/health`.
2. **Plugin repo.**
   1. Create the public GitHub repo `illbytes/hermsy-hermes`. Choose a licence (MIT is the usual choice for Hermes plugins).
   2. Run `tool/export_plugin.sh ~/Code/hermsy-hermes` to fill it from `server/hermes-plugin/hermsy`.
   3. Commit and push.
   4. Check from a clean Hermes: `hermes plugins install illbytes/hermsy-hermes --enable`.
3. **Play.**
   - Publish the privacy policy (`store/privacy-policy.md`, which now mentions the push service) at a public URL.
   - Use the updated data-safety answers (`store/data-safety.md`).
   - For Google's reviewers, the "App access" test server needs the plugin too.
4. **Later, optional.** Ask for `hermsy` to be listed in the Hermes plugin catalog. Then the install is `hermes plugins install hermsy`.

## For each person

**With hermes-spawn (the simple way):**
1. `curl -fsSL https://raw.githubusercontent.com/oscarfrank/hermes-spawn/main/install.sh | bash`
2. `hermes-spawn hermes`: creates Hermes, then offers the phone setup. Press Enter.
3. Install Hermsy and tap **Scan QR code**.

That covers the API server, the plugin, an HTTPS address (Caddy with an automatic sslip.io address, Cloudflare Tunnel or Tailscale), and the key, all checked end to end. For an existing instance: `hermes-spawn connect <name>`.

**Without hermes-spawn**, what they need:
- Hermes 0.19 or newer.
- The API server on (`API_SERVER_ENABLED=true` and a strong `API_SERVER_KEY`).
- The API server reachable from their phone over HTTPS: Caddy with a domain, a Cloudflare tunnel, or Tailscale with HTTPS. This is the only part that takes real work, and anyone already using a Hermes client has done it.

What they do (the plugin README says the same):
1. `hermes plugins install illbytes/hermsy-hermes --enable`, then restart Hermes.
2. Install Hermsy, create a PIN, enter the Hermes address and API key.
3. Settings → Hermes:
   - check it shows **Connected**
   - tap **Set up** on the Hermsy Brief and the Chief of Staff
   - allow notifications

A message you can send someone:

> Hermsy is a phone app for your Hermes. On the machine running Hermes, run
> `hermes plugins install illbytes/hermsy-hermes --enable` and restart
> Hermes. Then install Hermsy from Play, enter your Hermes address (HTTPS)
> and your API_SERVER_KEY, and in Settings → Hermes tap Set up for the Brief
> and the Chief of Staff. To test: `hermes send -t hermsy "Hello"`.

## Helping someone when it doesn't work

| They see | Check |
|---|---|
| Hermsy can't save the server | The address must be HTTPS and reachable from the phone (try it in the phone's browser: `/health`). The key is `API_SERVER_KEY`. |
| Settings → Hermes says **Not installed** | `hermes plugins list` shows `hermsy` enabled? Hermes restarted since? Hermes 0.19+? |
| Connected, but no notifications | Notifications allowed on the phone? Hermes's `logs/agent.log` has `[Hermsy] Ready`, and no `hermsy: waking … failed` lines? `curl https://push.hermsy.illbytes.com/health` answers? Messages still appear when they open the Inbox. |
| No Brief | `hermes cron list` shows "Hermsy Brief"? Tap Refresh in the Brief: it runs the job. A bad reply lands in the Inbox instead. |
| Chief of Staff never texts | That's often right: it stays silent unless something matters, at most 3 a day, never 22:00–07:00. `hermes cron run <id>` in the morning slot always produces a text. |
| Cloud voices missing | Hermes needs `OPENAI_API_KEY` or `ELEVENLABS_API_KEY`; Settings → Hermes lists what it found. |

## Shipping updates

- **Plugin:**
  1. Change `server/hermes-plugin/hermsy` and bump `version` in `plugin.yaml`.
  2. Export to the repo and push.
  3. People update with `hermes plugins update hermsy` and restart Hermes.

  Their skills, scripts and standing orders are never overwritten. A change to those reaches only new installs, so mention it in the release notes if people should copy it.
- **App:** through Play as usual. The app asks the plugin (`hello`) what it supports, so add features there in a way an older plugin can simply not offer.
- **Push service:** `docker compose up -d --build` on the VPS. Keep `/v1/wake` stable: every plugin out there calls it.
