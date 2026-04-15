# Install guide

## Requirements

On your **workstation** (the machine you'll run `install.sh` from):

- `bash`, `curl`, `unzip`, `awk` — standard on Linux, macOS, and WSL.
- Network access to github.com and to your MiSTer.

On the **MiSTer**:

- FTP server enabled. This is the MiSTer factory default; if you changed
  it, re-enable it via `Scripts/ftp.sh` or your MiSTer config.
- Known FTP credentials. MiSTer ships with `root` / `1`.
- `/media/fat/` should look like a normal MiSTer install (an `_Console`
  folder exists, `MiSTer` binary is present, etc.).

## Step 1: clone and configure

```sh
git clone https://github.com/<your-org>/mister-fpga-retroachievements.git
cd mister-fpga-retroachievements
chmod +x scripts/*.sh
```

Decide which host the MiSTer is on. You can check with `ping <hostname>` or
look it up in your router's DHCP leases.

## Step 2: run the installer

```sh
MISTER_HOST=192.168.1.42 ./scripts/install.sh
```

Optional environment variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `MISTER_HOST` | (required) | IP or hostname of the MiSTer |
| `MISTER_USER` | `root` | FTP username |
| `MISTER_PASS` | `1` | FTP password |
| `STAGING_DIR` | `./staging` | Local working directory for downloads |

The installer will:

1. Preflight-check FTP connectivity.
2. Download odelot's latest `Main_MiSTer` release (a zip with the MiSTer
   binary, `achievement.wav`, and a default `retroachievements.cfg`).
3. Enumerate every `odelot/*_MiSTer` repo on GitHub and download the
   latest release `.rbf` from each repo that has one.
4. Capture the current `/media/fat/MiSTer` as `/media/fat/MiSTer.stock`
   so you have a verified rollback copy.
5. Upload everything to `/media/fat/_RA_Cores/`, install `RA_Helper.sh`
   (the dialog menu) to `/media/fat/Scripts/` as the single MiSTer-menu
   entry for this tool, install the five toggle scripts under the
   hidden `/media/fat/Scripts/.ra/` directory, and append the boot
   auto-restore hook to `/media/fat/linux/user-startup.sh`.

Expected runtime: two to five minutes depending on network speed. The
core `.rbf` files total ~25 MB.

## Step 3: set your RetroAchievements credentials

SSH or serial into the MiSTer. Edit the config:

```sh
vi /media/fat/retroachievements.cfg
```

Replace the placeholders:

```ini
username=YOUR_RA_USERNAME
password=YOUR_RA_ACCOUNT_PASSWORD
```

The `password` field is your **account password**, not a Web API key.
odelot's binary calls `rc_client_begin_login_with_password()` and
exchanges it for a session token on first login.

Security notes:

- The card is FAT32; you cannot enforce `chmod 600`. Anyone with physical
  or FTP access can read this file.
- If you're cautious, rotate your RA password after the initial login;
  the cached session token is what subsequent plays use, so the password
  only really needs to be right once.

## Step 4: reboot and verify

```sh
reboot
```

When the MiSTer is back up, use the menu from the MiSTer main menu:
**Scripts → RA_Helper**.

Pick **Status**. You should see:

```
/media/fat/MiSTer : RA (odelot)
CORE         STATE   DETAILS
NES          STOCK   NES_20260101.rbf
SNES         STOCK   SNES_20260325.rbf
...
```

The binary is now the odelot build; cores are still stock. Back in the
menu, pick **Turn RA cores ON**, then re-run **Status** — every core
should now show `RA`.

## Step 5: test with a real game

Load a supported system (NES is a reliable first test), launch any game
with a published RA set (Super Mario Bros works), and watch for the OSD
popup announcing the achievement set. Trigger a known-early achievement
and confirm the unlock toast fires.

## Troubleshooting

**Installer fails at preflight with `cannot list /media/fat/`.**
Check that FTP is enabled on the MiSTer. Try `curl -v -u root:1
ftp://<host>/` from your workstation.

**Status reports `UNKNOWN` for the binary.**
The live binary doesn't match either the captured `MiSTer.stock` or the
staged `MiSTer.ra`. Run **Update odelot assets** from the menu to
refresh `MiSTer.ra`, then reboot so the boot hook re-applies it.

**Status reports `DIRTY` for a core.**
There's both a symlink and a real stock file for the same system — this
happens if `update_all` dropped in a newer stock `.rbf` while RA was on.
Run **Turn RA cores ON** again; it will re-stash the new stock file.

**OSD popup never appears on a supported system.**
Verify the core is actually the RA build: **Status** should show `RA`
for that core. If it's `RA` but no popup, check credentials by viewing
`/media/fat/retroachievements.cfg` and ensuring the username and password
are correct. odelot's binary logs to the MiSTer's `logread`; look for
lines tagged `RA_LOG` for clues.
