# Core support matrix

## RA-supported on MiSTer (via odelot)

These are the systems odelot has actively modified to expose emulated RAM
over DDRAM, enabling the rcheevos client in the main binary to evaluate
achievement conditions.

| System | odelot repo | Stock folder | Notes |
|--------|-------------|--------------|-------|
| NES / Famicom Disk System | [NES_MiSTer](https://github.com/odelot/NES_MiSTer) | `_Console` | Release ships as a zip containing `NES.rbf`. FDS auto-routes to RA console ID 91; the binary detects the `FDS\x1A` header and switches console mapping for RA game-ID lookup. |
| SNES | [SNES_MiSTer](https://github.com/odelot/SNES_MiSTer) | `_Console` | Selective-address protocol (~185 reads/frame). |
| Genesis / Mega Drive | [MegaDrive_MiSTer](https://github.com/odelot/MegaDrive_MiSTer) | `_Console` | |
| Master System / Game Gear | [SMS_MiSTer](https://github.com/odelot/SMS_MiSTer) | `_Console` | Game Gear uses this core via MGL. |
| Game Boy / Game Boy Color | [Gameboy_MiSTer](https://github.com/odelot/Gameboy_MiSTer) | `_Console` | GBC uses this core via MGL. |
| Nintendo 64 | [N64_MiSTer](https://github.com/odelot/N64_MiSTer) | `_Console` | Hybrid model: ARM mmaps RDRAM directly; FPGA only emits a VBlank heartbeat. |
| PlayStation | [PSX_MiSTer](https://github.com/odelot/PSX_MiSTer) | `_Console` | CHD disc images supported via `libchdr`; `.cue`/`.gdi` via the rcheevos default reader. |
| Game Boy Advance | [GBA_MiSTer](https://github.com/odelot/GBA_MiSTer) | `_Console` | IWRAM (BRAM, with read-retry on collisions) + EWRAM + Flash via DDRAM. ARM pre-fills Flash with `0xFF` on game load when no save is present. |
| Mega CD / Sega CD | [MegaCD_MiSTer](https://github.com/odelot/MegaCD_MiSTer) | `_Console` | 64 KB Work RAM + 512 KB MCD Program RAM (SDRAM). CHD disc images supported. |
| Neo Geo (MVS / AES / CD) | [Neogeo_MiSTer](https://github.com/odelot/Neogeo_MiSTer) | `_Console` | CD CHD images supported. |
| TurboGrafx-16 / PC Engine | [TurboGrafx16_MiSTer](https://github.com/odelot/TurboGrafx16_MiSTer) | `_Console` | PC Engine CD CHD supported. |
| Atari 2600 | [Atari7800_MiSTer](https://github.com/odelot/Atari7800_MiSTer) | `_Console` | Routed via the Atari7800 core (RA console ID 25); the 7800 core also runs 2600 games. |
| Sega 32X | [S32X_MiSTer](https://github.com/odelot/S32X_MiSTer) | `_Console` | Released alongside `poc-v12`. |

## No RA support on MiSTer

Every other MiSTer core has no RetroAchievements integration. This
includes Atari 5200/Lynx, Intellivision, ColecoVision, Saturn, Atari
Jaguar, Neo Geo Pocket, WonderSwan, Game & Watch, and every arcade
core. The toolkit cannot add support that doesn't exist upstream — this
is a hardware/firmware problem, not a packaging problem, because
achievements require the core to publish emulated RAM to the ARM side.

If you want achievements for these systems, the usual alternative is to
play them in RetroArch on a PC (RetroArch has full RA integration for
most of these cores).

## Per-system quirks

**Game Gear.** Uses `SMS.rbf` via an MGL shim. `ra_on.sh` only creates
the symlink for the SMS core; Game Gear launches via the same binary and
picks up RA support automatically.

**Game Boy Color.** Uses `Gameboy.rbf` via an MGL shim. Same story as
Game Gear.

**NES.** odelot releases this one as a zip containing a folder and a
`.rbf` inside. `ra_update.sh` and `install.sh` both handle the zip case
transparently — they unzip and find the `.rbf` wherever it lives.

**N64 and PSX.** These are the most demanding cores on the ARM side;
the RA integration's per-frame RAM read may have more visible overhead
here than on 8/16-bit systems. If you see hitching in these cores
specifically, file an issue upstream at odelot/N64_MiSTer or PSX_MiSTer.

**Famicom Disk System.** No separate core — the modified NES core
detects FDS images by their `FDS\x1A` 16-byte fwNES header, strips it
before MD5 hashing, and reports console ID 91 to RetroAchievements so
the right game database is queried.

**Atari 2600.** Played via the modified `Atari7800_MiSTer` core (the
7800 hardware also runs 2600 carts). The RA stack reports console ID 25.

## Hardcore mode

odelot's binary added hardcore enforcement in **v1.0** (2026-04-26).
Today only the **NES / FDS** path actually enforces it (load-state and
cheats are blocked at the core level); other cores accept the
`hardcore=1` flag but silently fall back to softcore. Expect this list
to grow as odelot ships per-core enforcement work.

To toggle:

- **Menu:** `RA_Helper → Hardcore mode`. The label shows the current
  state in line; selecting it shows a confirm dialog and flips the cfg.
- **CLI:**
  ```sh
  /media/fat/Scripts/.ra/ra_hardcore.sh status   # default action
  /media/fat/Scripts/.ra/ra_hardcore.sh on
  /media/fat/Scripts/.ra/ra_hardcore.sh off
  /media/fat/Scripts/.ra/ra_hardcore.sh toggle
  ```

The toggle writes to `/media/fat/retroachievements.cfg` (atomic
temp-file + rename, with duplicate-line collapse). Changes take effect
on the **next core load** — no reboot, but you do need to relaunch the
core for the binary to pick the new flag up.

> **Why is hardcore single-core only right now?** Hardcore requires
> the *core* to refuse load-state restores and cheat injection, not just
> the RA layer. odelot has implemented those refusals in the NES core;
> the other cores either have hooks pending or have not been audited
> yet. The toolkit will not artificially gate the toggle by core — your
> NES games will be hardcore-counted, your SNES games will not, and the
> RA server tracks each unlock under whatever mode the binary actually
> ran in.
