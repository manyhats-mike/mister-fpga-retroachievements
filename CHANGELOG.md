# Changelog

All notable changes to this project will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [SemVer](https://semver.org/).

## [0.3.0] - 2026-04-21

### Upgrade notes
- Existing v0.2.x installs: re-run `./scripts/install.sh` once from your
  workstation to pick up `ra_uninstall.sh`, `ra_self_update.sh`, VERSION,
  and CHANGELOG.md on the device. `install.sh` is idempotent and leaves
  your credentials, cores, and boot hook untouched. Future updates can
  then be driven from the menu under **Updates ▸ Update toolkit**.
- Fresh installs: no changes to the install flow.

### Added
- `scripts/ra_uninstall.sh` — one-shot full removal of the toolkit. Inlines
  the `ra_off` logic, restores `/media/fat/MiSTer` from `MiSTer.stock`,
  strips the boot hook, deletes `_RA_Cores/`, `MiSTer.stock`,
  `achievement.wav`, `retroachievements.cfg`, `Scripts/RA_Helper.sh`, and
  `Scripts/.ra/`, then reboots. Re-execs itself from `/tmp` first so it can
  safely delete its own directory mid-run. Env toggles:
  `RA_UNINSTALL_ASSUME_YES=1` (skip prompt), `RA_KEEP_CFG=1` (preserve
  credential file).
- `scripts/ra_self_update.sh` — fetches the latest tagged release of the
  toolkit from GitHub and replaces the helper scripts on the device.
  Validates the extracted tarball before overwriting anything, and backs up
  the prior scripts to `/media/fat/Scripts/.ra/.backup_<timestamp>/` so a
  bad release can be rolled back manually. Never touches odelot's binary,
  cores, credentials, or the boot hook. Env toggles:
  `RA_SELF_UPDATE_ASSUME_YES=1`, `RA_SELF_UPDATE_FORCE=1`.
- `scripts/release.sh` — workstation-side helper that reads `VERSION`,
  extracts the matching section from `CHANGELOG.md` as release notes, tags
  the commit, pushes the tag, and creates the GitHub release via `gh`.
  Idempotent preflight checks (clean tree, tag not already taken).
- `RA_Helper` menu: new **Updates** submenu groups "Update RA cores
  (odelot)", "Update toolkit (scripts)", and "View changelog". The
  changelog viewer renders `/media/fat/Scripts/.ra/CHANGELOG.md` in a
  `dialog --textbox`.
- `RA_Helper` menu: new **Uninstall toolkit** entry with two-level
  confirmation, wired to `ra_uninstall.sh` with `RA_UNINSTALL_ASSUME_YES=1`.
- `install.sh` now uploads `ra_uninstall.sh`, `ra_self_update.sh`,
  `VERSION`, and `CHANGELOG.md` alongside the other helpers under
  `/media/fat/Scripts/.ra/`.

### Changed
- `install.sh` SCRIPT_VERSION → 0.3.0 (adds uninstall, self-update,
  VERSION, and CHANGELOG to the upload loop).
- `ra_helper.sh` SCRIPT_VERSION → 0.3.0 (Updates submenu; new Uninstall
  entry; About box expanded).
- `docs/USAGE.md`: documents the menu changes, `ra_uninstall.sh`, and
  `ra_self_update.sh`. "Removing the toolkit entirely" now points at the
  one-shot uninstaller; manual steps remain as a fallback.

## [0.2.2] - 2026-04-15

### Changed
- `ra_helper.sh` now streams each helper's stdout/stderr into
  `dialog --programbox` instead of capturing to a temp file and displaying
  it after completion. Output (including per-core download progress and
  per-file status lines) appears live, so the menu no longer looks frozen
  during long operations like Update. The box stays on screen after the
  helper exits and shows the exit code; press Enter to dismiss.
- `ra_update.sh` emits explicit `downloading ...` / `extracting ...`
  status lines before each large `curl` / `unzip` step so the stream has
  visible activity rather than long silent gaps (curl is still invoked
  with `-sS`; byte-level progress isn't line-based enough to render
  cleanly inside programbox).
- `install.sh` runs in a terminal (not dialog), so the multi-MB GitHub
  downloads (main binary zip + per-core `.rbf`/`.zip`) now use
  `curl --progress-bar` with a preceding `downloading ...` echo. Small
  JSON API calls stay silent to avoid flash-bar noise.

## [0.2.1] - 2026-04-15

### Fixed
- `install.sh` now uses absolute FTP URLs (`ftp://HOST//path`) instead of
  single-slash paths. MiSTer's default FTP home is `/root`, so the prior
  form was being interpreted as relative to `/root` and failing with 550
  on `CWD media`. Double-slash makes paths absolute from the FS root.
- `ra_update.sh` now tolerates stale/missing CA bundles on MiSTer's BusyBox
  image. Previously `curl` exited 60 ("unable to get local issuer
  certificate") against `api.github.com` and aborted the run. The script
  now tries verified TLS first and, on cert-verification failure (curl
  rc 35/60/77), warns once and falls back to `--insecure` for the rest of
  the run.

## [0.2.0] - 2026-04-15

### Added
- `scripts/ra_helper.sh` — unified `dialog`-based menu. Deployed on the
  MiSTer as `/media/fat/Scripts/RA_Helper.sh`; presents Status, Turn ON,
  Turn OFF, Update, View README, and Rollback in a single screen and
  shells out to the existing toggle scripts.
- `RA_UPDATE_ASSUME_YES=1` environment toggle in `ra_update.sh` — when
  set, new-core adoption prompts auto-answer "y" (used by the menu so it
  can run non-interactively).

### Changed
- On-device layout: only `RA_Helper.sh` lives in `/media/fat/Scripts/` so
  the MiSTer main menu's Scripts browser shows one entry for this tool
  instead of six. The helpers (`ra_on.sh`, `ra_off.sh`, `ra_status.sh`,
  `ra_update.sh`, `ra_rollback_binary.sh`) moved to
  `/media/fat/Scripts/.ra/`, which the browser hides by dotfile
  convention (same pattern MiSTer_SAM uses for its `.MiSTer_SAM/` dir).
- `install.sh` uploads to the new layout.
- `docs/USAGE.md` and `docs/INSTALL.md` now point at the menu as the
  preferred entry point; direct CLI invocation of helpers is documented
  as a fallback using the new `.ra/` paths.

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
