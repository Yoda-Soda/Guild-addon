# Horde Eternal

## Missing Addon After A Client Update

First distinguish a missing AddOns-list entry from a loaded addon whose controls
are hidden. Do not delete SavedVariables or reset guild data to troubleshoot
loading.

1. Fully exit WoW, then confirm the client being launched has
  `Interface\AddOns\HordeEternal\HordeEternal.toc`. Extract the packaged
  `HordeEternal` folder there, not a nested repository folder. An existing
  shortcut or symbolic link must still target the correct client and workspace.
  Restart WoW after installing files or changing a manifest; `/reload` alone
  does not establish that the addon was discovered.
2. At character selection, check the AddOns list and enable HordeEternal for
  the affected character. If it is specifically marked **Out of date**, record
  that status. **Load out of date AddOns** can be used for a controlled smoke
  check, but is not proof of compatibility. A completely absent entry needs a
  folder/discovery check before an interface-number change.
3. Record the running build, including the fourth `GetBuildInfo()` return, and
  project ID before proposing a new `## Interface` value:

  ```text
  /dump GetBuildInfo()
  /dump WOW_PROJECT_ID
  ```

  The manifest remains pinned to `16001`. Public sources refreshed on
  2026-11-21 report UI build
  [1.60.1.71037](https://github.com/Gethe/wow-ui-source/blob/734f065329cff4992835b01a84f210a297db91b6/version.txt);
  the separate
  [resource dump](https://github.com/Ketho/BlizzardInterfaceResources/blob/e230342a476eb4ef484ba7b34adc0da6ecc6acc1/README.md)
  reports build `70938`, interface `16001`, and project ID `18`. Neither source
  identifies the currently running client or verifies this reported regression.
4. If listed but not loading, capture the first Lua error and the game's
  load-failure reason. On clients exposing `C_AddOns`, these read-only probes
  distinguish unavailable APIs from load status; run the second block only
  when all three first-block results are `function`:

  ```text
  /dump C_AddOns and type(C_AddOns.IsAddOnLoaded)
  /dump C_AddOns and type(C_AddOns.IsAddOnLoadable)
  /dump C_AddOns and type(C_AddOns.GetScriptsDisallowedForBeta)
  ```

  ```text
  /dump C_AddOns.IsAddOnLoaded("HordeEternal")
  /dump C_AddOns.IsAddOnLoadable("HordeEternal")
  /dump C_AddOns.GetScriptsDisallowedForBeta()
  ```

  If the client reports that addon scripts are disallowed, stop; changing TOC
  metadata cannot bypass that restriction.
5. If loaded but the minimap button/window is absent, use a character in
  **The Horde Eternal**. Controls intentionally stay hidden while guild
  identity is unavailable or unverified. On an eligible character, try
  `/hordeeternal` and `/hordeeternal report`; include their outcome with the
  build and load status. Do not weaken the guild check to make controls appear.

One confirmed access blocker is an explicitly empty `GetNormalizedRealmName()`
result with no guild-realm return from `GetGuildInfo("player")`. The reported
client loads the addon and registers its command, but the old realm check then
silently hides both the minimap button and window despite the correct guild ID.
Readable empty realms now retain realm-less roster identities and use a
`<guild name>@club:503775441` cache scope, without inventing a realm or relaxing
the required guild ID. Missing or restricted realm results still fail closed.
Previous realm-qualified guild caches remain separate and are not deleted; the
realm-less scope populates through fresh scans, member setup, and guild sync.
Use `/reload`, then verify the minimap button and `/hordeeternal` on the affected
character. Current build metadata and post-fix client verification are still
outstanding; passing offline tests does not establish that the live UI recovered.

## Guild Restriction

The addon is restricted to **The Horde Eternal**, guild club ID `503775441`.
Outside that guild, including on guildless characters, the main window, minimap
button, and internal map pins are hidden. Slash commands do not
open the UI or trigger scans, and member/crafting communication is paused. There
is no automatic startup announcement or profession scan outside the guild.

Guild identity is checked through guarded `C_Club.GetGuildClubId`, or a single
guild-type entry from `GetSubscribedClubs` when the direct API is absent. Missing,
pending, or restricted identity fails closed; guild-name matching alone cannot
grant access. Guild/club events restore eligible access without reopening the
window automatically. Existing scoped saved data is preserved. The addon still
appears in WoW's installed-addon management list; this restriction hides its own
in-game controls, not the game's addon-manager entry.

Use `/reload` to apply these Lua changes. Check a member of this guild and an alt
in another/no guild, and verify both fresh login and leaving/rejoining. The club
reader's source declarations are from pinned build `1.60.1.70425`; supplied live
subscription evidence is from build `70938`. Offline tests do not certify the
running client's event timing or identity API results.

## Diagnostic Log

Open the paper-note icon in the main window header, or run:

```text
/hordeeternal logs
/hordeeternal logs trace on
/hordeeternal logs trace off
/hordeeternal logs clear
```

The copyable viewer lists All events, Warnings (including errors), or Errors.
Select **Select All**, then use Ctrl+C to copy the displayed report. It includes
client build/interface/project, initialization/access state, scan freshness,
filter/trace settings, and event history. New events do not replace a focused
report while it is being copied. Clear affects only diagnostic history.

The current-session log retains at most 200 entries, evicts the oldest, and
coalesces repeated identical events within five seconds. It is not written to
SavedVariables: copy a reproduction before `/reload` or logout. Times are client
uptime, not a shared clock. Detailed tracing is off by default; enable it before
reproducing a sync problem to include accepted sends, received chunks, and message
rejections, then disable it afterwards. Send acceptance still does not prove
remote receipt.

Recorded data uses fixed event codes, approved reason values, and bounded counts.
It excludes character names, Discord nicknames, recipe names, message bodies,
database dumps, and raw API-error content; restricted values are omitted. Logs
are local and never automatically shared. The viewer and commands obey the same
single-guild restriction as the addon. This records detected addon failures, not
every unexpected Lua exception; it does not replace or suppress WoW's error
handler. Include the first actual Lua error stack when reporting such an exception.

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
in a fixed-height scrollable table with a mouse wheel and native scrollbar.
Six rows are visible, with one additional recycled buffer row for partial scrolling;
scrolling only paints cached rows rather than rebuilding the roster or statistics.
Aligned Character,
Class/Race, Talents, Role, and Main/Nickname columns separate each character's information.
Class-coloured names and standard class icons make the rows easy to scan. Each
online character has a green status dot and normal class-coloured styling without
repeating an Online label. Offline rows
use a gray band and muted text while class icons stay coloured; unknown presence uses
amber and Status unknown instead of implying the character is offline. Offline
and unknown labels remain explicit; tooltips retain full presence details, and reconnecting characters
restore their online styling immediately on roster refresh. Each
Main/Discord cell has a gold star beside the referenced main's full name,
including on alt rows that reference that main. Main/Alt status remains explicit
under the character name. The guild-leader crown is not used for main characters.
The Discord mark appears beside each
shared server nickname and in the profile editor; it is hidden when no nickname
is available. Class icons stay intact and coloured. Each
row identifies **Main** or **Alt** in the character's status line and shows the
selected main's full **Name Surname** in the Main column, or **No main selected**.
The main name has its own label rather than sharing space with an "Alt of"
prefix. Rows also show class,
reported race/spec, guild rank, and Discord server nickname. Hover
a row for rank, availability, talent point distribution, and last-report time.
The statistics filter does not hide unknown or alternate characters in this list.
All visible character labels, tooltips, crafting requests, and receipt status
messages omit realm suffixes while retaining first name and surname. Canonical
realm-qualified identities remain unchanged for storage, membership, and sender
validation; display formatting never merges their underlying identities.
Click a column heading to sort the entire filtered list, then click again to
reverse direction. A direction arrow marks the active heading, and sorting
returns to the top of the directory. Role sorts by the guild's rank hierarchy, not alphabetically
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
current verified roster sender can publish or relay member reports. Profile data
from departed members is pruned after a complete roster; unavailable rosters
hide it. Guild scopes cannot be mixed.

Main/alt links are member declarations, not proof of account ownership. The stock
UI only selects the logged-in character and enforces one main per account per
guild. Modified guild addons can forge shared group claims; separate WoW accounts
and separate installations cannot be reliably linked or constrained by this UI.
Newer account-profile revisions supersede older declarations. Updated clients
also exchange `HEGM1` protocol-2 inventories and schema-3 snapshots, retaining the
original character's identity. A peer can relay cached main/alt links, Discord
server nicknames, race, talent estimates, and talent distributions after their
owners go offline. Local saved reports persist across sessions. The original
owner and relay sender must still belong to the current verified guild roster.

Account declarations and character facts have independent revision counters.
Newer facts do not roll back a newer main or nickname declaration; explicit
clearing is retained rather than restored from an older peer. Unchanged character
facts keep their revision and original report time. Equal-version conflicts,
identity conflicts, malformed snapshots, and checksum failures are rejected and
logged without private profile fields. A checksum detects corruption; it is not
authentication of the original author. These remain trusted-guild declarations,
not cryptographic proof of account ownership.

Member catch-up uses inventories, requested snapshots, and up to three recovery
attempts. Each inventory callback serializes at most one report, with up to eight
records per outgoing batch, existing message-queue limits, and delayed subsequent
batches for large guilds. Login greetings request cache announcements without
requiring the main window to be open or local profile setup to be complete.
Receiving reports does not bypass that setup lock. Online state and map locations
continue to come from the current roster, not historical relayed reports.

Older clients still receive the original schema-2 direct owner broadcasts, but
only updated clients exchange versioned member snapshots and relay them. Older
cached reports without character-fact revisions remain non-relayable until their
owners complete an updated inventory/snapshot exchange. Member catch-up remains
independent of recipe-sharing opt-out and crafting resets, as before.

**Update every guild client and fully restart WoW.** New modules were added to
the manifest. Existing crafting clients continue to share crafting data, but
only updated clients exchange the new member profiles.

## Guild Map

The **Map** tab shows this guild's online characters by roster-reported zone,
using the client's own map artwork. It follows the Olympus reference's
zone-count presentation, but has no multi-guild selector or cross-guild data.
No external map library or coordinate-sharing protocol is required.

- The world overview groups counts by continent. Click a count to drill down;
  continent maps show zone counts, and zone maps show the zone's total.
  Right-click the map artwork, background, or a count marker to go up one map
  layer. A map without a parent stays unchanged; left-click drill-down remains.
- Hover a count or zone row for the character names. Large tooltips show the
  first twelve names plus the remaining count. Counts always mean characters,
  not distinct people or accounts.
- The primary map spans the tab's width. A compact three-location strip below
  it shows continent totals at the top level and occupied zones when zoomed in.
  Location rows are sorted by count; arrow controls make additional rows
  reachable. Unmapped names remain available as text rather than guessed pins.
- The toolbar includes parent map, world overview, your current zone, open
  native world map, and refresh. Opening the native map is a user action.
- **Guild markers** toggles count markers inside the addon's Map tab. It is
  enabled by default and persists account-wide. Horde Eternal does not add pins,
  a filter button, or hooks to WoW's native world map; other map addons remain
  responsible for their own overlays. The Map tab and its native-map opening
  button remain available.

Locations are snapshots from `GetGuildRosterInfo`, not live player coordinates.
Only confirmed online characters with a readable nonempty zone enter the counts.
Offline and unknown-presence characters are excluded; unknown or unmapped zones
are reported separately rather than assigned guessed coordinates. The Refresh
control requests a new roster; map opening and travel also request updates,
coalesced to at most once per ten seconds. Actual freshness depends on the game.

Zone names are matched by a bounded walk of the client's direct-child map tree,
not a dependency on a one-shot recursive result. Ambiguous names
stay unplaced. The initial Azeroth map is used only when the client exposes it;
otherwise the reader walks upward from the player's map. Unavailable metadata,
restricted fields, or missing art produce an unavailable state, not a fabricated
map. Continent totals are projected directly onto the highest two-continent
overview; rectangles may cross the artwork edge if their centers remain visible.
Zone pins use map-area centers, not the characters' exact positions. Closely
placed zones can overlap; the location strip remains an alternative way to select one.

When a character's reported location has no position on the current map, its
location-strip entry remains visible instead of disappearing during drill-down.
For example, a Kalimdor total that includes Darkspear Island still exposes that
location and its character names when the continent opens, even if the client
cannot project the BG onto Kalimdor. Such entries show **Map position unavailable**
and contribute to the **unplotted** count. A uniquely resolved map remains clickable
and opens its own artwork when available. Unresolved or ambiguous names remain
listed without guessing a map ID; detached instance maps remain available in the
strip, while locations verified on another continent are excluded. Continent
tooltips inside the Map tab also show each character's reported zone.

This is roster-reported location, not a new BG presence protocol, proof of a
particular match, or exact player coordinates. The change needs only `/reload`.
Live check: with one guildmate in Darkspear Island and one in a Kalimdor zone,
compare the world count, continent pin plus location-strip counts, character
tooltips, and opening the BG artwork. Confirm logging the guildmate out removes
the BG entry; unavailable metadata/art must remain honest unavailable states.

The Map tab and its internal pins require completed main/server-nickname setup and a
complete readable roster. Losing access removes pins and their cached frame
payloads. Guild changes cannot mix location snapshots from different guilds.
No map locations are written to SavedVariables or sent to other players.

Implementation evidence: Olympus's read-only Map/Zones examples for the feature
shape; the pinned build `1.60.1.70425`
[map API declarations](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua)
and [map tile renderer](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvasDetailLayer.lua)
for `C_Map.GetMapInfo`, `GetMapChildrenInfo`, `GetMapRectOnMap`,
`GetMapArtLayers`, and `GetMapArtLayerTextures`. No Blizzard source or example
implementation is bundled. These sources predate the reported running build;
offline tests do not certify the actual client's rendering or secure execution.

Use `/reload` after this native-overlay removal. In-game
checks: verify the Map tab's world/continent/zone artwork, tooltip names and counts,
navigation, internal marker toggle, and cold-cache behavior.
Change zones and compare with the guild roster. Log a character out and confirm
their count disappears. Test profile locking and guild leave/change; all markers
must clear. Check normal and small UI scales, and coexistence with other map
addons. Opening WoW's native world map must show no Horde Eternal markers or
filter button. No automated gameplay is performed.

## Crafting

The Crafting tab opens on a profession directory. Select a profession or filter
recipes globally. Recipe rows include icons, item effects, available material
data, and cached guild crafters. Hovering a recipe also opens its native tooltip.
Recipes with no known guild crafter use gray text and desaturated icons while
remaining clickable. Normal styling returns when any guild crafter is known,
including offline crafters; this does not change ownership or the usability filter.
Recipes with known guild crafters appear first, then unknown recipes, with
alphabetical ordering inside each group. The full filtered list is scrollable by
mouse wheel or native scrollbar instead of page arrows. A bounded recycled row
pool renders only the visible area; scrolling does not rebuild the catalogue or
change the selected recipe's details. The window scales down for smaller viewports.

Opening a profession shows its **guild-known / total catalogued recipes** in the
main header. These are the full profession totals, independent of search and
usability filters; the list footer separately shows the visible filtered range.

The profession directory groups matching profession names across built-in,
Forever client, library, and cached skill-line IDs. Each group has one row and
combined counts; selecting it includes recipes from all of its IDs. Saved recipe
IDs and shared ownership data are unchanged.

Professions explicitly labelled `[DNT]` by the client are internal test entries.
They and their recipes are excluded from the visible directory, recipe search,
and coverage counts. Saved definitions/ownership are not deleted, and legitimate
additional professions remain visible.

Rescan lives in the crafting toolbar. Hover for an explanation; clicking updates
your learned recipes and publishes them when sharing is enabled. The chat icon
beside a remote crafter opens an editable whisper request. It never sends the
message automatically and does not overwrite an existing chat draft.

The **Hide unusable** checkbox in the top crafting toolbar hides confirmed unmet
item-use requirements for the logged-in character, including minimum level,
required professions such as Engineering, and equipment proficiency. It is not a
filter for the profession that makes the item. Filtering happens before search
result counts and scrolling; the profession directory and guild coverage totals
remain unfiltered. The account-wide checkbox preference persists, but eligibility
is always re-evaluated for the current character, never copied from a guildmate.

Checks use guarded `C_Item.GetItemInfo` minimum-use level (not item level),
`UnitLevel("player")`, and structured `C_TooltipInfo.GetHyperlink` requirement and
equipment lines. The pinned [tooltip declarations](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoSharedDocumentation.lua)
define `UsageRequirement`, `EquipSlot`, and `ErrorLine`; their live tooltip colors
still need verification on the running build. Missing, restricted, pending, or
non-item output requirements remain visible as unknown rather than being assumed
usable or discarded. Details show the requirement status. Item loads are bounded
and completion events coalesce; level, skill, and tooltip changes refresh the
filtered results while Crafting is visible. No recipe ownership or shared profile
is changed, and no item is equipped or used.

### Automatic Profession Capture

The addon attempts a background scan at login. If the client exposes readable
known-profession lists and recipe details without a window, it can collect them
then. Some Forever profession data is only available after opening the relevant
profession; the pinned declarations do not guarantee complete closed-window
discovery. The addon does not cast profession spells, open windows, clear filters,
or change the selected profession on your behalf.

When a profession is opened, its data source changes, its recipe list becomes
ready, or a recipe is learned, a short debounced scan captures the readable data
automatically. Related events coalesce. Loading failures retry at most three
times; closing or changing the source cancels older delayed scans. Linked,
guild, NPC-crafting, loading, or unreadable sources cannot be adopted as this
character's learned recipes. Automatic capture requires readable own-source
checks. Successful scans refresh the browser and queue sharing when enabled.

Learned recipes accumulate across professions for the current character. Opening
Alchemy after Enchanting no longer replaces Enchanting's recipes. A scan updates
only recipe IDs whose learned state was actually read. Explicitly unlearned
recipes, or a readable API confirmation that the recipe's profession is no longer
learned, withdraw those claims; unobserved recipes remain cached. An empty window
does not mean all other professions were unlearned. The combined profile survives
relogging and is the one shared with guildmates. It remains character-owned and
never borrows learned recipes from another alt or from LibProfessionDB.

The event/source checks follow the pinned build `1.60.1.70425`
[trade-skill declarations](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua)
and [profession frame](https://github.com/Gethe/wow-ui-source/blob/b401e0332adfbf0460d319b06d8ea29279a941f1/Interface/AddOns/Blizzard_Professions/Blizzard_ProfessionsFrame.lua).
They still require live verification on the running client. For context-limited
professions, open each profession normally once; clicking Rescan is no longer
required. Existing lost recipes cannot be invented and must be observed again.

## Full Recipe Catalogue

Horde Eternal bundles [LibProfessionDB](https://www.curseforge.com/wow/addons/libprofessiondb)
v1.10.0, LibStub, and the complete Forever core/locale data listed by that release.
No separate ProfessionDB, Ace3, or VersionCheck installation is required. The
standalone addon's version-check bootstrap is not included. Restart WoW after
installing this update so the changed manifest and embedded files are loaded.
The bundled snapshot declares 2,517 recipes from live build `1.60.1.70938`,
including Herbalism's Incense Candle, Greenhouse, and Seed Hybridizer and Skinning's
Camp Chair, Field Guide, and Trapper's Workbench. Catalogue entries do not establish
which guild members have learned those recipes.

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

Run from the repository root. These values reproduce the current v1.10.0 release;
replace the archive path, hash, and release URL together for a newer release:

```powershell
$release = @{
  ArchivePath = 'C:\Downloads\ProfessionDB.zip'
  ExpectedSha256 = 'F146D5D82347033EC381F42150BFA4D4379149E41D9EFE5C0D4FF291A64C3639'
  SourceUrl = 'https://www.curseforge.com/wow/addons/libprofessiondb/files/9619259'
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
[tasks.json](../.vscode/tasks.json); its synthetic updater regression deliberately
uses the historical cached v1.9.1 archive when no
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
readable scan; explicit unlearned updates withdraw old claims, while a failed,
incomplete, or empty-context scan cannot discard other professions. Rescanning also invalidates previously
queued profiles.

Same-generation caches from the previous per-character format migrate when that
character next logs in. Existing newer cached profiles take precedence. Old
generations cannot repopulate reset guild caches or old local learned claims;
affected characters must rescan. Revisioned network profiles are ordered by owner
revision, not timestamp; legacy profiles cannot replace them. Legacy-only records
still reject older nonzero source timestamps in the same generation. The library snapshot
is unchanged. Data sharing is within the same WoW SavedVariables account/profile,
not across unrelated accounts or game installations.

After a complete readable roster identifies the current character, its complete
saved learned profile is also restored to its named account cache if needed.
This works even when recipe APIs are not ready for a fresh login scan. Incomplete
saved scans and pre-reset data are not promoted, and a restored saved profile
still cannot be published as a fresh scan. Other characters see the original
character as a cached crafter, never as their own learned ownership. When
recovering a previously missing named profile, log into its owner once with the
updated addon before switching back to the alt.

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

## Recipe Synchronization Reliability

New complete readable scans issue persistent per-character revisions and canonical
content fingerprints. Unchanged scans keep their revision; changed recipes and
explicit withdrawals advance it even when timestamps move backwards. Fingerprints
detect corruption, not author identity. The bundled recipe library is unchanged.
Identical complete rescans retain the queued profile identity and coalesce repeat
publication, so frequent profession-list events cannot cancel chunks already in
flight or indefinitely postpone inventory announcements. Changed or unavailable
scans still invalidate queued claims.

Upgraded clients exchange bounded inventories and request missing/newer complete
snapshots through additional `I`, `W`, and `R` messages on `HERC2`. Verified snapshots
retain their original character, generation, revision, fingerprint, and source time
when relayed by a guild peer. Empty snapshots retain withdrawals so old caches cannot
restore the removed recipes. Legacy direct-owner `P` messages remain supported but
cannot overwrite a revisioned record and are never relayed as revisioned claims.

Inventory reconciliation starts shortly after login/publication and repeats about
every three minutes. Large inventories use at most eight packets per batch, with
queue capacity reserved for other work and unfinished batches continued after
fifteen seconds. At most eight owner requests run at once. Recovery makes at most
three attempts, allowing up to five minutes for each transfer and rotating among
up to three retaining providers, then pauses before another reconciliation round.
There is no guaranteed delivery or server-side archive.

Transfers validate guild membership, generation, requested owner/provider, revision,
count, canonical encoding, and fingerprint before replacing any profile. Assemblies,
cache size, request history, and queued work are bounded. Recipe sharing opt-out
stops inventory/request relay. A verified departure removes profiles and cancels
requests/queued snapshots; an incomplete roster still preserves offline members.
Diagnostics include aggregate pending/applied/retry/failure counters, without names.

If an owner restores an older backup, a retained peer can supply the newer revision.
Only a fresh readable scan may issue a revision above it; unavailable recipe APIs
must not turn restored data into a fresh ownership claim. All upgraded clients need
this version for inventory recovery; older clients still use direct broadcasts.

### Detecting Profession Removal

Only the character running the addon can observe their current profession state.
The current scan path withdraws a cached recipe on explicit readable unlearning,
including `C_TradeSkillUI.IsRecipeProfessionLearned(recipeID) == false` for previously
cached recipes. Missing/restricted/nil returns and empty loading windows do not mean
unlearning. That API is declared in pinned build `1.60.1.70425`; its live behavior on
build `70938` is not yet verified. Skill/profession events trigger guarded rescans,
but event arrival alone is not proof that anything was removed. A character who
does not run the addon after changing professions leaves peers with a last report.

Members may have at most **two primary professions**. Profile validation counts
distinct known primary professions per character, excluding First Aid, Fishing,
and Cooking and deduplicating base/Forever aliases. Gathering professions count
toward the limit; unknown skill lines and test professions are not treated as
additional primaries. Do not combine the entire guild or all account alts into one
character's count. A local profile above the limit now flags a conflict and pauses
publication; incoming profiles above the limit are rejected without replacing the
last valid data. The count detects a conflict, not which profession was removed.

Three or more recorded primaries now open an owner-only correction dialog asking
which profession was unlearned. This does not block the member's Guild/Map access;
only publication of the conflicting recipe profile pauses. The owner selects a
recorded primary and explicitly confirms removing its cached learned recipes.
**Later**, closing the dialog, or losing guild access leaves the records unchanged.
Neither selection nor confirmation performs an in-game profession-unlearn action.

Confirmation requires a current readable scan and verified guild roster; stale
dialog selections cannot change a newer profile. It issues a newer owner revision,
preserves the other professions and secondary skills, and resumes sharing once
the cached primary set is valid. Repeated historical swaps may require confirming
more than one old record. A persisted withdrawal prevents stale recipe windows
from restoring the removed profession.

Open the dialog again with `/hordeeternal professions`. **Previously removed**
offers explicit owner confirmation of relearning or recovery from a mistaken
withdrawal, followed by a guarded rescan and the same two-primary validation.
If current recipe APIs are unavailable, the withdrawal is retained rather than
silently restoring old ownership. Other guild members cannot use this dialog to
change someone else's profile. The dialog obeys guild-only visibility.

Live checks: compare a newly learned recipe on two upgraded clients, log the owner
out and recover via a third client, confirm already-known profession removal only
when safe, and compare a verified departure against offline-member preservation.
Enable Detailed diagnostics before reproducing dropped transfers; no offline suite
certifies the actual client's API behavior, roster completeness, or delivery.

## Application Administrator

**Pod Cast** is the configured application administrator for The Horde Eternal.
The main window title shows **Application admin** for that verified character,
**Guild member** for other members, or **Admin status unavailable** when the
current roster/identity cannot establish authority. The title refreshes on guild
roster changes, including while profile setup is still required. The same state
appears in capability and diagnostic reports. Check it without changing any data:

```text
/hordeeternal admin
```

The displayed state and crafting-reset permission use the same guarded identity
check. Guild rank alone, including another officer or guild master, does not grant
application-admin access. `Podcast Clawson` no longer authorizes new resets; saved
profiles/preferences are not renamed or erased by this identity change. Update
all participating clients before using administrator operations. Main-lock
approval and signed correction features remain planned, not unlocked by this
status label. Existing peer-reset authorization is still trust-based as described
below. Use `/reload` for the Lua changes, then check the label on Pod Cast and an alt.

## Crafting Reset

Only **Pod Cast**, uniquely identified in the current guild roster, can
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
when Pod Cast is offline. The account also retains the generation so its
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

## Launch Sync And Correction Plan

This is proposed work, not implemented behavior. Launch diagnostics supplied on
2026-11-15 report client `1.60.1.70938`, interface `16001`, project ID `18`, a
ready schema-1 database, and a ready 2,511-recipe library. The Forever installation
is linked to this repository. Feature delivery, restrictions, and current recipe
accuracy still require live checks. The current source uses `HERC2`; previous
development notes describing `HERC3` are not evidence that it is present here.

The administrator confirmed their launch character is **Pod Cast** and they are
the guild master. Administrative corrections and raid-main approvals are intended
for this administrator only, not every officer. Resolve the character's full
guild/realm identity from a readable roster; do not split the first name and
surname or infer authority from display text alone. The current reset gate and
read-only application-role display now use `Pod Cast`, rejecting the previous
`Podcast Clawson` identity. Authenticated corrections and main approvals remain
planned. A future guild-master transfer must not silently transfer signing
authority.

The user's launch-client `C_Club.GetSubscribedClubs()` probe also reports
**The Horde Eternal**, `clubId=503775441`, `clubType=2`, and `memberCount=241`.
The requested single-guild restriction now uses that ID for runtime eligibility,
not administrator authority. The pinned club declarations map guild type to `2`.
Live checks of current-guild ID results, cross-client consistency, and event timing
remain required. The existing guild-name/realm storage key is unchanged; no database
key migration or roster replacement was performed. The member count does not
certify a complete readable roster, online status, or distinct accounts. Club
broadcasts, descriptions, and unrelated subscriptions are not stored or shared.

### Separate Data Ownership

Do not synchronize or replace the complete SavedVariables database. Separate
wire-protocol version, local storage schema, catalogue release, administrative
correction revision, crafting generation, and character-profile revision.
Use persistent per-character revision counters for profile ordering; timestamps
describe freshness, not authority or a reliable ordering between different clients.

| Data | Writer and proposed correction policy |
| --- | --- |
| Bundled recipe catalogue | Reviewed dependency release; maintainer corrections use a separate data-only overlay, without editing pinned vendor files. |
| Learned recipes and character facts | Each character reports its own facts. A maintainer may invalidate a bad cached claim or require a fresh report, not invent learned ownership. |
| Main selection | Members declare a main during open setup. Once the raid roster is locked, the administrator-approved main record is authoritative; member profiles cannot replace it. |
| Administrative corrections and resets | Only the maintainer can author authenticated releases; peers may retain and relay the unchanged signed records. |
| Presence and map locations | Readable current-client observations; do not promote them into permanent administrative truth. |
| Personal preferences and unrelated saved data | Remain local and outside correction/reset payloads. |

Priorities confirmed on 2026-11-15: no current errors reported; reliable learned
recipe updates are the greatest member-facing risk, and preventing casual main
changes after raid lockdown is the administrator's principal policy requirement.
Recipe catalogue errors, learned-profile errors, and main declarations still
require different repair operations. A crafting reset currently clears learned/
observed caches; it does not repair an incorrect bundled recipe definition.

### Recipe Update Reliability First

Before expanding administrative features, verify the complete lifecycle on two
guild clients: learn a recipe, open/switch professions, publish, receive, log out,
and switch to an alt. A successful update must change the receiving crafter list,
not merely return send-API success. Keep catalogue definitions and each character's
learned ownership separate; a ready 2,511-recipe library is not proof of either
current availability or correct guild ownership.

Use persistent owner-profile revisions and content digests to reconcile changes.
Relayed learned profiles retain their original owner and revision; a relay cannot
make old data newer. Request missing/newer profiles, retry with bounded provider
fallback, and retain useful offline snapshots. Expose fresh, cached, pending,
unavailable, and rejected states without treating offline owners as non-crafters.

Explicit unlearning withdraws the affected profession/recipes. A missing API,
partial scan, linked profession, or temporarily empty loading context must not
erase previously valid professions or publish cached data as a fresh scan.
Targeted maintainer invalidation requires a new valid owner scan and prevents
older cached/queued records from restoring the bad claim. Tests must cover cold
caches, interrupted transfers, reordered/duplicate packets, returning offline
members, opt-out, restarts, and scans spanning several professions.

### Raid Main Lockdown

Current `Members.Save` allows replacing or clearing the main; the received-profile
handler can also accept a higher group revision with a changed main. No raid-main
lock currently exists. Disabling the checkbox alone would not enforce this policy.

Plan a guild-scoped open-setup phase followed by an administrator-confirmed lock.
Before locking, preview current declarations, resolve duplicate/conflicting links,
and publish an authenticated approved-main snapshot. The approved record, not
the most recent member declaration, becomes authoritative for main/alt displays,
statistics, and profile access. Characters not approved at lockdown remain pending
approval rather than silently choosing their own locked main.

After locking, a member may request a change with a proposed main and reason, but
the request never changes the approved record. Only the administrator may approve
or reject it. Approval publishes a new authenticated revision; the guild remains
locked while that one assignment changes. Allow nickname, race/talent, profession,
and other permitted character updates independently of main approval.

Enforce policy in local saving, incoming profiles, capture/migration, queued work,
and view resolution. Clearing a main, selecting an alt, advertising a larger member
revision, regenerating an addon group ID, reinstalling, or replaying older data
must not replace an existing approved assignment. Keep approved roster identities
separate from member-supplied account/group IDs, which do not prove WoW account
ownership. New characters and disputed account links require administrative review.

Persist and relay lock/approval records while the administrator is offline. Missing
or unverifiable policy cannot grant change permission or trigger automatic unlock.
A confirmed departed/renamed main needs an unavailable/review state, not automatic
promotion of an alt. Recipe resets must preserve approved mains, approval history,
and lock policy. Test pre-lock changes, post-lock save and packet rejection, valid
approvals, new recruits, alts/reinstalls, departure, guild changes, restarts, offline
catch-up, and unsupported clients. Unmodified clients enforce the shared policy;
the addon cannot prevent someone editing their own files or establish real-world
account ownership without administrative verification.

### Authenticate Administrative Authority

The existing `Pod Cast` command gate is useful UI authorization, but a
relayed issuer string is forgeable. A checksum detects changed content, not who
authorized it. A larger version number is not authorization either.

For the strict maintainer-only requirement, plan an external signing workflow.
Keep the private signing key outside the repository, addon installation, and
shared SavedVariables. Pin only its public verification key in guild clients.
Select a vetted Lua-compatible signature verifier and benchmark it on this exact
client before committing to a dependency or algorithm; do not invent cryptography
or assume WoW provides a signing API. Define backup, loss, and authenticated key
rotation procedures before rollout.

Sign an envelope covering format, guild scope, key identity, base catalogue/schema
requirements, correction revision, operation identity, payload digest, and content.
Reject invalid signatures, incompatible schemas, wrong-guild records, and unknown
operations before changing data or advancing accepted revisions. Advertised peer
versions must never advance local authority state. Replaying an older release
must not restore old data. Restoring earlier content requires a newly signed,
higher revision, rather than lowering the revision counter.

This authenticates administrative releases on conforming clients, not arbitrary
player facts. It cannot stop someone modifying their own addon or saved files.
Unsigned legacy resets must not remain an administrative bypass after migration;
members need an addon update to participate in authenticated corrections.

### Repair And Relay Without Replacing The Database

Keep `Sync.lua` as the transport owner; add a separately owned administrative
message handler rather than another competing send queue or standalone addon.
Reuse bounded chunking, roster/guild checks, throttling, and stale-work cancellation.
Add revision/digest inventories, requested transfers, bounded retries/provider
fallback, duplicate suppression, and startup/periodic reconciliation.

The maintainer previews and confirms a release before signing and publishing it.
Compatible receiving clients verify and automatically apply valid newer releases;
members do not need to edit saved files or approve each correction manually.
Stage a complete correction, validate it, then apply it atomically and rebuild
derived indexes. Retain a last-known-good correction state
and an audit record. Use targeted patches/tombstones for normal repairs and a
signed snapshot when a peer lacks the required patch base. Persist authority
revision and invalidations across alts/reloads so stale reports cannot resurrect
corrected data. Reserve broad resets for a confirmed need and preserve other data.

Peers relay signed records unchanged, including when the maintainer is offline.
Track unsupported, pending, applied, and rejected peers separately; API acceptance
does not establish receipt or application. SavedVariables persist on orderly
logout/reload, so an in-session acknowledgement is not proof of disk persistence.
Offline members catch up only when a retained peer is reachable; keep an external
release backup for recovery if every peer loses its copy.

Evaluate AceComm, LibSerialize, and LibDeflate only against demonstrated needs,
license/load-order requirements, and build-specific behavior. Libraries do not
provide administrative authority or conflict rules. Bound encoded, decoded, and
decompressed sizes and work. Never send executable Lua, run a received chunk, or
use guild messages to install addon/library code; those updates remain reviewed
addon releases. Compression and full-snapshot traffic are not defaults.

### Implementation And Validation Order

1. Restore the missing MoonSharp runner and ProfessionDB updater archive fixture;
   rerun the existing regression baseline and verify the two-client recipe
   lifecycle, targeted withdrawal, and failed-scan preservation in game.
2. Add owner revisions/digests, requested reconciliation, bounded retries/offline
   relay, and per-peer recipe application status through the shared transport.
3. The current reset gate and read-only role display now bind to the roster-verified
  `Pod Cast` identity. Next select/test signature verification, and specify
  authority versions, limits, key recovery, and all-client migration.
4. Implement authenticated targeted correction/import with preview, rollback, and
   persistence checks; add administrative snapshot/patch redistribution.
5. Implement and test the approved-main registry, lock transition, change requests,
   and administrator approval path before raid lockdown. Never activate a lock
   until participating clients understand and retain its policy.
6. Test forged/unsigned high revisions, tampered/replayed records, wrong guilds,
   conflicting equal revisions, missing bases, interrupted/reordered transfers,
   stale resurrection, main-change bypasses, authority offline, key rotation,
   and restored backups. Finish with restart, alt, restriction, and mixed-version
   checks on multiple clients.

## Source And Compatibility

The replacement [Discord source image](../discord2.png) and original
[Discord image](../discord.png) are preserved unchanged.
[The conversion tool](../tools/Convert-DiscordIcon.ps1) creates the packaged
`media/Discord.tga` from `discord2.png`: a 64x64, uncompressed 32-bit BGRA texture
retaining the source blue/white colours and alpha instead of forcing a white
silhouette. The converter checks the saved pixel bytes and verifies that the blue
background and white logo survive. Re-run the tool after
changing the source image. The main-character gold star uses WoW's existing
`Interface\TargetingFrame\UI-RaidTargetingIcon_1` texture; no extra star asset is
needed. It marks the addon-declared main and does not set an actual raid target
marker or imply a guild rank. Restart WoW after first adding the new
texture and verify both marks at normal/small UI scales.

- Library API inspected: [LibProfessionDB v1.10.0](https://www.curseforge.com/wow/addons/libprofessiondb/files/9619259),
  LibStub major `LibProfessionDB-1.0`, minor 14. The release is MIT-licensed;
  its [license notice](libs/LibProfessionDB-1.0/LICENSE) is retained. The import
  records 177 byte-verified upstream files, including 176 Lua scripts.
- That release declares 2,517 Forever recipes from build `1.60.1.70938`, matching
  the user's reported launch build, interface `16001`, project ID `18`.
  A matching data build or catalogue count is not proof that every
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

Background roster and synchronization updates do not rebuild hidden Guild or
Crafting pages. Visible-page update bursts are coalesced over 0.1 seconds;
opening a tab still refreshes its current data. Crafting aggregation deduplicates
each owner's recipe IDs without repeatedly scanning the accumulated crafter list,
and guild statistics reuse the directory's member rows.

Periodic recipe inventory validation processes at most one stored profile per
timer callback rather than serializing the entire guild cache in one frame.
Guild changes, crafting resets, and sharing opt-out cancel unfinished inventory
builds. Inventory exchange can therefore take additional frames in large guilds;
message formats, validation, and outgoing queue limits are unchanged. These
bounds reduce avoidable work but are not an in-game frame-time guarantee; live
Forever profiling is still required, especially during profession scans.

An arriving member's sync greeting schedules an inventory response independently
of the responding character's own profession scan. A peer holding verified
recipe revisions can therefore relay an offline guild member's recipes even
after reloading without opening its own profession windows. This is queued
catch-up, not immediate delivery: it includes the randomized greeting-response
delay, inventory preparation, and the outgoing message queue. Original owners
must remain in the verified guild roster, and both peers must have sharing
enabled. Legacy direct recipe packets without an original revision are not
eligible for relay until a verified inventory/snapshot exchange has completed.

[The package check](../tests/embedded_library_spec.ps1) verifies manifest order,
every imported file's checksum, the retained license, and the absence of a
standalone dependency. With `-MoonSharpPath` (or the local cached test DLL), it
also syntax-compiles every embedded Lua file without executing third-party code.
Actual library initialization and the full catalogue still need an in-game
check; mocked API tests do not prove that the embedded data loads in WoW.

[The offline suite](../tests/crafting_spec.lua) exercises optional library loading,
legacy paged-query compatibility, full scrolling queries, known-first ordering,
profession coverage, unique coverage counts, restricted data, draft preservation,
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
lua tests/map_spec.lua
lua tests/scanning_spec.lua
```

[Scan regression tests](../tests/scanning_spec.lua) cover sequential profession
capture, automatic opening/list updates, bounded loading retries, delayed-scan
cancellation, linked/guild/restricted source rejection, sharing opt-out,
background-capable clients, explicit profession unlearning, and reload retention.

[Map regression tests](../tests/map_spec.lua) cover online-only guild-zone
aggregation, profile/roster gates, restricted map data, ambiguous zone names,
continent totals, native tile order and edge cropping, map navigation, pin
tooltips, internal marker toggles, bounded roster requests, and absence of native
world-map overlays or hooks.

[Member regression tests](../tests/members_spec.lua) cover main replacement,
alt association, default-main statistics, Discord clearing, guarded talent-group
counts, staged/unknown/tied/zero talents, member message reassembly, revision
ordering, guild scopes, profile editing, drafts, pooled directory scrolling/filtering,
scrollbar/wheel input, roster-shrink clamping, and cached-only row rendering.
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
  `/hordeeternal library` reports a ready library and the pinned snapshot's 2,517
  recipes. Check the source label and repeat with a standalone copy if used.
2. Browse Herbalism and Skinning camp recipes, search globally, and scroll through
  a large recipe list. Verify each gathering profession's catalogue includes
  three recipes without fabricating learned guild ownership.
3. Check images, item effects, long names, and material names with a cold cache.
4. Hover and click Rescan; confirm the tooltip and successful guild publication.
  Open Enchanting, then Alchemy (or another pair) without clicking Rescan. Verify
  both sets of learned recipes remain visible locally, on an alt, and on another
  upgraded guild client. Repeat with a cold cache, a rapid switch/close, and a
  linked profession. Check whether a fresh login can read those professions
  without opening windows; do not infer that capability from the mock tests.
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
9. On upgraded test clients, create a reset as Pod Cast and confirm other
  characters cannot create one. Verify settings remain unchanged. Keep one peer
  online, log the owner out, then log an older-generation character in and check
  that it adopts the peer's generation and rebuilds only its own crafting data.