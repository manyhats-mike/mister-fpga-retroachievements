# mister-fpga-retroachievements

A management toolkit for deploying and toggling [odelot's RetroAchievements
integration](https://github.com/odelot/Main_MiSTer) on a
[MiSTer FPGA](https://misterfpga.org/) without ever displacing the stock
cores that `update_all` manages.

## What this is

odelot's fork of the MiSTer `Main_MiSTer` binary adds RetroAchievements
support by reading the FPGA core's emulated RAM via DDRAM every frame and
evaluating [rcheevos](https://github.com/RetroAchievements/rcheevos)
conditions. It requires both a modified MiSTer main binary and a modified
`.rbf` per supported system.

Running odelot's fork naively conflicts with the usual MiSTer update
workflow — `update_all` pulls stock cores and the stock main binary from
[MiSTer-devel](https://github.com/MiSTer-devel), happily overwriting the
RA-enabled builds.

This repo fixes that conflict. It:

- Keeps `update_all` fully in charge of stock cores. Nothing in `_Console`,
  `_Computer`, or `_Other` is altered in the off state.
- Stages odelot's modified binary + cores in a parallel folder, `_RA_Cores`.
- Provides a menu (`RA_Helper` in the MiSTer Scripts browser) to toggle RA
  on or off, check status, update odelot's assets from GitHub, view the
  changelog, self-update the toolkit, roll back the main binary in
  emergencies, or fully uninstall everything in one shot.
- Installs a tiny hook in `user-startup.sh` so the modified binary survives
  any future `update_all` run: if it gets clobbered, the next boot restores
  it automatically.
- **Auto-discovers** new systems odelot publishes — run `ra_update.sh`
  and any new `*_MiSTer` repo with a `.rbf` release prompts for adoption.

## Supported systems

Whatever odelot has published. At v0.1.0: **NES, SNES, Genesis / Mega Drive,
Master System / Game Gear, Game Boy / Game Boy Color, N64, PSX**. GBA and
Neo Geo repos exist in odelot's profile but have no releases yet; the
updater will pick them up when they ship.

> Atari 2600, Intellivision, arcade, Saturn, Sega CD, and any other system
> not in the list above have **no RetroAchievements support on MiSTer today**,
> from anyone. This toolkit cannot add support that doesn't exist upstream.

## Important caveats

- **Softcore only.** odelot's integration explicitly disables hardcore mode
  because there is no anti-tamper mechanism on MiSTer yet. Unlocks land on
  the softcore leaderboard and **do not** count for hardcore ranking.
- **Experimental upstream.** odelot describes the integration as
  proof-of-concept. Expect occasional regressions between releases. The
  included `ra_rollback_binary.sh` reverts to the stock upstream binary.
- **Plaintext credentials.** The SD card is FAT32, which cannot enforce
  Unix permissions. `/media/fat/retroachievements.cfg` is world-readable
  to anyone with physical or FTP access to the card.

## Quick start

From your workstation (Linux / macOS / WSL) with `curl` and `unzip`
installed:

```sh
git clone https://github.com/manyhats-mike/mister-fpga-retroachievements.git
cd mister-fpga-retroachievements
chmod +x scripts/*.sh
MISTER_HOST=192.168.1.42 ./scripts/install.sh
```

Then on the MiSTer (SSH / console):

```sh
# 1. edit your credentials (password field is your RA ACCOUNT password,
#    not a Web API key)
vi /media/fat/retroachievements.cfg

# 2. reboot once so the modified binary takes over
reboot
```

After reboot, open the MiSTer main menu → **Scripts → RA_Helper** and
use **Status** then **Turn RA cores ON**. Launch any supported system's
game and look for the RA achievement set popup in the OSD.

## Upgrading from v0.2.x

If you already have a v0.2.x install on your MiSTer, just re-run the
installer once from your workstation to land the new files:

```sh
cd mister-fpga-retroachievements
git pull
MISTER_HOST=192.168.1.42 ./scripts/install.sh
```

This is **safe and idempotent**:

- Your credentials (`/media/fat/retroachievements.cfg`) are left alone.
- Your RA cores, manifest, and `MiSTer.stock` backup are not touched.
- The boot hook is not re-appended (it's already there).
- Only the helper scripts, menu, `VERSION`, and `CHANGELOG.md` are refreshed.

No reboot required. Once it finishes, open the **RA_Helper** menu —
you'll see the new **Updates ▸** submenu and **Uninstall toolkit** entry.

From v0.3.0 onward you can skip the workstation step entirely and use
**Updates ▸ Update toolkit (scripts)** in the menu to pull future
releases directly from GitHub.

## Daily use

Primary entry point: `RA_Helper` in the MiSTer Scripts menu.

| Menu action | What it does |
|-------------|--------------|
| Status | Show current RA / stock state for every core + the main binary |
| Turn RA cores ON | Activate RA-enabled cores (idempotent) |
| Turn RA cores OFF | Revert to stock cores (main binary stays — no reboot) |
| Updates ▸ Update RA cores (odelot) | Fetch latest odelot binary + cores |
| Updates ▸ Update toolkit (scripts) | Pull the latest release of this toolkit from GitHub |
| Updates ▸ View changelog | Read CHANGELOG.md right on the device |
| Rollback main binary | Emergency restore of stock MiSTer binary (reboots) |
| Uninstall toolkit | Wipe everything this toolkit installed (reboots) |

"Turn RA cores ON" is idempotent — run it again after `update_all` pulls
a newer stock core and it will re-stash and re-symlink the fresh file.

Direct CLI fallback (scripting, SSH sessions): the helpers are in
`/media/fat/Scripts/.ra/ra_{on,off,status,update,rollback_binary,uninstall,self_update}.sh`.
See [docs/USAGE.md](docs/USAGE.md) for details.

## Repository layout

```
.
├── README.md
├── LICENSE
├── CHANGELOG.md
├── VERSION
├── scripts/
│   ├── install.sh              # bootstrap onto a MiSTer over FTP
│   ├── ra_helper.sh            # dialog menu (deployed as RA_Helper.sh)
│   ├── ra_on.sh                # activate RA mode
│   ├── ra_off.sh               # revert to stock cores
│   ├── ra_status.sh            # print current state
│   ├── ra_update.sh            # refresh odelot assets from GitHub
│   ├── ra_rollback_binary.sh   # escape hatch - restore stock main binary
│   ├── ra_uninstall.sh         # full wipe of this toolkit
│   ├── ra_self_update.sh       # pull the latest release from GitHub
│   └── release.sh              # maintainer: cut a GitHub release
├── config/
│   ├── retroachievements.cfg.example
│   └── manifest.example
└── docs/
    ├── INSTALL.md              # detailed install walk-through
    ├── USAGE.md                # operational recipes
    ├── HOW-IT-WORKS.md         # what the scripts actually do
    └── CORES.md                # per-system notes
```

## How it stays compatible with `update_all`

1. odelot's cores live in `/media/fat/_RA_Cores/<Name>.rbf`, a folder
   `update_all` does not manage.
2. When RA mode is on, stock `.rbf` files in `_Console` are moved aside to
   `_Console/.ra_stash/`, and a symlink takes their place pointing to the
   matching `_RA_Cores/<Name>.rbf`. Any launcher that resolves the core
   path (Zaparoo, NFC triggers, MGL files, main menu) follows the symlink
   transparently.
3. odelot's modified main binary at `/media/fat/MiSTer` is backward-
   compatible with stock cores (RA logic only fires when a core exposes
   RAM to DDRAM), so it stays resident permanently. The boot hook
   re-applies it if `update_all` ever replaces it with upstream.

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) for the full picture.

## Credits

- The actual RetroAchievements integration, modified MiSTer main binary,
  and modified cores are [odelot](https://github.com/odelot)'s work. This
  toolkit is a deployment wrapper around those releases.
- [RetroAchievements](https://retroachievements.org/) for the service and
  the [rcheevos](https://github.com/RetroAchievements/rcheevos) SDK.
- The MiSTer FPGA project and every core author whose work odelot forked.

## License

MIT — see [LICENSE](LICENSE). Note that odelot's binaries and cores are
separate works under their own licenses; this repo does not redistribute
them. The scripts here fetch them from their official GitHub releases at
install time.

## Contributing

Issues and PRs welcome. For adding support for a new odelot-published
system, you usually do not need to change code — `ra_update.sh` auto-
discovers it and prompts before adopting. If the new system needs a
different stock folder than `/media/fat/_Console` (for example a home
computer system), fix the line in `/media/fat/_RA_Cores/.manifest`
after first adoption, or send a PR to update `default_stock_folder_for`
in `ra_update.sh`.
