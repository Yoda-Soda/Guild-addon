# Contributing to HordeEternal

Thanks for helping. This is a small project with a strict quality bar around
client compatibility, so please read this before opening a pull request.

## Before you start

- **Environment:** Windows with **Windows PowerShell 5.1** (`powershell.exe`).
  The tooling uses .NET Framework assemblies, so PowerShell 7 is not a valid
  substitute for running the suite as written.
- **The client:** WoW Forever. You can contribute to most areas without it, but
  anything touching the roster, secret values, sync or layout needs an in-client
  check before merge.
- **Talk first for large changes.** Open an issue describing the behaviour and
  the approach. Small fixes can go straight to a pull request.

## Set up

```powershell
git clone git@github.com:Yoda-Soda/Guild-addon.git
cd Guild-addon
.\tests\run-tests.ps1
```

First run downloads MoonSharp 2.0.0 into `%TEMP%\HordeEternal-LuaTests`. You
should see `PASS:` lines and no exceptions.

## Workflow

1. Branch from `main`, one topic per branch:
   `fix/guild-roster-empty-state`, `feature/map-filter`, `docs/readme`.
2. Keep commits focused and write a real message — explain *why*, not just what.
3. Push your branch and open a pull request into `main`.
4. Make sure CI is green and answer review comments by pushing more commits.
5. The maintainer squash-merges. Your branch is deleted automatically.

`main` is the release line and is protected. Pushes go through a pull request
that needs a green CI run, a resolved conversation list, and **approval from the
maintainer**, who is the only code owner. An approval from any other contributor
does not satisfy the gate. Force-pushes and branch deletion are blocked, and
history is linear (squash merges only). Do not rewrite history on a branch
someone is reviewing.

Only the maintainer merges. Expect to wait for their review — that is the point.

## Rules that will bite you

### `HordeEternal/libs/` is vendored and hash-pinned

Never edit anything under `HordeEternal/libs/` by hand. `LibProfessionDB.lock.json`
records the upstream version, the archive SHA-256 and a SHA-256 per file;
`tests/embedded_library_spec.ps1` fails on any drift, on extra files, on a broken
`embeds.xml` load order, and if the upstream MIT notice is altered.

Updating the library is a maintainer task via `tools/Import-ProfessionDB.ps1`
with a new pinned hash — open an issue rather than editing the data.

Note that `libs/` is marked `-text` in `.gitattributes` on purpose. Do not
normalise line endings there.

### Do not infer client compatibility from mocks

The Lua specs stub the WoW API. Passing them proves logic, not that the real
client returns what your mock claims. For anything touching the client:

- State what you actually verified and what still needs an in-client check.
- Collect `GetBuildInfo()` and `WOW_PROJECT_ID` before asserting compatibility.
- Prefer a focused runtime probe over an assumption.

### Guard secret values

On the Forever client, identity-bearing returns may be secret. Guard every API
return that can be secret, including late tuple fields such as guild-roster
GUIDs — a readable return type does not prove the value is accessible. Do not
log, compare, format or pass potentially secret values into other APIs without
checking the contract.

### TOC metadata

Do not change `## Interface`, `## Version`, `## SavedVariables` or the load order
in `HordeEternal.toc` in a feature pull request. `## Interface` pins the client
generation and `## Version` is set by the maintainer at release time. If you
think either is wrong, raise it in an issue.

### PowerShell 5.1 quoting

Prefer a `.lua` test file over native `lua -e` strings with embedded quotes. For
multi-step validation use a single script block with terminating errors
(`$ErrorActionPreference = 'Stop'`) and inspect real output before reporting
success.

## Testing

```powershell
.\tests\run-tests.ps1                         # everything contributors can run
.\tests\run-tests.ps1 -SkipLua                # integrity/TOC checks only
.\tests\embedded_library_spec.ps1             # one suite
```

Add a spec when you change behaviour covered by an existing spec, and keep the
`PASS:` output lines. A change that reduces coverage will be asked to add it
back.

`tests/library_update_spec.ps1` requires the upstream release archive and is
maintainer-only.

## Pull request checklist

- [ ] `.\tests\run-tests.ps1` passes locally
- [ ] New or changed behaviour is covered by a test
- [ ] No files under `HordeEternal/libs/` were modified
- [ ] `HordeEternal.toc` version/interface untouched (unless agreed)
- [ ] In-client checks noted, or explicitly listed as still outstanding
- [ ] No secrets, tokens, account names or personal data in the diff
- [ ] I have not bumped the version or published anything

## Releasing is maintainer-only

Packaging and uploading to CurseForge is done exclusively by the repository
owner, from `main`, after review. Contributors never create a release, never
upload a zip, and should never need CurseForge credentials. CI produces a
testable artifact on each pull request if you want to try a real package.

## Licence

By contributing you agree that your work is licensed under the project's MIT
licence (see [LICENSE](LICENSE)). Do not paste in code you cannot license this
way, and preserve the bundled `LibProfessionDB-1.0` MIT notice.
