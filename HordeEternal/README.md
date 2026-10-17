# Horde Eternal

## Guild Overview

The Guild tab includes class, race, and talent-estimate counts in a compact
composition area. Select Classes, Races, or Talents to see ranked counts and
proportional bars; larger breakdowns have their own page arrows. Counts include a
percentage, such as `12 (23.5%)`, using the selected population as the denominator.
Unknown race/spec reports remain in that population; these are composition
percentages, not a claim of statistical significance. An empty population shows
`-` rather than dividing by zero. Tooltips identify the denominator. Radio buttons
default to **Mains**; **All characters** includes mains, known alts, and characters
who have not declared a main. Zero-count classes and unknown race/spec coverage
are retained. Statistics use the complete readable guild roster, not only online
characters or addon users. Mains-only totals exclude undeclared characters rather
than guessing which character is their main.

The searchable directory lists every verified guild character, online first,
with six fixed rows per page and no nested list scrolling. Aligned Character,
Class/Race, Talents, Role, and Main/Nickname columns separate each character's information.
Class-coloured names and standard class icons make the rows easy to scan. Each
row shows **Main**, **Alt of Name Surname**, or **No main selected**, plus class,
reported race/spec, guild rank, and Discord server nickname. Hover
a row for rank, availability, talent point distribution, and last-report time.
The statistics filter does not hide unknown or alternate characters in this list.
Click a column heading to sort the entire filtered list, then click again to
reverse direction. A direction arrow marks the active heading, and sorting
returns to page one. Role sorts by the guild's rank hierarchy, not alphabetically
or by a guessed tank/healer/damage role. Unknown roles/specs stay after known
values in either direction; name ties are deterministic. Guild roles are also
searchable. The initial unsorted view remains online-first.

### Required Profile Setup

1. Log into the character you want as your main and select **Set up guild profile**.
   After setup, the upper-right profile gear reopens the editor.
2. Tick **This character is my main**, enter your **Discord server nickname**, and
  select **Save**. Choosing a new main replaces the previous one for this WoW
  account in this guild. Unticking the current main and saving clears it.
3. Log into each alt with the updated addon. It uses the account's shared main
  choice and advertises its own link and character facts. Alts that have never
  run this addon cannot be identified automatically.

Guild information and the Crafting tab stay locked until a current guild main
and a nonblank server nickname have been saved for this account. Alts in the
same guild inherit the completed setup. Clearing either field, or losing the
selected main from the guild roster, relocks information. Received profiles and
cached counts do not bypass the local setup requirement. This is an onboarding
rule in the stock addon, not a security boundary against a modified addon or
direct SavedVariables access.

Profile editing opens in a separate dialog. Closing it or pressing Escape cancels
unsaved changes; normal roster updates preserve an active draft. Save is enabled
when there are changes. The dialog keeps the main directory clear for browsing.

The Discord field is the nickname used in the guild's Discord server, not an
account username, handle, or login credential. It is blank by default and required
to unlock the information views. Existing saved Discord text is preserved but
must be saved once to confirm it is a server nickname. Unconfirmed legacy text
is not advertised as a nickname. Saving shares the entered plain-text nickname
with guild addon users; blanking it and saving sends a newer clearing
record. Guild clients may retain previously received values until they receive
the update. No Discord service, OAuth, token, or password is used. The profile is
shared across this account's characters in this guild, not across different WoW
accounts. Account linking uses a generated guild-scoped addon identifier, not a
Battle.net account identifier. Keep the same SavedVariables when updating.

### Race And Talent Coverage

The roster supplies class, level, and rank, but not a complete race or talent
database. Each character reports its own guarded `UnitRace("player")` result and
active talent configuration. Offline data is a last report, not live inspection.
Characters without the addon, unvisited alts, unreadable APIs, and unreceived data
remain unknown. The directory and statistics do not invent race or spec values.

Spec is an estimate from the named talent group with the most spent points.
Ties are **Hybrid**; a readable zero-point configuration is **No talents spent**.
Staged/uncommitted talent edits, missing groups, and restricted values yield
**Spec unknown**. Talent events coalesce updates, with at least 30 seconds between
automatic publications. This does not inspect other players, change talents,
select a gameplay specialization, or infer a tank/healer/damage role.

The reader follows the pinned Forever/Camelot
[talent UI](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua)
and its `C_ClassTalents.GetActiveConfigID`, `C_Traits.GetConfigInfo`,
`ConfigHasStagedChanges`, `GetGroupDisplayInfoByTreeID`, and
`GetGroupCurrencyInfo` declarations. These are from build `1.60.1.70425`, older
than the reported runtime build, and still need a live check.

### Sharing And Trust

Guild member data is stored separately under `memberGuilds`, outside crafting
profiles and crafting generations. Crafting resets do not erase main choices,
server nicknames, or character facts. `HEGM1` schema 2 distinguishes server
nicknames from legacy handle records, which updated clients reject. It uses bounded, rate-limited guild-only packets
through the existing send queue, including when recipe sharing is off. Only a
current verified roster sender can update its character profile. Profile data
from departed members is pruned after a complete roster; unavailable rosters
hide it. Guild scopes cannot be mixed.

Main/alt links are member declarations, not proof of account ownership. The stock
UI only selects the logged-in character and enforces one main per account per
guild. Modified guild addons can forge shared group claims; separate WoW accounts
and separate installations cannot be reliably linked or constrained by this UI.
Newer account-profile revisions supersede older declarations. Profiles are not
relayed on behalf of offline characters; a new installation starts with unknown
facts until their owners publish. Local saved reports persist across sessions.

**Update every guild client and fully restart WoW.** New modules were added to
the manifest. Existing crafting clients continue to share crafting data, but
only updated clients exchange the new member profiles.

## Crafting

The Crafting tab opens on a profession directory. Select a profession or filter
recipes globally. Recipe pages include icons, item effects, available material
data, and cached guild crafters. Hovering a recipe also opens its native tooltip.
The arrow controls make every result reachable, including catalogues larger than
100 recipes. The window scales down to fit smaller game viewports.

The profession directory groups matching profession names across built-in,
Forever client, library, and cached skill-line IDs. Each group has one row and
combined counts; selecting it includes recipes from all of its IDs. Saved recipe
IDs and shared ownership data are unchanged.

Rescan lives in the crafting toolbar. Hover for an explanation; clicking updates
your learned recipes and publishes them when sharing is enabled. The chat icon
beside a remote crafter opens an editable whisper request. It never sends the
message automatically and does not overwrite an existing chat draft.

## Full Recipe Catalogue

Horde Eternal bundles [LibProfessionDB](https://www.curseforge.com/wow/addons/libprofessiondb)
v1.9.1, LibStub, and the complete Forever core/locale data listed by that release.
No separate ProfessionDB, Ace3, or VersionCheck installation is required. The
standalone addon's version-check bootstrap is not included. Restart WoW after
installing this update so the changed manifest and embedded files are loaded.

If the coverage tooltip reports a missing library lookup or an unregistered
LibProfessionDB instance, run `/hordeeternal library`. This read-only diagnostic
reports readiness and recipe count when the embedded library is available.
Only on failure does it also inspect standalone addon/dependency status. A
missing standalone ProfessionDB addon is normal when the embedded copy is ready.
The diagnostic never enables addons or changes settings. If the bundled payload
is missing or fails to initialize, the browser falls back to observed recipes;
Rescan does not download or repair library files.

The header counts unique guild-known recipes, including your current character,
against the available catalogue. Multiple crafters do not increase the recipe
count. Guild coverage includes only received profiles. Online crafters appear
first, alphabetically within each availability group. Offline crafters remain
visible but dimmed, with whisper buttons disabled. Missing online status also
disables requests; cached recipes alone never imply online presence. Roster
updates refresh the ordering and controls. Hover the count for the data source.

## Updating Libraries

Updates are not automatic. The bundled snapshot changes when a maintainer imports
and tests a newer release, then distributes an updated Horde Eternal package.
Players receive library updates by updating Horde Eternal. Guild sync, crafting
resets, and Rescan do not update third-party code or static recipe data. There is
no in-game network downloader or automatic dependency-update job.

[The import tool](../tools/Import-ProfessionDB.ps1) verifies the pinned archive
SHA-256 before extracting anything. It copies upstream files unchanged, retains
the MIT license and LibStub's public-domain notice, and generates
[embeds.xml](embeds.xml) plus a [per-file integrity lock](libs/LibProfessionDB.lock.json).
Load order is LibStub, library engine, Forever core data, then locale data, all
before the catalogue consumer. Other game versions and the standalone bootstrap
are excluded.

### Update Command

Close WoW before applying an update. Download a Forever-compatible archive from
the [official release list](https://www.curseforge.com/wow/addons/libprofessiondb/files/all)
and review its API, license, and client-build coverage. Calculate its SHA-256
with `Get-FileHash -Algorithm SHA256`. A hash pins the bytes you reviewed; it does
not independently prove that a download is trustworthy.

Run from the repository root. These values reproduce the current v1.9.1 release;
replace the archive path, hash, and release URL together for a newer release:

```powershell
$release = @{
  ArchivePath = 'C:\Downloads\ProfessionDB.zip'
  ExpectedSha256 = '909CB41720CF6BF6920F1C25C644F89B39AD63087F589C07737E7DA943C52379'
  SourceUrl = 'https://www.curseforge.com/wow/addons/libprofessiondb/files/9095167'
  Update = $true
}
.\tools\Import-ProfessionDB.ps1 @release -CheckOnly
.\tools\Import-ProfessionDB.ps1 @release
```

If Windows blocks local scripts, use a temporary PowerShell process started with
`powershell.exe -NoProfile -ExecutionPolicy Bypass` to run these commands. This
does not change the machine or user execution policy.

`-CheckOnly` stages and validates without changing the installed bundle or making
a backup. `-Update` requires explicit hash and source URL; it checks existing
vendor files against their recorded hashes before replacing anything. Local
edits, missing files, unsupported manifests, changed licensing, or checksum
mismatches abort the operation. Release version, library minor version, declared
recipe count, data build, file hashes, and load order are read from the staged
release and written to the lock automatically. No source-code edit is required
for a release that follows the supported upstream format.

Only the two owned library directories, their lock, and the embedded load
manifest are replaced. Unrelated libraries and addon files are preserved;
obsolete files in the replaced payload are removed. The previous files are saved
under `%TEMP%\HordeEternal-library-backups`, and the command prints the exact
backup path. Use `-BackupRoot C:\YourBackupFolder` for longer-term retention.
Ordinary installation errors trigger rollback. Do not interrupt the command:
a process termination or power failure may require restoring those backup paths
manually. A reviewed older archive can also be reapplied with `-Update`.

Package integrity is checked before and after applying. Lua syntax is also
compiled without executing vendor code when MoonSharp is available; otherwise
the command prints a warning. Supply `-MoonSharpPath` to point to a local test
DLL. Changed upstream layouts or snapshots above the current 5,000-recipe limit
are deliberately rejected for manual review.

After updating, run the regression checks and verify `/hordeeternal library`
after a full WoW restart. Review the generated dependency diff, update any
release-specific documentation, and distribute the entire Horde Eternal folder
to guild members. The updater does not publish releases or update their copies.

```powershell
.\tests\embedded_library_spec.ps1
.\tests\library_update_spec.ps1 -ArchivePath C:\Downloads\ProfessionDB-v1.9.1.zip
```

The updater regression uses a synthetic release and temporary addon copies to
test preview, replacement, rollback, backups, local-edit protection, obsolete
file removal, and unrelated-file preservation. It never changes the real
bundle. VS Code also provides the **Validate library updater** test task in
[tasks.json](../.vscode/tasks.json); it uses the cached v1.9.1 archive when no
archive path is supplied. Run the existing Lua crafting/guild suites before
shipping. Do not hand-edit generated recipe files or mix game versions.

## Character And Guild Data

Each character's learned profile uses per-character saved variables. The received
guild profiles, named local-character scans, observed recipe definitions, and
crafting generation are shared account-wide under `craftingGuilds[guildKey]`.
Switching to an alt in the same guild immediately reuses the latest cache, even
if the previous character is now offline. That character appears as a separate
named crafter; the current character appears once as **You**. An alt
never advertises another character's professions. Publishing requires a fresh,
readable scan; a successful empty scan withdraws old profession claims, while a
failed or incomplete scan cannot publish. Rescanning also invalidates previously
queued profiles.

Same-generation caches from the previous per-character format migrate when that
character next logs in. Existing newer cached profiles take precedence. Old
generations cannot repopulate reset guild caches or old local learned claims;
affected characters must rescan. Network profiles with an older nonzero source
timestamp cannot replace newer data in the same generation. The library snapshot
is unchanged. Data sharing is within the same WoW SavedVariables account/profile,
not across unrelated accounts or game installations.

Guild sync and remote-crafter display require a complete readable roster with the
current character present. Cached profiles are removed when a verified roster
no longer contains that member. An incomplete or restricted roster hides remote
profiles and pauses communication without treating missing rows as departures.
Changing or leaving guild hides the previous guild's remote profiles. Its scoped
account cache remains available to other local characters still in that guild;
it is never merged into another guild's cache. Whisper
actions recheck membership and online status even if an old recipe selection
remains open. Presence uses the guarded ninth `GetGuildRosterInfo` return, as
observed in the Forever Olympus roster reference; verify on the running client.

## Crafting Reset

Only **Podcast Clawson**, uniquely identified in the current guild roster, can
use the normal reset command. Run:

```text
/hordeeternal resetcrafting
/hordeeternal resetcrafting confirm
```

Confirm within 30 seconds. The command creates the next persistent crafting
generation for this guild. Members clear their local crafting profile, remote
crafter profiles, and observed recipe index when they adopt it, then rescan their
own character. Minimap/window settings, other addon data, sharing preferences,
and the bundled LibProfessionDB catalogue are not reset.

Guild clients relay the latest generation to members who return later, even
when Podcast Clawson is offline. The account also retains the generation so its
other characters adopt it before publishing. Old-generation packets and queued
transfers cannot restore the cleared data. Generation control messages are
exchanged even when recipe sharing is disabled.

This is a trusted-guild protocol, not cryptographic authorization: the stock
command is owner-only, but a guild member with a modified addon could forge a
relayed reset record. The owner's identity must remain uniquely resolvable in
the guild roster. There is no server-side reset storage; offline catch-up needs
an online guild peer retaining the newer generation. A queued or API-accepted
announcement does not prove delivery to every client.

**Upgrade every member and restart the game.** The manifest adds per-character
storage and a new module. Protocol `HERC2` rejects old `HERC1` clients. The old
account-wide crafting cache is discarded because its recipes cannot safely be
assigned to a character; each character rebuilds its own cache on scanning.

## Source And Compatibility

- Library API inspected: [LibProfessionDB v1.9.1](https://www.curseforge.com/wow/addons/libprofessiondb/files/9095167),
  LibStub major `LibProfessionDB-1.0`, minor 13. The release is MIT-licensed;
  its [license notice](libs/LibProfessionDB-1.0/LICENSE) is retained. The import
  records 150 byte-verified upstream files, including 149 Lua scripts.
- That release advertises 2,511 Forever recipes from build `1.60.1.69977`.
  This is an older snapshot than the user's reported client `1.60.1.70450`,
  interface `16001`, project ID `18`. A catalogue count is not proof that every
  entry is currently obtainable. Borrowed Vanilla availability flags are shown
  as unconfirmed rather than silently hiding those recipes.
- Read-only integration uses `GetGameVersion`, `GetMeta`, `IsReady`, `Count`,
  and bounded `Iterate`. Wrong-game, partial, missing, and oversized data fall
  back to observed recipes. Library data is not added to the shared learned list.
- Display and whisper contracts were checked against Gethe's
  [pinned Forever UI source](https://github.com/Gethe/wow-ui-source/tree/b401e0332adfbf0460d319b06d8ea29279a941f1),
  build `1.60.1.70425`: `C_Item.GetItemInfo/GetItemIconByID`,
  `C_TradeSkillUI.GetRecipeOutputItemData`, `C_Spell.GetSpellInfo/GetSpellLink`,
  `C_TooltipInfo.GetHyperlink`, and `ChatFrameUtil.SendTellWithMessage(name, text)`.
  The latter populates the chat editor; it does not send a whisper.
- Item/spell load events refresh selected details. Missing or restricted fields
  remain unavailable; item text and images are never invented.

## Verification

[The package check](../tests/embedded_library_spec.ps1) verifies manifest order,
every imported file's checksum, the retained license, and the absence of a
standalone dependency. With `-MoonSharpPath` (or the local cached test DLL), it
also syntax-compiles every embedded Lua file without executing third-party code.
Actual library initialization and the full catalogue still need an in-game
check; mocked API tests do not prove that the embedded data loads in WoW.

[The offline suite](../tests/crafting_spec.lua) exercises optional library loading,
pagination, unique coverage counts, restricted data, draft preservation,
profession navigation, item-load refresh, Rescan, tab fallbacks, viewport fitting,
and guild transport. It has been run with MoonSharp 2.0.0 and mocked WoW APIs;
this does not certify actual WoW rendering or secure-execution behavior.

[Guild regression tests](../tests/guild_spec.lua) also exercise complete and
restricted rosters, owner confirmation/expiry, crafting-only reset scope,
peer-to-peer offline catch-up, generation persistence across alts, empty and
failed scans, stale queued/partial transfers, and exclusion of departed members.
Run both suites from the repository root with a Lua interpreter:

```text
lua tests/crafting_spec.lua
lua tests/guild_spec.lua
lua tests/members_spec.lua
```

[Member regression tests](../tests/members_spec.lua) cover main replacement,
alt association, default-main statistics, Discord clearing, guarded talent-group
counts, staged/unknown/tied/zero talents, member message reassembly, revision
ordering, guild scopes, profile editing, drafts, and directory paging/filtering.
The mocked Canvas suite also loads the real Guild view to check tab isolation.

Guild-tab client checks still required: save a main and Discord server nickname, log into
an alt, and verify the link on another upgraded client; select a different main
and verify the old one is an alt. Check all-character versus main counts,
unknown/offline rows, character classes/races, talent reset/commit/dual-spec
changes, and nickname clearing. Verify the setup lock, inherited alt setup,
percentages for both populations, heading sorting in both directions, and the
guild Role column. Check the window at normal/small UI scales with
long names and a large roster. No offline test certifies actual WoW rendering,
secure execution, or server delivery.

The legacy guild enumeration contracts and offline-roster completeness still
need confirmation on the running Forever build. The pinned UI source alone does
not certify them. In-game checks still required:

1. With standalone ProfessionDB disabled, restart WoW and open Crafting. Confirm
  `/hordeeternal library` reports a ready library and the pinned snapshot's 2,511
  recipes. Check the source label and repeat with a standalone copy if used.
2. Browse several professions, search globally, and page through a large list.
3. Check images, item effects, long names, and material names with a cold cache.
4. Hover and click Rescan; confirm the tooltip and successful guild publication.
5. Open a guild crafter's request; confirm the recipient and editable text before
   sending. Verify an existing chat draft is preserved.
6. Check the header, details, tooltips, and external tabs at your normal UI scale
   and a smaller viewport, including while the client applies restrictions.
7. Log between characters with different professions and one without professions;
  confirm another guild client sees only each character's own learned recipes.
  Check that the latest received guild cache and the previous character's named
  scan are available immediately on the alt, including after a restart, and that
  no old character cache restores profiles after a crafting reset.
8. Check that offline guild members remain in the verified roster and catalogue,
  including with the guild UI's offline filter toggled. Remove a test member and
  confirm their crafting entries disappear without removing offline members.
  Log a known crafter out and back in: check online-first ordering, dimmed offline
  rows, disabled whisper requests, and re-enabled requests after reconnection.
9. On upgraded test clients, create a reset as Podcast Clawson and confirm other
  characters cannot create one. Verify settings remain unchanged. Keep one peer
  online, log the owner out, then log an older-generation character in and check
  that it adopts the peer's generation and rebuilds only its own crafting data.