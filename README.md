# HordeEternal

A guild management addon for the **World of Warcraft Forever** client: guild
composition statistics, a searchable member directory, a shared profession
catalogue, and a guild map.

> **Public repository.** Anyone may contribute through a pull request to `main`,
> which needs a passing CI run and approval from the maintainer — the only code
> owner. Players install the addon from its CurseForge page; only the maintainer
> publishes releases. See [Releasing](#releasing-maintainer-only).

| | |
|---|---|
| Addon folder | `HordeEternal/` |
| TOC | `Interface: 16001`, `Version: 1.0.2` |
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

# 2. Bump ## Version in HordeEternal/HordeEternal.toc via a pull request and
#    merge it. The TOC is the single source of truth for the release version.

# 3. Build the upload artifact (folder-rooted zip, as CurseForge expects).
.\tools\New-AddonPackage.ps1
```

The script names the file `dist/HordeEternal-<TOC version>.zip` and prints the
SHA-256. Upload that file to the CurseForge project page by hand, then tag the
merged commit:

```powershell
git tag -a v1.0.2 -m "HordeEternal 1.0.2"
git push origin v1.0.2
```

The TOC version must be bumped as part of each release, not after it. It sat at
`0.1.0` while CurseForge shipped `1.0.0`–`1.0.2`, which meant the in-game version
string was wrong and any package built from the repository would have been
mislabelled.

`tools/Test-AddonVersion.ps1` enforces this in CI:

- the TOC version must be a plain `MAJOR.MINOR.PATCH`;
- on a `v*` tag build, the tag must equal the TOC version exactly;
- on every other build, the TOC version must not be behind the newest release tag.

So a release cannot be tagged with a mismatched TOC, and a stale TOC cannot
quietly reach the packager. `New-AddonPackage.ps1` reads the same value.

CI builds the same zip on every pull request as a downloadable artifact, so
contributors can test a real package without touching the release channel.
