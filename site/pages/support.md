# Support

Email **[support@illbytes.com](mailto:support@illbytes.com)**, or open an issue on [GitHub](https://github.com/illBytes/hermsy/issues). Please don't send your API key.

## Common problems

| You see | Try |
|---|---|
| Hermsy can't save the server | The address must start with `https://` and be reachable from the phone: open `https://<your address>/health` in the phone's browser. The key is Hermes's `API_SERVER_KEY`. |
| Settings › Hermes says the plugin is **Not installed** | Run `hermes plugins list` where Hermes runs: `hermsy` should be enabled. Restart Hermes after installing it. It needs Hermes 0.19 or newer. |
| No notifications | Allow notifications for Hermsy in Android settings. Messages still reach the Inbox whenever you open the app. With hermes-spawn, `hermes-spawn connect <name> --status` checks everything. |
| No Brief | Tap **Set up** for the Brief in Settings › Hermes, or check that Hermes has a job named "Hermsy Brief". |
| Replies stop mid-sentence | Your proxy closes long streams: give it long timeouts (`hermes-spawn connect` does this for Caddy). |
| The Chief of Staff never texts | Often that's right: it stays quiet unless something matters, at most three times a day, never at night. |

## Reporting a reply

Every reply, Inbox message and Brief can be reported as offensive or wrong: long-press it and choose **Report**. Hermsy opens an email to illbytes with the reason and the text. It reaches us only if you send it.

## Your data

Delete a chat or an Inbox message in Hermsy to remove it from your phone; uninstalling Hermsy removes everything it stored. What Hermes keeps is on your own server, under your control. See the [privacy policy](../privacy/).
