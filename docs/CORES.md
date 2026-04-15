# Core support matrix

## RA-supported on MiSTer (via odelot)

These are the systems odelot has actively modified to expose emulated RAM
over DDRAM, enabling the rcheevos client in the main binary to evaluate
achievement conditions.

| System | odelot repo | Stock folder | Notes |
|--------|-------------|--------------|-------|
| NES | [NES_MiSTer](https://github.com/odelot/NES_MiSTer) | `_Console` | Release ships as a zip containing `NES.rbf` |
| SNES | [SNES_MiSTer](https://github.com/odelot/SNES_MiSTer) | `_Console` | |
| Genesis / Mega Drive | [MegaDrive_MiSTer](https://github.com/odelot/MegaDrive_MiSTer) | `_Console` | |
| Master System / Game Gear | [SMS_MiSTer](https://github.com/odelot/SMS_MiSTer) | `_Console` | Game Gear uses this core via MGL |
| Game Boy / Game Boy Color | [Gameboy_MiSTer](https://github.com/odelot/Gameboy_MiSTer) | `_Console` | GBC uses this core via MGL |
| Nintendo 64 | [N64_MiSTer](https://github.com/odelot/N64_MiSTer) | `_Console` | |
| PlayStation | [PSX_MiSTer](https://github.com/odelot/PSX_MiSTer) | `_Console` | |

## Announced but not yet released

These repositories exist in odelot's GitHub profile but have no published
releases at the time of writing. `ra_update.sh` will discover them the
moment odelot ships a release `.rbf`.

| System | odelot repo |
|--------|-------------|
| Game Boy Advance | [GBA_MiSTer](https://github.com/odelot/GBA_MiSTer) |
| Neo Geo | [NeoGeo_MiSTer](https://github.com/odelot/NeoGeo_MiSTer) |

## No RA support on MiSTer

Every other MiSTer core has no RetroAchievements integration. This
includes Atari 2600/5200/7800/Lynx, Intellivision, ColecoVision, TG16,
Saturn, Sega CD, Atari Jaguar, Neo Geo Pocket, WonderSwan, Game & Watch,
and every arcade core. The toolkit cannot add support that doesn't exist
upstream — this is a hardware/firmware problem, not a packaging problem,
because achievements require the core to publish emulated RAM to the ARM
side.

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
