# OmaPlex

**Your own Plex Media Server, run from the Omarchy bar.**

OmaPlex sets up Plex Media Server on your computer and keeps it one click
away. Turn it on and off, have it start with your computer, see who's
watching what, look for new films and shows, and add the drives your media
lives on, all without opening a terminal or typing a command.

<p align="center">
  <img src="screenshots/panel.png" alt="The OmaPlex panel: Plex running, two streams playing, and four libraries" width="440">
</p>

## What you get

- **One-click install.** Installs Plex Media Server, starts it, and sets it to
  start every time your computer does.
- **On and off from the bar.** Start or stop Plex, and choose whether it
  starts with your computer.
- **Now playing.** See what's being watched, by whom, on which device, how far
  in, and whether Plex is converting the video or playing it as it is.
- **Libraries.** See every library and when it was last checked. Click one to
  look for new files straight away.
- **Media drives.** Set up a drive for your films, TV and music. It opens
  every time your computer starts and Plex can read everything on it.
- **The Plex icon tells you how things are.** Bright while Plex is running, dim
  while it's stopped, and your theme's accent colour while someone is
  watching something.

## Install

You need Omarchy 4.

```bash
git clone https://github.com/28allday/omaplex
cd omaplex
./install.sh
```

This adds OmaPlex to your bar, then installs Plex. When it asks for your
password, it's the one you log in with. It:

1. installs Plex Media Server
2. starts it now, and every time your computer starts
3. lets your TV, phone and other computers at home (and on your Tailscale
   network) find it
4. asks whether this computer is a **dedicated Plex server** (see below)
5. adds Plex to your app launcher
6. offers to set up a media drive
7. opens Plex so you can sign in

Already added OmaPlex some other way? Click the Plex icon in the bar and
choose **Install Plex Media Server**. It does exactly the same thing.

<p align="center">
  <img src="screenshots/first-run.png" alt="OmaPlex before Plex is installed, offering to install it" width="440">
</p>

## Getting started

1. **Claim your server.** When Plex opens, sign in with your Plex account (a
   free one is fine). This makes the server yours. Then add your libraries:
   point Plex at the folders that hold your films, TV and music.
2. **Connect OmaPlex.** Click the Plex icon and choose **Connect OmaPlex to
   Plex**. You'll be asked for your password once. After that the panel shows
   what's playing and lists your libraries.

<p align="center">
  <img src="screenshots/connect.png" alt="OmaPlex with Plex running, ready to connect" width="440">
</p>

## Using the panel

Click the Plex icon in the bar to open the panel.

| | |
| --- | --- |
| **The switch at the top** | Turns Plex on or off |
| **Start with the computer** | When on, Plex starts by itself after a restart |
| **Open Plex** | Opens Plex, where you watch things and change settings |
| **Connect OmaPlex to Plex** | Shows what's playing and your libraries in the panel (only needed once) |
| **Dedicated server** | Keeps this computer awake for Plex (see below) |
| **Add a media drive** | Sets up a drive for your media (see below) |
| **Restart Plex** | Turns Plex off and on again, which fixes most hiccups |
| **Now playing** | Who's watching what, on which device, and how far in |
| **Libraries** | Click a library, or its ↻ button, to look for new files now |
| **Remove Plex** | Uninstalls Plex. Your media files are never touched |

Turning Plex on or off, and changing whether it starts with your computer,
asks for your password. That's your computer checking it's really you.

**Mouse:** left click opens the panel, right click refreshes it, middle click
opens Plex.

**Keyboard,** with the panel open:

| Key | Does |
| --- | --- |
| `j` `k` or arrows | Move up and down |
| `Enter` | Choose the highlighted row |
| `p` | Turn Plex on or off |
| `o` | Open Plex |
| `s` | Look for new files in the highlighted library |
| `r` | Refresh |
| `Esc` | Close |

## Dedicated server

If the computer is mainly there to run Plex, say yes when the install asks
"Is this computer a dedicated Plex server?" (or choose **Dedicated server**
in the panel later). OmaPlex then:

- **stops the computer from going to sleep,** even from the menu, because
  Plex disappears from your TV and phone while it sleeps. The screen still
  locks and switches off as usual.
- **sets the power profile to Balanced** while plugged in: full speed when
  Plex is busy, less power when nobody is watching.

On a laptop the question defaults to no. Choosing **Dedicated server** again
turns it off and puts your previous power profile back, and so does
**Remove Plex**.

## Adding a media drive

Plug in your drive, then choose **Add a media drive**. A window opens and
walks you through it:

1. **Pick the drive.** Your computer's own drives aren't listed, so you can't
   pick the wrong one.
2. **Name it.** The drive's own name is suggested. It will appear in your file
   manager under that name, and open at `/media/<your username>/<name>`.
3. **Confirm.** From now on the drive opens every time your computer starts.
   If it isn't plugged in, your computer still starts normally.
4. **Plex gets permission to read it,** including anything you add later.
   Nothing on the drive is moved, renamed or deleted.
5. **Empty drive?** You're offered `Movies`, `TV` and `Music` folders to get
   started.
6. **Plex's artwork.** You're asked whether to keep Plex's artwork, posters
   and video previews on this drive. For a big collection these can take many
   gigabytes, so this is worth saying yes to if your computer's own drive is
   small. They go in a `Plex Artwork` folder on the drive. Plex's library
   database stays on your computer, so Plex stays quick, and Plex won't start
   without the drive plugged in. This is only offered on Linux-formatted
   drives (ext4, btrfs or xfs), and only if the drive doesn't already have
   something called `Plex Artwork` on it.

7. **Let it sleep.** A hard drive can stop spinning while nobody is watching
   anything: after 30 minutes (recommended), an hour, two hours, or never.
   That saves power and wear. The cost is a pause of a few seconds when
   someone presses play while it's asleep. If the drive is a pool of several
   disks, every disk gets the same timer. Solid-state drives don't spin, so
   they aren't asked.

   Many NAS drives (WD Red among them) ignore their own sleep timer, so
   OmaPlex doesn't rely on it: a small background service notices when a
   disk has had nothing to do for the time you chose and tells it to sleep.
   Checking on the disks never wakes them.

   OmaPlex also stops two things that keep a drive awake for no reason: it
   opens the drive so that playing a file doesn't write to it, and it sets
   Plex to look for new files as they arrive instead of re-reading your
   libraries on a timer.

Then open Plex, add a library, and point it at the drive: choose the folder
under `/media/<your username>/<name>`.

Choosing **Add a media drive** for a drive that's already set up skips
straight to the artwork and sleep questions, so you can change those later.

Plex also runs heavier jobs, like making video previews, in a maintenance
window overnight (2–5 am unless you change it in Plex → Settings →
Scheduled Tasks). The drive wakes for those and sleeps again afterwards.

Drives formatted for Windows or a Mac (exFAT or NTFS) work as they are. If you
also use the drive on another computer, nothing changes for it there.

## Removing Plex

Choose **Remove Plex** in the panel. It stops and uninstalls Plex, closes the
network access it opened, removes it from your app launcher, and if this
computer was set up as a dedicated server, lets it sleep again and restores
your power profile. Before going
further it asks whether to:

- **delete Plex's settings, watch history and artwork** (say no if you might
  reinstall: Plex will pick up where it left off)
- **stop opening your media drives automatically**

If Plex's artwork was on a media drive, deleting Plex's settings deletes the
`Plex Artwork` folder there too. The drive-sleep service is removed as well.

Your media files are never touched.

To remove the OmaPlex icon itself:

```bash
omarchy plugin remove nosignal.plex
```

## Updating

```bash
omarchy plugin update nosignal.plex
```

Plex Media Server itself updates whenever you update Omarchy.

## Privacy

- OmaPlex only ever talks to the Plex server on your own computer. It doesn't
  contact any website or online service.
- **Connect** reads your server's own sign-in key from Plex's settings (that's
  the one password prompt) and keeps it in `~/.config/omaplex/token`, a file
  only you can read. **Remove Plex** deletes it.

## Troubleshooting

**The panel says "Starting…" for a while.** Plex takes a few seconds to wake
up after it starts, a bit longer the first time. Give it a moment.

**Plex can't see my files.** In Plex, pick your media from
`/media/<your username>/<drive name>`. A drive your file manager opened by
itself appears under `/run/media/…` instead, and that folder is private to
you, so Plex can't look inside. **Add a media drive** fixes this. If the drive
was set up with **Add a media drive**, run it again for that drive. Otherwise make sure the folder is one
Plex is allowed to read. Folders inside your home folder are private to you
by default, so a separate drive is the easiest place for media.

**"Plex no longer accepts the saved sign-in."** This happens if you sign out
of Plex or reset the server. Choose **Connect** again.

**My drives don't go to sleep.** They sleep only after the time you chose
with nothing at all happening on them, so anything that reads the drive
starts the count again: someone watching, browsing Plex while its artwork is
on that drive, or Plex's overnight jobs. In the first few nights after adding
a big library, Plex works through every film, song and show (loudness,
previews and so on), and the drives stay busy until it's finished. To see
when the drives were last put to sleep:

```bash
journalctl -u omaplex-spindown
```

Lines like "asleep after 30 min with nothing to do" mean it's working. To
change the time, or switch it off, choose **Add a media drive** and pick the
same drive again.

**My TV or phone can't find the server.** Check that it's on the same network
as your computer, and that Plex is running (the icon is bright, not dim).

## For the curious

The panel is driven by a small helper you can use yourself:

```bash
~/.config/omarchy/plugins/nosignal.plex/bin/omaplex status    # current state, as JSON
~/.config/omarchy/plugins/nosignal.plex/bin/omaplex start     # also: stop, restart
~/.config/omarchy/plugins/nosignal.plex/bin/omaplex boot on   # or off
~/.config/omarchy/plugins/nosignal.plex/bin/omaplex open
```

From scripts, while the desktop is running: `omarchy-shell nosignal.plex
toggle` (or `start`, `stop`, `restart`, `openWeb`, `connect`, `status`).

Plex Media Server comes from the Arch User Repository package
`plex-media-server`.

## License

MIT
