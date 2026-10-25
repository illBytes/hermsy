# Delete your Hermsy data

Hermsy, the app by illbytes, has no accounts and no Hermsy cloud. Your data lives in two places you control: your phone, and your own Hermes server. illbytes keeps nothing about you, so there is nothing to request from us.

## On your phone

| Data | How to delete it |
|---|---|
| A chat | Open the side menu and swipe the chat left, or hold it and choose **Delete**. |
| An Inbox message | In the Inbox, swipe the message away. |
| Everything Hermsy stored: chats, the Inbox, the Brief, your settings, your PIN, the saved server address and key, downloaded voice models | Uninstall Hermsy, or Android **Settings › Apps › Hermsy › Storage › Clear storage**. |

Deleted data is gone straight away. Hermsy's data is not included in Android backups, so no copy is left in a backup either.

## On your Hermes server

Your conversations and what Hermes sends you are kept by your own Hermes server, which you or your host run. Delete them there:

- **Conversations:** delete them in Hermes (for example with its sessions tools or dashboard), or remove Hermes's data folder.
- **Inbox messages, Briefs and your phone's push token**, kept by the Hermsy plugin: delete the plugin's folder, `hermsy/` in Hermes's home folder. Messages older than 60 days are removed automatically.
- **Your phone's push token** is forgotten by the plugin on its own after you uninstall Hermsy: the next time Hermes tries to wake the phone, Google reports the app gone. (Turning notifications off in Android stops them showing.)

## illbytes' push service

To wake your phone for a notification, your Hermes sends your phone's push token to illbytes' push service, which passes it to Google once and does not store it. It keeps no record of tokens or of who was woken, so nothing remains to delete.

Questions: [support@illbytes.com](mailto:support@illbytes.com). See also the [privacy policy](../privacy/).
