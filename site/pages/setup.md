# Set up Hermsy

Hermsy connects to your own [Hermes Agent](https://hermes-agent.nousresearch.com/). You need Hermes 0.19 or newer, reachable from your phone over HTTPS.

## With hermes-spawn (the simple way)

If you run Hermes in Docker with [hermes-spawn](https://github.com/oscarfrank/hermes-spawn):

1. Update hermes-spawn and connect your instance:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/oscarfrank/hermes-spawn/main/install.sh | bash
   hermes-spawn connect <name>
   ```

   It switches on Hermes's API server, installs the Hermsy plugin, gives Hermes an HTTPS address, checks it all, and shows a QR code. For the address, it suggests the right option for your machine:

   | | Best for | You do |
   |---|---|---|
   | **Caddy** | A server with a public IP | Nothing: an automatic address. Or your own domain, with one DNS record. |
   | **Cloudflare Tunnel** | A machine at home | Click one login link (your domain is on Cloudflare). |
   | **Tailscale** | Keeping Hermes private | Click one login link; install Tailscale on your phone. |

   Already reach Hermes through your own proxy? Use `hermes-spawn connect <name> --url https://your-address`.

2. Install Hermsy, create a PIN, and tap **Scan QR code**.

3. In Hermsy, **Settings › Hermes**: tap **Set up** for the Brief and the Chief of Staff.

New instances offer this at the end of `hermes-spawn <name>`.

## Any other Hermes

1. **Switch on the API server** in Hermes's `.env`: `API_SERVER_ENABLED=true` and a long random `API_SERVER_KEY` (for example from `openssl rand -hex 32`). In Docker, also `API_SERVER_HOST=0.0.0.0`.
2. **Make it reachable over HTTPS** from your phone: a reverse proxy such as Caddy with your own domain, a Cloudflare Tunnel, or Tailscale. Streaming replies need long timeouts (for Caddy: `flush_interval -1`).
3. **Install the Hermsy plugin** where Hermes runs, then restart Hermes:

   ```bash
   hermes plugins install illbytes/hermsy-hermes --enable
   ```

4. In Hermsy, enter the address and the API key in **Settings › Hermes**.

Chat and calls work without the plugin. The Inbox, notifications, the Brief, cloud voices and the Chief of Staff need it. More in the [plugin's README](https://github.com/illBytes/hermsy-hermes).

## Check it

On Hermes, send yourself something:

```bash
hermes send -t hermsy "Hello from Hermes"
```

It should arrive as a notification. If it doesn't, see [Support](../support/).
