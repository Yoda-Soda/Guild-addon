# HordeEternal

A guild management addon for the **World of Warcraft Forever** client: guild
composition statistics, a searchable member directory, a shared profession
catalogue, and a guild map.

> **This is a private repository.** Source is shared with invited contributors
> only. Players install the addon from its CurseForge page — only the
> maintainer publishes releases. See [Releasing](#releasing-maintainer-only).

| | |
|---|---|
| Addon folder | `HordeEternal/` |
| TOC | `Interface: 16001`, `Version: 0.1.0` |
| Client | WoW Forever, pinned data build `1.60.1.69977` |
| Saved variables | `HordeEternalDB` (account), `HordeEternalCharacterDB` (per character) |
| Licence | MIT — see [LICENSE](LICENSE), plus the bundled `LibProfessionDB-1.0` |

## What it does

- **Guild overview** — class, race and talent composition with percentages and
  tooltips that state the denominator (mains vs. all characters).
- **Member directory** — every verified guild character, online first, with
  class-coloured names, main/alt links and Discord presence.
- **Profession catalogue** — recipes each character has actually learned, shared
  with the guild so members can find a crafter for an item.
- **Guild map** — plots guild activity on the world map.
- **Minimap button** and in-game options for the above.

`HordeEternal/README.md` is the detailed feature and in-client verification
specification. Read it before changing behaviour — it documents the expected
semantics precisely, down to empty-state and offline handling.

## Repository layout

| Path | Purpose |
|---|---|
| `HordeEternal/` | The addon itself — this folder is what gets packaged and installed |
| `HordeEternal/libs/` | Vendored `LibStub` and `LibProfessionDB-1.0`. **Hash-pinned; do not edit by hand** |
| `HordeEternal/libs/LibProfessionDB.lock.json` | Pinned upstream version, archive SHA-256 and per-file hashes |
| `tests/` | Automated checks (PowerShell 5.1 + Lua specs executed through MoonSharp) |
| `tools/` | Maintainer utilities: library import, icon conversion, packaging |
| `.github/workflows/` | CI: runs the tests on every pull request |

## Development

Prerequisites: **Windows** with **Windows PowerShell 5.1** (`powershell.exe`).
No Lua or WoW installation is needed to run the automated tests.

```powershell
git clone git@github.com:Yoda-Soda/Guild-addon.git
cd Guild-addon
.\tests\run-tests.ps1
```

The runner downloads MoonSharp 2.0.0 from NuGet on first use into
`%TEMP%\HordeEternal-LuaTests` (the same location the existing scripts default
to) and then runs:

1. `tests/embedded_library_spec.ps1` — embedded-library load order, per-file
   SHA-256 integrity against the lock file, TOC metadata and retained licence.
2. The Lua specs — `crafting`, `guild`, `members`, `map`, `scanning` — in a
   MoonSharp interpreter with the WoW API mocked inside each spec.

`tests/library_update_spec.ps1` is **not** part of the default run: it needs the
upstream `ProfessionDB.zip` release archive that only the maintainer keeps. Pass
`-ArchivePath` to exercise it.

VS Code tasks with equivalent commands live in `.vscode/tasks.json`.

### In-client checks

The automated tests run against mocked APIs and cannot prove client behaviour.
`HordeEternal/README.md` ends with the manual verification checklist that must be
walked through in the client for anything touching roster, secret-value
restriction, sync, or UI layout.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Contributions arrive as pull requests
into `main`; nothing is pushed directly to `main`.

## Releasing (maintainer only)

Packaging and publishing are deliberately restricted to the maintainer. **Do not
upload to CurseForge from a pull request.** The publish step is performed
manually by the repository owner, because the CurseForge project accepts
releases from that account only.

```powershell
# 1. Tests and CI must be green on main.
git switch main; git pull

# 2. Build the upload artifact (folder-rooted zip, as CurseForge expects).
.\tools\New-AddonPackage.ps1
```

The script writes `dist/HordeEternal-<version>.zip`, verifies the TOC
`## Version` matches, and prints the SHA-256. Upload that file to the CurseForge
project page by hand, then tag the release:

```powershell
git tag -a v0.1.0 -m "HordeEternal 0.1.0"
git push origin v0.1.0
```

CI builds the same zip on every pull request as a downloadable artifact, so
contributors can test a real package without touching the release channel.
