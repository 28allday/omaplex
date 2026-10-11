# OmaPlex

Run a Plex Media Server from the Omarchy bar.

OmaPlex puts a Plex icon in your bar. Click it to install Plex, turn it on and
off, choose whether it starts with your computer, see what's playing, scan
your libraries for new files and set up media drives.

The icon is bright while Plex is running, dim while it's stopped, and turns
your theme's accent colour while someone is watching something.

## Install

```bash
git clone https://github.com/28allday/omaplex
cd omaplex
./install.sh
```

This adds the plugin to your bar, then installs Plex Media Server, starts it,
sets it to start every time the computer starts, lets devices on your home
network (and your Tailscale network) reach it, and adds Plex to your app
launcher. It asks for your password when it needs to.

If you add the plugin some other way, for example from the plugin
marketplace, click the icon and choose **Install Plex Media Server**. It
does the same thing.

## First run

1. Plex opens in a web app. Sign in with your Plex account to claim the
   server, and add your libraries.
2. Back in the OmaPlex panel, click **Connect OmaPlex to Plex**. You'll be
   asked for your password once. After that the panel shows what's playing
   and lists your libraries.

## The panel

| Row | What it does |
| --- | --- |
| On/off switch | Starts or stops Plex |
| Start with the computer | Plex starts by itself after a restart |
| Open Plex | Opens the Plex web app |
| Connect | Lets the panel show what's playing and your libraries |
| Add a media drive | Makes a drive open at every start and lets Plex read it |
| Restart Plex | Fixes most hiccups |
| Now playing | Who's watching what, on which device, and how far in |
| Libraries | Click one (or its scan button) to look for new files |
| Remove Plex | Uninstalls Plex. Your media files are never touched |

Mouse: left click opens the panel, right click refreshes it, middle click
opens Plex.

Keys inside the panel: `j`/`k` or arrows to move, `enter` to pick, `p` to
turn Plex on or off, `o` to open Plex, `s` to scan the selected library, `r`
to refresh, `esc` to close.

## Adding a media drive

**Add a media drive** opens a short set-up in a terminal:

- pick the drive (your system drives aren't listed)
- name it, and it opens at `/media/<you>/<name>` every time the computer starts
- if the drive is missing at start-up, your computer still boots normally
- Plex gets permission to read everything on it, including files you add later
- an empty drive can get `Movies`, `TV` and `Music` folders

Then add a library in Plex pointing at that folder.

## Command line

The helper behind the panel works on its own too:

```bash
~/.config/omarchy/plugins/nosignal.plex/bin/omaplex status    # JSON
~/.config/omarchy/plugins/nosignal.plex/bin/omaplex start     # stop, restart
~/.config/omarchy/plugins/nosignal.plex/bin/omaplex boot on   # or off
~/.config/omarchy/plugins/nosignal.plex/bin/omaplex open
```

With the shell running: `omarchy-shell nosignal.plex toggle`, `start`,
`stop`, `restart`, `openWeb`, `status`.

## Privacy and permissions

- OmaPlex only talks to the Plex server on this computer (`127.0.0.1:32400`).
- Starting and stopping Plex goes through the normal system password prompt.
- **Connect** reads this server's own sign-in token from Plex's settings
  (one password prompt) and saves it to `~/.config/omaplex/token`, readable
  only by you. **Remove Plex** deletes it.

## Removing

Click **Remove Plex** in the panel. It stops and uninstalls Plex, closes the
network ports it opened, removes the app launcher, and asks before deleting
Plex's settings and watch history or changing your media drives. Then remove
the panel itself:

```bash
omarchy plugin remove nosignal.plex
```

## Requirements

Omarchy 4. Plex Media Server comes from the AUR package `plex-media-server`.

## License

MIT
