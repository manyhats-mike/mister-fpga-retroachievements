# Changelog

All notable changes to this project will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [0.1.0] - 2026-04-14

Initial release.

### Added
- `scripts/install.sh` — one-command bootstrap that deploys odelot's MiSTer
  binary, modified cores, configuration file, and the toggle scripts to a
  target MiSTer device over FTP.
- `scripts/ra_on.sh` — activate RetroAchievements-enabled cores by stashing
  stock `.rbf` files and symlinking odelot's cores into their place. Also
  restores the modified MiSTer binary at `/media/fat/MiSTer` if `update_all`
  (or anything else) clobbered it.
- `scripts/ra_off.sh` — revert to stock cores. Does not swap the MiSTer
  binary (odelot's binary is backward-compatible with stock cores).
- `scripts/ra_status.sh` — print current mode of the MiSTer binary and every
  core listed in the manifest. Detects drift (symlink + real stock file
  present simultaneously).
- `scripts/ra_update.sh` — auto-discovers odelot's `*_MiSTer` GitHub repos,
  downloads new/updated core `.rbf` files into `/media/fat/_RA_Cores/`, and
  refreshes the MiSTer binary at `/media/fat/_RA_Cores/MiSTer.ra`. Prompts
  before adopting previously-unseen systems.
- `scripts/ra_rollback_binary.sh` — escape hatch that restores the stock
  MiSTer binary from the backup taken at install time, removes the boot
  auto-restore hook, and reboots.
- Boot-time auto-restore hook appended to `/media/fat/linux/user-startup.sh`
  (delimited by `RA_AUTORESTORE_BEGIN` / `RA_AUTORESTORE_END`) that
  re-applies the modified binary on every boot if it has been overwritten.
- Docs: `docs/INSTALL.md`, `docs/USAGE.md`, `docs/HOW-IT-WORKS.md`,
  `docs/CORES.md`.

### Known limitations
- Softcore achievements only. Hardcore mode is disabled in odelot's binary
  because no anti-tamper mechanism exists on MiSTer yet. Unlocks count on
  the softcore leaderboard and **do not** count toward hardcore rankings.
- Supported systems are limited to the cores odelot has modified: NES,
  SNES, Genesis/Mega Drive, Master System/Game Gear, Game Boy/GBC, N64,
  PSX. Other systems (Atari 2600, Intellivision, arcade, etc.) have no
  RetroAchievements support on MiSTer.
- Credentials are stored in plaintext at `/media/fat/retroachievements.cfg`
  because the SD card is FAT32 and cannot enforce Unix permissions.
