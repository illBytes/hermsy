# Hermsy push service

The one piece illbytes runs for everyone.

Google only delivers pushes to the Hermsy app when they're signed with the illbytes Firebase project's key. Each person's Hermes (the hermsy plugin) therefore asks this service to wake their phone.

- The service gets a phone's push token and nothing else.
- It sends a push that carries only `{"type": "wake"}`.
- The phone then asks its own Hermes what is new.

## What it keeps

- **Nothing on disk.**
- **In memory:** rate-limit counters keyed by hashes of tokens and sender addresses.
- **No access log.** `/health` reports totals only.

## API

`POST /v1/wake {"token": "<FCM token>"}`

| Answer | Meaning | The plugin |
|---|---|---|
| 200 `{"ok": true}` | Sent | done |
| 410 | The app is gone from that phone | forgets the phone |
| 429 | Too many wakes for this phone (30 per 10 min) or sender (600 per 10 min) | retries later |
| 503 | Google is busy | retries later |
| 400 / 422 | A token Google refuses / nonsense | gives up |

## Deploy (on the VPS)

1. **DNS:** an A record for `push.hermsy.illbytes.com` pointing at the server, set to **DNS only** (grey cloud) in Cloudflare. Cloudflare's free edge certificate covers `*.illbytes.com` but not two levels down, so with the proxy on, every request fails its TLS handshake at Cloudflare. Caddy has its own certificate for the name. If you ever turn the proxy on (with a certificate that covers the name), the service rate-limits by `CF-Connecting-IP` by itself.

2. **Code and key:**

   ```bash
   mkdir -p /root/hermsy-push/secrets
   # from your machine: rsync -a server/push/ root@<server>:/root/hermsy-push/ --exclude tests
   # then put the illbytes Firebase service account key (from Firebase console ›
   # Project settings › Service accounts) at /root/hermsy-push/secrets/firebase.json
   chmod 600 /root/hermsy-push/secrets/firebase.json
   ```

   It must be the same Firebase project the app is built with (`android/app/google-services.json`).

3. **Start:**

   ```bash
   cd /root/hermsy-push && docker compose up -d --build
   curl -s 127.0.0.1:8651/health
   ```

4. **Caddy**: add a site and reload:

   ```caddy
   push.hermsy.illbytes.com {
       reverse_proxy 127.0.0.1:8651
   }
   ```

   ```bash
   caddy reload --config /etc/caddy/Caddyfile   # or: systemctl reload caddy
   curl -s https://push.hermsy.illbytes.com/health
   ```

   The service takes the sender from `CF-Connecting-IP` if present, else the last `X-Forwarded-For` entry, which Caddy appends. The port is bound to loopback, so Caddy is the only way in. A sender who fakes either header only moves itself to another rate-limit bucket; each phone keeps its own limit.

## Tests

With the Python test setup from the main README (`server/.venv`):

```bash
server/.venv/bin/python -m pytest -q server/push/tests --rootdir server/push -c server/push/pytest.ini
```
