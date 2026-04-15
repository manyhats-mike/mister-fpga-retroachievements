# How it works

## Problem

odelot's RetroAchievements integration for MiSTer requires:

1. A modified MiSTer main binary (`/media/fat/MiSTer`) that hosts the
   rcheevos client and reads emulated RAM from DDRAM every VBlank.
2. A modified `.rbf` per supported system that pushes its emulated RAM
   contents into DDRAM on a known interface.

The standard MiSTer update tools (`update_all` → `Downloader_MiSTer`)
pull fresh copies of both the main binary and every core from
MiSTer-devel on a regular cadence, silently replacing any modified
builds. Running odelot's fork directly leaves users constantly needing
to re-deploy after every update.

## Solution

The toolkit introduces a parallel "RA mode" layered on top of a normal
MiSTer install:

```
/media/fat/
├── MiSTer                     <- odelot's modified binary (always)
├── MiSTer.stock               <- backup of upstream binary (for rollback)
├── retroachievements.cfg      <- credentials + display prefs
├── achievement.wav            <- unlock SFX
├── _RA_Cores/                 <- opaque to update_all
│   ├── MiSTer.ra              <- current odelot binary (source of truth)
│   ├── NES.rbf                <- odelot's modified NES core
│   ├── ...
│   └── .manifest              <- core → folder/pattern mapping
├── _Console/                  <- managed by update_all, untouched
│   ├── NES_20260101.rbf       <- stock core (when RA off)
│   ├── NES_20260101.rbf       <- symlink to _RA_Cores/NES.rbf (when RA on)
│   └── .ra_stash/             <- stock files stashed here when RA on
├── Scripts/
│   └── ra_*.sh                <- the five toggle / status scripts
└── linux/user-startup.sh      <- boot hook (RA_AUTORESTORE block)
```

## Design choices

### Symlink replacement of stock files (not bare-name aliases)

When RA mode is on, the stock `.rbf` file keeps its exact filename — the
real file is moved to `.ra_stash/`, and a symlink of the same name takes
its place. This is important because:

- MiSTer's menu, Zaparoo, NFC triggers, and `.mgl` launchers all resolve
  cores by path glob. Any of them may pick the highest-version filename
  from `_Console/`. If we left both `NES_20260101.rbf` (real) and
  `NES.rbf` (symlink) present, the resolver's choice would be ambiguous
  and version-dependent.
- Stashing the real file and taking over its name guarantees that
  whatever mechanism picks up the core will get the RA build.

### Always-on modified main binary

odelot's fork is deliberately backward-compatible with stock cores — RA
logic only fires when a core cooperates by publishing RAM to DDRAM. Stock
cores behave normally under the modified binary. That lets us keep the
modified binary resident permanently, which means:

- `ra_on.sh` / `ra_off.sh` only swap cores — no reboot required.
- Unsupported systems (Atari 2600 etc.) keep working under RA mode, just
  without achievements.

### Boot auto-restore hook

`update_all` **will** overwrite `/media/fat/MiSTer` on its next run;
nothing in the public `downloader.ini` surface area lets us prevent this
cleanly (and even custom databases are not allowed to replace the main
binary).

Instead, we append a block to `/media/fat/linux/user-startup.sh` — which
MiSTer runs at boot before the main daemon starts — that compares the
live binary against `_RA_Cores/MiSTer.ra` and re-copies if they differ.
When the files already match (the common case) the check is a single
`cmp` of two ~1 MB files; it adds no noticeable boot delay.

This means the workflow becomes:

1. User runs `update_all` at some point.
2. `update_all` pulls the upstream MiSTer binary and stock cores.
3. User reboots (or `update_all` reboots automatically).
4. Boot hook sees the binary doesn't match `MiSTer.ra` and restores it.
5. If RA mode was on, user runs `ra_on.sh` again to re-symlink the
   freshly-pulled stock cores.

Only step 5 is manual; everything else is automatic.

### Auto-discovery of odelot's repos

The manifest is populated from a live query to GitHub
(`/users/odelot/repos`). Every repo ending in `_MiSTer` that publishes a
`.rbf` asset (directly or inside a zip) is a candidate. This means:

- When odelot adds a new system (e.g. Game Boy Advance, Neo Geo, both
  currently exist as empty repos), the next `ra_update.sh` run prompts
  the user to adopt it — no toolkit update required.
- The toolkit doesn't care about odelot's filenames; it writes files as
  `<basename>.rbf` in `_RA_Cores/` based on the repo name.

### Pipe-delimited manifest

The manifest file is trivial to read with `awk -F'|'` or `IFS=|`, needs
no JSON parser on the MiSTer, and is safe for shell iteration. The file
lives on the device and is edited by `ra_update.sh`; the toggle scripts
only read it.

## What the scripts actually do

### `install.sh` (runs on workstation)

1. FTP-verify connectivity.
2. Download odelot Main_MiSTer latest release; extract the MiSTer binary,
   achievement.wav, and retroachievements.cfg template.
3. Query `odelot/*_MiSTer` repos; download each latest release `.rbf`.
4. If `/media/fat/MiSTer.stock` does not exist, fetch the live
   `/media/fat/MiSTer` and upload it back as `MiSTer.stock`.
5. Create `/media/fat/_RA_Cores/`; upload `MiSTer.ra`, every core `.rbf`,
   and the generated manifest.
6. Upload `retroachievements.cfg` placeholder (only if none already
   exists), upload `achievement.wav`.
7. Upload the five toggle scripts into `/media/fat/Scripts/`, chmod 755.
8. Read `/media/fat/linux/user-startup.sh` (or create if absent); append
   the RA_AUTORESTORE block if not already present.

It does **not** install the modified binary at `/media/fat/MiSTer`
directly — ProFTPD refuses to overwrite a running executable. The boot
hook handles that: on the next reboot, the live binary is not running
yet, and the hook swaps it in.

### `ra_on.sh`

For each manifest entry:

1. Ensure `/media/fat/MiSTer == _RA_Cores/MiSTer.ra`; copy if needed.
2. Find every stock `.rbf` matching `<stock_folder>/<stock_pattern>`.
3. For each one: if it's already a symlink at our target, leave alone;
   otherwise move the real file to `.ra_stash/` and replace with a
   symlink to `_RA_Cores/<basename>.rbf`.
4. If no stock files are found at all, create a bare-name symlink
   `<stock_folder>/<basename>.rbf` as fallback.

Writes `ON` to `/media/fat/_RA_Cores/.state`.

### `ra_off.sh`

Inverse of `ra_on`. For each manifest entry, removes our symlinks and
moves stashed originals back. Does not touch the main binary.

### `ra_status.sh`

Reads the manifest, inspects every core folder, and classifies each
entry as `RA`, `STOCK`, `DIRTY`, `MISSING`, or `NONE`. Also prints the
live binary status by comparing `/media/fat/MiSTer` against
`_RA_Cores/MiSTer.ra` and `MiSTer.stock`.

### `ra_update.sh`

Same discovery logic as `install.sh`, but runs on the MiSTer and writes
into `_RA_Cores/` directly. Prompts before adopting any newly-discovered
`*_MiSTer` repo. Also refreshes `_RA_Cores/MiSTer.ra` from
`odelot/Main_MiSTer` latest release.

### `ra_rollback_binary.sh`

Emergency escape hatch: copies `/media/fat/MiSTer.stock` back over
`/media/fat/MiSTer`, strips the RA_AUTORESTORE block from
`user-startup.sh`, and reboots. After this, only a fresh `install.sh`
run reinstates RA support.
