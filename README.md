# Saboton Essentials

A World of Warcraft Forever / Classic+ addon for small, reactive audio and animation moments. Built as a collection of independent modules under a shared `/saboton` command, so new features can be added without touching existing ones.

## AI disclaimer

Generative AI was heavily utilized in creation of this mod and the modules below.

## Modules

### Squeaky Toy (`squeak`)

When a player of a configurable class (Mage by default) in your party or raid dies, play a configurable sound (Squeaky Toy by default, or the "Ka-ching!" sound). Optional hostile and friendly death triggers are for testing and require a readable GUID and a matching visible unit token; secret values cannot be matched.

### Extra Attack (`extraattack`)

When the player gets an extra attack (Windfury, Hand of Justice, Ironfoe, Sword Specialization, etc.), play a sound and track a combo streak on-screen. The combo text arcs rightward on each hit, then fades after the movement and streak window finish. Its position, movement time, and fade time are adjustable in Options. Detection uses early main-hand `PLAYER_SWING` events as a heuristic for extra attacks and `SPELL_UPDATE_COOLDOWN` for Windfury Totem (spell 10608, one hit) and Windfury Weapon (spell 439440, two hits). Unusual swing timing may affect the swing-based detection. Multiple hits play a staggered, rising sound cascade after a short settle window.

### Gathering Timer (`gather`)

Starts two countdown bars (min and max respawn) when you loot a tracked ore or herb node. It is off by default and can be enabled in Options or with `/saboton gather enable`. Direct node-spawn detection is not possible on the Forever client (no game-object enumeration, no spawn event, no minimap-blip read), so it's timer-based: the loot of a tracked gatherable is the trigger. The min bar ("node may be up") and max bar ("gone / taken") are independent — each can be toggled off, has its own duration, and plays its own sound (bell chime and impact thud by default). The bar frame is movable (drag while unlocked, out of combat only), resizable, and can fill horizontally or vertically. Each gatherable (Thorium, Arcane Crystal, Black Lotus, etc.) can be toggled on or off individually.

### Spy Enhancement (`spyenhancement`)

Adds manual, bidirectional guild sync for Spy's existing player KoS and watched-guild lists, with optional player KoS reasons. It compares content fingerprints, requests missing/different records, and confirms an exchange only after peer acknowledgment. Combat and chat restrictions defer sending and imports; throttling and lost acknowledgments use bounded retries. An offline or restricted peer may require another manual sync.

Use Spy's UI and commands to manage those lists. There is no second KoS list, guild list, or list editor; the Saboton dashboard controls synchronization only. Imports are additive: existing entries/reasons are preserved, and other players cannot delete your entries. **Names are shared by default. Share KoS reasons is off by default; enabling it also publishes player preset reasons and custom Other text to guild peers. Guild reasons and unrelated metadata are not shared.** Removing an imported entry in Spy suppresses its return on subsequent syncs; `allowsync` or manually re-adding it permits sharing again.

Incoming player reasons only fill an absent or empty reason table, including when both clients already have the target. **Any non-empty reason on the receiver wins in its entirety**: no merging, replacement, or remote clearing, even if it differs from the sender or was imported earlier. The decision is made when applying the record, so local edits during a transfer are protected. Receiving reasons is enabled with guild sync independently of outbound reason sharing. Turning sharing on or off cancels pending local work; start a fresh sync afterward.

Preset reason labels are retained as sender text; custom Other text is stored under the receiver's localized Other label. Sync allows at most 64 reasons per player, 512 bytes per preset label, 2,048 bytes of custom text, and 4,096 bytes for the complete encoded reason field (hex encoding and headers count toward this total). Unsupported/oversized reasons fail visibly rather than being truncated. Leaving sharing off still permits names-only sync of those entries.

Player imports populate both Spy's KoS membership and the player metadata/KoS marker used by its menu, including its central character-sharing store when enabled. Beta.5 also repairs incomplete metadata left by earlier imports after settings restoration, or once local restrictions clear. This repair preserves existing metadata and KoS timestamps and does not restore names you removed. No fresh transfer is required for names already present and tracked as imports.

All participants need the v4 implementation in beta.6 or later; old v2/v3 clients cannot participate, even for names-only sync. Exchanges use the guild addon channel, validate the guild roster and Spy list scope, and preserve Forever's `First-Surname` identities and ruleset-wide storage. No automatic login/change sync is implemented, and completion does not mean every guild member has converged. These are guild-channel messages, not encrypted private transfers.

Cyrillic analysis can classify names or guild names when they contain Russian- or Ukrainian-specific letters; shared Cyrillic letters are reported as unclear. These are language-character indicators, not proof of a player's nationality.

#### Sync quick start and recovery

1. Install Spy and Saboton Essentials beta.6 or later (v4 protocol) on both clients. Both characters must be in the same guild and use the same Spy ruleset/list scope.
2. Open `/saboton spyenhancement options` on each client and leave **Enable guild sync** checked. This enables replies and imports as well as manual starts.
3. Press **Sync Now on one client**. Either client can initiate, regardless of which has more entries; the exchange is bidirectional. Discovery normally takes at least 12 seconds after its first message is submitted, followed by paced transfers.
4. Wait for a confirmed exchange. For example, 9 targets on one client and 1 already shared target on the other should leave both with 9, unless a missing name is locally suppressed.

To send player KoS reasons, check **Share KoS reasons** on the sending client before starting. The receiver can leave that sharing option off; its existing non-empty reasons still take priority. Reason-only updates do not increase the imported-name count. Different preserved reasons can produce another record exchange on later syncs; confirmation means the receiver accepted its local-wins policy, not that conflicting reasons became identical.

Repeated button presses do not create additional rounds while work is active. Simultaneous initiators use deterministic ordering; discovery is bounded to 32 peers. This does not elect a permanent guild leader or automatically distribute the final union back to every participant.

| Status or symptom | Meaning / next step |
| --- | --- |
| Queued / offering / responding | Discovery is in progress, not confirmation of a transfer. An abandoned responder returns to idle after 3 unrestricted local minutes. |
| Deferred: combat/chat restriction or chat lockdown | Leave the request queued; it resumes when the local restriction clears. |
| Known peers: 0 | No previous confirmed peers are recorded; this is not a count of clients currently detected online. |
| 0 queued bytes | No session payload bytes are queued. Discovery messages and outstanding replies are not included in this number. |
| No confirmed peers / peer timeout | Check that the peer is online, enabled, updated, in the same guild/scope, and unrestricted; then retry manually. |
| Disconnect / cancel / reload | Already applied imports remain; partial exchanges are not reported as confirmed. Reload clears network work, so initiate a fresh sync afterward. |

Unresponsive sessions are released after 3 minutes without a new valid page or matching acknowledgment, or sooner when the roster explicitly reports a disconnect. Local combat/chat pauses do not consume the progress timeout; remote restrictions can still cause the other client to time out. There is also a two-hour absolute lifetime. Other available peers can continue, without an automatic retry loop.

For troubleshooting, enable `/saboton spyenhancement debug` on both clients **before** starting a fresh sync. It immediately prints identity/roster/state information, then logs sends, receives, and rejection/arbitration decisions, capped at 200 lines per enable. Capture both clients' output and `/saboton spyenhancement status`. Run the debug command again to disable it; logging is not restored after reload. Logs include character identities and guild scope, so review them before sharing.

### Options (`options`)

When Blizzard's Settings API is available, a shared panel lists module options under Game Menu > Options > AddOns > Saboton Essentials. Without that API, `/saboton options` and the minimap button open a smaller panel with the four Extra Attack text position and timing sliders and a Spy Enhancement dashboard launcher; remaining settings use slash commands.

Spy Enhancement has a dashboard in its Settings subcategory, also available through `/saboton spyenhancement options` or `/saboton options spyenhancement`. Without canvas Settings support, the same dashboard opens in a fallback window; the shared fallback options include a launch button. It provides sync, reason-sharing, and notification checkboxes with explanatory tooltips, **Sync Now**, **Cancel**, live state/list counts/requested-name progress, last confirmed exchange, and a paged suppressed-name list with **Allow again**. Allowing a name does not immediately import it; run another sync. Progress is per active exchange, not a promise of guild-wide convergence.

### Minimap Button (`minimap`)

A draggable minimap button (Thunder Clap icon) that opens the Options panel when clicked. Can be dragged around the minimap, and hidden via a checkbox in Options or `/saboton minimap`.

## Installation

Place this folder under the active client's `Interface\AddOns` directory. For the Forever beta, for example:

```text
World of Warcraft\_classic_beta_\Interface\AddOns\SabotonEssentials\
```

Restart the game or run `/reload`.

## Configuration

The addon includes `Media\squeak.mp3`, `Media\kaching.mp3`, `Media\HumanMaleAggroA.ogg`, `Media\clear-bell-chime.mp3`, and `Media\impact-thud.mp3`. Missing or unsupported sound files produce a chat warning.

Settings, custom gatherables, and frame positions are stored in the account-wide `SabotonEssentialsDB` SavedVariables database. WoW writes it on `/reload` or a normal logout and restores it when the addon loads. The addon kit documented a bug in Forever beta build 1.60.1.69893 where the client writes SavedVariables but does not load them again; its status on later builds is not established here. On an affected build, these settings can still reset despite being saved. There is currently no built-in workaround.

## Commands

All commands go through `/saboton <module> <command>`.

- `/saboton help` - list available modules
- `/saboton squeak status` - print the current trigger and sound configuration
- `/saboton squeak test` - play the configured sound
- `/saboton squeak debug` - toggle debug messages
- `/saboton squeak mages` - toggle the friendly-class-in-party/raid trigger (on by default)
- `/saboton squeak hostile` - toggle playing the sound on any hostile unit's death (off by default, for testing)
- `/saboton squeak friendly` - toggle playing the sound on any friendly unit's death (off by default, for testing)
- `/saboton squeak class <token>` - set which class triggers the friendly-death sound (e.g. `MAGE`, `WARRIOR`); also available as a dropdown in Options
- `/saboton squeak sound <none|squeak|kaching>` - set which sound plays; also available as a dropdown in Options
- `/saboton extraattack status` - print the current enabled state, sound, text, combo window, and combo count
- `/saboton extraattack test` - simulate an extra-attack proc (plays the sound and updates the combo)
- `/saboton extraattack enable` - toggle the entire module on/off (on by default); also available as a checkbox in Options
- `/saboton extraattack debug` - toggle swing and burst diagnostics
- `/saboton extraattack window <seconds>` - adjust the combo streak's reset window (default 1 second)
- `/saboton extraattack text` - toggle the on-screen combo text (on by default); also available as a checkbox in Options
- `/saboton extraattack textformat <format>` - customize the combo text, `%d` is replaced with the combo count; also editable as a text box in Options
- `/saboton extraattack xoffset <number>` / `yoffset <number>` - shift the entire combo-text arc horizontally or vertically in UI units; positive values move right or up. Also available as sliders in Options
- `/saboton extraattack sound` - toggle the sound (on by default); also available as a checkbox in Options
- `/saboton extraattack soundkey <none|kaching|squeak|huagh>` - set which sound plays; also available as a dropdown in Options
- `/saboton extraattack stagger <seconds>` - time between the sounds of a multi-hit burst (default 0.09s); also available as a slider in Options
- `/saboton gather status` - print the current state, active timer, and which gatherables are tracked
- `/saboton gather test` - start short test bars (5s / 10s) without needing a node
- `/saboton gather clear` - stop and hide the current timers
- `/saboton gather enable` - toggle the module on/off
- `/saboton gather debug` - toggle debug messages
- `/saboton gather lock` / `unlock` - lock or unlock the bar frame for dragging (out of combat only)
- `/saboton gather width <px>` / `height <px>` - resize the bars
- `/saboton gather orient <h|v>` - horizontal or vertical fill
- `/saboton gather min <seconds>` / `max <seconds>` - set the respawn window for active and future timers; 0 disables that bar
- `/saboton gather minsound <key>` / `maxsound <key>` - set the expiry sounds (`ding`, `thud`, `kaching`, `squeak`)
- `/saboton gather toggle <name|id>` - toggle tracking for one gatherable (e.g. `toggle thorium`)
- `/saboton gather add <id|name> <ore|herb> <min> <max>` - add a custom gatherable
- `/saboton gather list` - list all gatherables and their state
- `/saboton spyenhancement sync` - manually reconcile Spy's KoS players and watched guilds with available guild peers; queues while restricted
- `/saboton spyenhancement options` - open the sync dashboard, including fallback UI when needed
- `/saboton spyenhancement cancel` - cancel queued/in-progress local sync work (already imported entries remain)
- `/saboton spyenhancement allowsync [player|guild] <name>` - allow a removed imported name to return on the next sync
- `/saboton spyenhancement status` - show Spy list counts, sync status, and Cyrillic cache counts
- `/saboton spyenhancement debug` - toggle session-only sync chat diagnostics (200-line limit per enable); shows identity/roster, send results, incoming frames, rejection reasons, and concurrent-start decisions. Enable on both clients before reproducing, then share the output. Status also includes send-call and received-frame counts. Diagnostics include character identities and guild scope, but not KoS target names or reason text.
- `/saboton spyenhancement detect [player|guild] <name>` - analyze one player or guild name
- `/saboton spyenhancement detectkos` / `detectguilds` - scan Spy's KoS players and watched guilds for Cyrillic names
- `/saboton spyenhancement cyrillicstats` / `clearcyrillicache` - show or clear nationality-analysis cache
- `/saboton minimap` - toggle the minimap button's visibility; also available as a checkbox in Options
- `/saboton options` - open the shared settings panel

## Technical notes

- Lua 5.1-compatible WoW addon code
- `src\Core.lua` bootstraps the shared namespace, module registry, slash command dispatcher, and settings persistence.
- Each feature lives in its own file under `src\Modules\` and self-registers via `addon.RegisterModule(name, module)`; a module implements `OnEnable()` (called once on `ADDON_LOADED`) and `HandleCommand(message)`
- A module can optionally implement `GetOptionsSchema()` to appear in the settings panel (see `src\Options.lua`); this is the only integration point between modules and the UI
- A schema may provide a `dashboard` with view/actions and suppressed-entry callbacks. Options renders the same controls in a canvas Settings category or fallback window, keeping widget code out of feature modules. Refresh runs once per second only while the dashboard is visible.
- Squeaky Toy uses the `UNIT_DIED` frame event (as of Patch 12.0.0/Midnight, addons can no longer register `COMBAT_LOG_EVENT_UNFILTERED`)
- Spy Enhancement requires Spy for KoS/watch-list access; Spy is an optional load-order dependency so the other modules work without it. Sync uses native messaging and timers, not an incidental Ace library installation.
- Forever's space-separated guild-message names are normalized to Spy's `First-Surname` identities for self-filtering and peer routing; surnames are never treated as internal realms.
- `src\Support\GuildSync.lua` handles bounded, paced guild exchanges with provider callbacks. Each frame is at most 255 bytes; native sends are spaced by at least 1.25 seconds, with server-result backoff. Records up to 8,192 bytes use acknowledged continuation chunks; requested records are streamed one at a time. Snapshots are limited to 500 players and 500 guilds. Large reconciliations, particularly with reasons, can take many minutes; restrictions and server throttles can extend that time.
- Discovery keeps up to 32 peers, coalesces repeated starts, and shares send opportunities with long transfers. Disconnected peers release their queues on roster updates, or after 3 minutes without progress if no disconnect event arrives. Local combat/chat pauses do not consume that timeout; a remotely restricted peer may need a later manual retry. Imported names survive interruption. This is best-effort per-peer reconciliation, not guaranteed all-to-all convergence in one guild-wide round.
- Combat and active chat lockdown still pause sync. Forever's broad outgoing-restriction flag is not used as a preflight veto: native send results determine whether submission is allowed, and peer acknowledgments determine success.
- Sync starts listening only after saved settings are restored. No network queue survives reload; imported-name suppression and confirmed-peer metadata do. The [implementation plan](docs/GUILD_SYNC_IMPLEMENTATION.md) documents the protocol, bounds, and remaining two-client Forever checks.
- Uses `UnitGUID` to confirm the dead unit is in the current group for the friendly-mage trigger
- The hostile/any-friendly testing triggers additionally scan target/focus/mouseover/nameplate/boss/arena unit tokens, since those deaths aren't limited to the group
- Uses `UnitClass` to check the matched group member's configured class.
- Extra Attack cannot use combat log events (addons can no longer register `COMBAT_LOG_EVENT_UNFILTERED`). Its previously tested `COMBAT_TEXT_UPDATE` fallback did not fire for real procs on the tested Forever client and has been removed.
- The legacy `PLAYER_SWING(swingDuration, swingType)` detector catches extra attacks such as Hand of Justice and Ironfoe: an extra attack lands as a main-hand swing far earlier than the current swing duration allows. A threshold under 50% of the expected interval excludes parry-haste false positives; swing duration is learned from the event itself so haste/Flurry are tracked without touching `UnitAttackSpeed` (secret in combat). Windfury Totem (spell 10608) and Windfury Weapon (spell 439440) are detected separately from their `SPELL_UPDATE_COOLDOWN` events; Weapon counts as two hits.
- Gathering Timer reads loot slots on `LOOT_READY`/`LOOT_OPENED`. When a readable source GUID is available, non-`GameObject` sources are rejected; otherwise the item match is used. Reopening a node restarts the timer, so the final pick wins.
- Gathering Timer uses `C_Timer` and StatusBar frames; dragging is gated on `InCombatLockdown()`.
- `src\Options.lua` builds the shared settings panel using Blizzard's `Settings` API (`Settings.RegisterVerticalLayoutCategory`/`Settings.RegisterProxySetting`/`Settings.CreateCheckbox`/`Settings.CreateSlider`/`Settings.CreateDropdown`); it reads a `GetOptionsSchema()` method from any module that implements one and never touches module internals directly, keeping UI code separate from feature logic
- The vertical-list Settings API has no built-in free-text control, so a schema option of `type = "text"` is rendered via a small custom row template (`SabotonTextInputControlTemplate` in `src\Options.xml`), styled and positioned like the built-in checkbox/slider/dropdown rows, backed by `SabotonTextInputControlMixin` in `src\Options.lua`
- Where Blizzard's `Settings` API is unavailable, the Options command opens a small window for the combo-text position and timing sliders, plus a Spy dashboard launcher. The Spy dashboard also opens directly via its options command; use slash commands for remaining settings.
- The minimap button repositions itself by tracking cursor angle around the `Minimap` frame during drag (the common community pattern also used by libraries like LibDBIcon); it opens Options by calling `addon.modules.options:HandleCommand()` directly rather than touching the `Settings` API itself, keeping Settings-API code confined to `src\Options.lua`

## Tests

Run the Lua files in `tests/` from the addon root with a Lua interpreter. They use mocked WoW APIs and do not replace in-game testing. For example, with Node.js available, run `npx --yes --package fengari-node-cli fengari tests/test_gathering_timer.lua`.

The guild-sync tests simulate multiple clients, restrictions, lost data/ACKs, throttling, concurrent initiators, invalid records, and transfer limits. Run `tests/test_guild_sync.lua` for the transport, `tests/test_guild_sync_recovery.lua` for twenty-client bursts, disconnects/reconnects and exact idle-timeout boundaries, `tests/test_spy_enhancement.lua` for the Spy adapter, and `tests/test_spy_options.lua` for modern/fallback dashboard controls, alongside the persistence/core tests. Basic two-client transfers were confirmed in-game on beta.3; twenty-client load, Forever sender/receiver combat, roster behavior, and visual layout still require in-game validation before release.

All ten Lua test suites passed with Fengari after the hardening changes. The recovery tests verify bounded queue drainage and successful transfers under their simulated conditions, not guaranteed all-to-all convergence or real server throughput.

## Releases

To create a ZIP locally on Windows for manual CurseForge upload, run from the addon root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\package-release.ps1
```

The script reads the TOC version and writes `releases\SabotonEssentials-<version>.zip`. The `releases` directory is ignored by Git. It packages the current working files, including uncommitted changes, and refuses to overwrite an existing ZIP; move or remove that ZIP to rebuild the same version. Run the tests and check the addon in-game before uploading.

The latest packaged test build is `0.3.0-beta.6`, including opt-in KoS reason sharing over the incompatible v4 protocol, burst/disconnect hardening, and the Spy KoS-menu metadata fix/repair. Update both clients together. Existing archives are not updated when source or documentation changes.

Releases use the [BigWigs WoW Packager](https://github.com/BigWigsMods/packager). It builds a ZIP containing the `SabotonEssentials` addon directory, detects Forever from interface `16001`, and generates release notes from Git history. Tests and original media sources are excluded from the ZIP.

1. Update `## Version` in `SabotonEssentials.toc` and commit the change. The first release is `0.1.0`.
2. Create and push an annotated tag matching the version, for example `git tag -a v0.1.0 -m "Release 0.1.0"` followed by `git push origin v0.1.0`.
3. GitHub Actions runs the Lua tests, verifies the archive, and publishes it as a GitHub release and workflow artifact. Tags such as `v0.2.0-beta.1` or `v0.2.0-alpha.1` are marked as prereleases; the TOC version must match without the leading `v`.

For automatic CurseForge uploads, create the WoW addon project on CurseForge, add its numeric project ID as the GitHub Actions repository variable `CURSEFORGE_PROJECT_ID`, and add an [author API token](https://authors.curseforge.com/#/settings/api-tokens) as the repository secret `CF_API_TOKEN`. Both are required if either is configured. Without them the workflow still publishes the ZIP on GitHub, where it can be downloaded and uploaded manually. CurseForge processes and may review uploaded files before publication; check that it lists the intended Forever game version. Re-running a successful CurseForge upload can create a duplicate file.

The [CurseForge upload API](https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api) is separate from the public CurseForge mod-distribution API. The packager assigns the release type from the tag and looks up the game version using the TOC interface number. Update the interface only after testing against the target client.

For project submission, CurseForge requests an English description, an appropriate license and categories, and an original square PNG logo of at least 400x400 pixels. Verify that all bundled media can be redistributed. CurseForge's WoW processor expects a ZIP with folders at its root and a case-matching `SabotonEssentials/SabotonEssentials.toc`. New projects need an approved release or beta file to sync to the CurseForge app. See the [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips), [file types](https://support.curseforge.com/support/solutions/articles/9000197242-file-project-types-and-additional-fields), and [WoW file processor rules](https://support.curseforge.com/support/solutions/articles/9000210425-curseforge-file-processor-errors-per-game).
