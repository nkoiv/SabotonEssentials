# Saboton Essentials

A World of Warcraft Forever / Classic+ addon for small, reactive audio and animation moments. Built as a collection of independent modules under a shared `/saboton` command, so new features can be added without touching existing ones.

## AI disclaimer

Generative AI was heavily utilized in creation of this mod and the modules below.

## Modules

### Squeaky Toy (`squeak`)

When a player of a configurable class (Mage by default) in your party or raid dies, play a configurable sound (Squeaky Toy by default, or the "Ka-ching!" sound). Optional hostile and friendly death triggers are for testing and require a readable GUID and a matching visible unit token; secret values cannot be matched.

### Extra Attack (`extraattack`)

When the player gets an extra attack (Windfury, Hand of Justice, Ironfoe, Sword Specialization, etc.), play a sound and track a combo streak on-screen. The combo text arcs rightward on each qualifying hit, then fades after the movement and streak window finish. Its position, movement time, and fade time are adjustable in Options. Detection uses early main-hand `PLAYER_SWING` events as a heuristic for extra attacks and `SPELL_UPDATE_COOLDOWN` for Windfury Totem (one hit per proc; each totem rank uses its own proc spell: 8516, 10608, 10610) and Windfury Weapon (two hits per proc; rank spells 8232, 8235, 10486, 16362, plus proc spell 439440). The optional, experimental "Count Seal of Command procs" setting is off by default and counts a cooldown update for observed proc spell 20424 as one extra attack; seal activation and Judgement spells are ignored. Whether other ranks use the same proc ID on Forever still needs in-game verification. Unusual swing timing may affect the swing-based detection. Multiple hits play a staggered, rising sound cascade after a short settle window. The minimum extra attacks for sound and text is adjustable from 1 to 10 (default 1); only hits in the same burst count toward the threshold. Text appears as soon as the burst qualifies and shows the full combo streak, including hits from smaller bursts. A burst settles after 0.15 seconds without another hit, independently of the combo streak window.

### Gathering Timer (`gather`)

Starts two countdown bars (min and max respawn) when you loot a tracked ore or herb node. It is off by default and can be enabled in Options or with `/saboton gather enable`. Direct node-spawn detection is not possible on the Forever client (no game-object enumeration, no spawn event, no minimap-blip read), so it's timer-based: the loot of a tracked gatherable is the trigger. The min bar ("node may be up") and max bar ("gone / taken") are independent — each can be toggled off, has its own duration, and plays its own sound (bell chime and impact thud by default). The bar frame is movable (drag while unlocked, out of combat only), resizable, and can fill horizontally or vertically. Each gatherable (Thorium, Black Lotus, etc.) can be toggled on or off individually.

**Gathering celebrations:** While the module is enabled, receiving an enabled item from a game-object loot window plays its chosen sound and shows a brief, non-interactive sparkle burst. Arcane Crystal (12363), Fel Crystal (248819), and Black Lotus (13468) are enabled by default with Ka-ching; other listed or custom gatherables default off. Each item has its own toggle and sound in Options, independent of whether its respawn timer is tracked. Choose **No sound** for sparkles only. Use `/saboton gather testcelebration Fel Crystal` to preview an item's effect and sound without gathering it, even when the module or that item's celebration is disabled.

Celebrations wait for a localized self-loot chat message and a matching item previously seen in a game-object loot window; merely opening a node does not trigger them. Duplicate loot-window events do not repeat the celebration. A message arriving within two seconds of closing the window can still match. If the client hides the loot source or self-loot message, the celebration cannot be confirmed; in-game behavior still needs verification on Forever. Custom gatherables added through the command become available in Settings after reloading the UI; the slash commands work immediately.

### Mob Spawn Timer (`mobtimer`) - experimental

Open `/saboton mobtimer options` to add or edit up to 30 unique mob names with minimum and maximum durations in seconds. Use the sliders for coarse adjustment or type exact values from 1 second to 7 days, then press Save. The Settings page also has a management button; the fallback options window has a launcher. To add the current creature directly, use **Add target** in the editor, **Add current target to mob timer** in the minimap menu, or `/saboton mobtimer target`. Its readable name and creature GUID are required; duplicates are rejected. New entries default to 10 and 15 minutes (600 and 900 seconds) and can be edited afterward. Adding a target tracks it but does not start a timer until a death is detected or it is started manually.

Automatic death detection is enabled by default for configured names. The addon observes readable creature names and GUIDs from target, focus, mouseover, nameplates and boss tokens, then starts the matching timer when `UNIT_DIED` supplies that GUID. Matching is exact and case-insensitive; enter the name as shown by your client. Recently observed identities are retained for up to 30 minutes (bounded to 256 identities), so the mob need not remain targeted. The death event must reach your client, and both its GUID and an observed matching identity must be readable. An unobserved, out-of-range, phased or secret mob may be missed; duplicate death events for a GUID are ignored for up to 30 minutes. Use `/saboton mobtimer status` to see registration and session counters; `/saboton mobtimer enable` toggles detection. If event registration fails the addon reports it, and manual timers remain usable. Automatic detection still requires in-game testing.

Select an entry with the arrows and use **Test 5s/10s** or **Start manual** to preview two bars. Multiple mobs can run concurrently; a new detected death or manual start for the same entry replaces its timer. This is one timer per name, not per spawn location or creature instance. Editing an entry does not change its running timer, and removing it clears its timer. Timers are estimates only and do not detect respawns. Settings and entries are saved, but active timers and observed identities do not survive reload. Unlocking shows a draggable placeholder when no bars are visible; dragging is disabled in combat. Appearance, sounds and minimum/maximum visibility are separately configurable from gathering.

Commands: `/saboton mobtimer target`, `enable`, `status`, `add <name> <min seconds> <max seconds>`, `edit <name> <min> <max>`, `list`, `test <exact name>`, `start <exact name>`, `remove <exact name>`, `clear`, `lock`, `unlock`, `width <60-500>`, `height <8-60>`, `orient <h|v>`, `minbar`, `maxbar`, `minsound <key>`, and `maxsound <key>`. Sound keys are `none`, `ding`, `thud`, `kaching`, `squeak`, and `huagh`.

### Mob death probe (`mobprobe`) - experimental

This session-only diagnostic compares `UNIT_DIED`, `UNIT_HEALTH` / `UNIT_FLAGS`, and a half-second `UnitIsDeadOrGhost` poll for a manually watched target. It does not start spawn timers or save its results. Event registration is attempted only when started; the restricted combat-log event is never registered.

1. Run `/saboton mobprobe start`, target a **living** mob, then run `/saboton mobprobe watch`. Check that the reported GUID is readable and the initial state is alive.
2. Kill it while targeted. Run `/saboton mobprobe status` and note whether `UNIT_DIED` matched, a unit event reported a transition, and polling reported a transition.
3. Repeat with a new living target and `/saboton mobprobe watch`: let another player kill it, or remove your target while its nameplate remains visible. Finally try a kill after the watched mob is no longer visible. Compare the output; "cached identity matched" means the event matched the GUID captured at watch time, but no current token was found.
4. Run `/saboton mobprobe status` before `/saboton mobprobe stop` and share the output and the test conditions. Counts are cumulative since `start`, including unrelated unit events; stop and start between scenarios for separate counts. Live messages are capped at 40 per session. A secret or missing GUID cannot be matched, and a dead observation after an unreadable state is not proof of an observed death transition.

The probe prints the watched name and diagnostic results in chat but does not print GUIDs. Review chat before sharing it. `/reload` stops the probe and discards results. No result guarantees detection of distant or unobserved deaths, or that a timer predicts an actual spawn.

### Tank Target (`tanktarget`)

Nameplate unit tokens are read from `namePlateUnitToken`, then `UnitFrame.unit` (observed on Forever instance plates), with numbered-plate lookup as a final fallback. This allows other tanks' targets to be matched without selecting those mobs yourself when the client exposes a usable token and permits native secret visibility.

**Hostile targets only** is enabled by default in Options; toggle `/saboton tanktarget hostile` to change it. It hides the shield, initials, and threat text on non-enemy targets using the game's `UnitIsEnemy` check, not merely whether a unit can be attacked. Unknown hostility is hidden; secret hostility uses native visibility when supported. The setting is saved; existing saved preferences are preserved.

For groups without a tank, turn off **Guess a tank when no group tank is assigned** in Options or toggle `/saboton tanktarget guess`. This stops the threat-holder, recent-threat and only-tank-capable-class guesses, so a DPS Warrior, Paladin or Druid is not automatically marked as a tank. Manual selection, assigned TANK roles (including cached roles), main-tank assignments and the separate solo-pet setting still work. The option is saved and defaults on to preserve existing behavior. With no detected tank, current-target-only threat is hidden; the separate all-nameplate threat option still works.

When a tank is detected, an optional label shows **your threat on your current target**, for example `Threat 75%`, even if the tank targets another enemy or has no target. Tank initials belong to the separate shield, not this percentage. Enable **Show threat on all nameplates** (saved, off by default) to query each visible plate's own mob, even without a detected tank. The master threat toggle and hostile-only filter still apply. Both modes require a living, attackable unit: `UnitCanAttack` and `UnitIsDeadOrGhost` suppress labels on interactable objects, friendly units, and corpses without comparing restricted health values. Missing unit tokens or unknown eligibility hide the label; unavailable threat on an eligible unit still shows gray `?`, never a copy of your current target's percentage. Secret eligibility uses separate native visibility gates, preserving the tank's threat/lead selection; unsupported or rejected checks hide the label and report the error. This filter affects threat labels, not tank shields or the forced-shield diagnostic. By default, non-tanks see scaled threat (100% means pulling aggro): green below 50%, yellow from 50% through 80%, red above 80%. Raw mode instead compares your threat with the current aggro holder. Readable, confirmed DPS aggro shows red `AGGRO`; when the aggro flag is secret, the percentage remains displayed without guessing.

For rendering diagnostics, `/saboton tanktarget testshields` forces a shield labeled `TEST` on every enumerated nameplate. It bypasses tank detection, target matching, unit-token requirements, and hostile filtering, and suppresses threat labels during the test. The module must remain enabled. Run the command again to restore normal display; this diagnostic resets on reload and is not saved. If only your current target renders a forced shield, the remaining problem is in rendering/plate enumeration rather than tank matching.

If you are the selected/manual tank or have the TANK role and hold aggro, the label becomes `Lead 140%`: your raw threat relative to the next-highest unit. **140% means 1.4 times their threat, not 140% extra**. Lead colors are red below 120%, yellow from 120% through 150%, green above 150%. A tank who loses aggro sees `Threat` with raw threat and tank colors, so low threat stays red. A DPS pulling aggro never switches to reassuring tank colors. A readable player TANK role is remembered while the role is hidden.

The display toggle, percentage mode, and both pairs of thresholds are available in Options and through the commands below. Moving one Settings boundary past the other adjusts its neighbor to keep them ordered. Unknown/unavailable threat (including a readable zero lead with no competitor) shows a gray `?`; threat is never cached. Secret percentages go directly into native formatted text and use neutral white instead of threshold colors: Forever rejects secret inputs to addon color curves. Secret aggro-holder booleans select two overlapping labels through native alpha. Restricted rendering still requires in-game Forever validation. Unsupported events and update/render failures are reported once per distinct error, or on every occurrence with debug enabled. Secret target matches are hidden on clients without native boolean alpha support rather than marking every candidate plate.

The shield has the detected tank's first-name and surname initials beneath it: `L.J.` for Leeroy Jenkins or `A.R.` for Agg Rend. Like Spy Enhancement, it treats the second return from `UnitName` as a surname only when `RegionalUniqueNamesEnabled()` is true; combined `First Last` and `First-Last` names are also supported in that mode. Realm names are not used as initials. An unavailable surname leaves the first initial alone (for example `L.`); an unreadable first name uses `?` rather than another tank's initials. Accented initials are preserved. The shield and halo are neutral white; a breathing pulse means you share the tank's target, not that the tank holds aggro. Only the threat text uses green/yellow/red safety colors. Initials hide with the shield, independently of the threat-text toggle. Raid-marker tinting has been removed: Forever returned secret marker indices even outside combat and rejected their use in addon color curves.

When matches are readable, multiple tanks targeting the same mob share **one shield with a comma-separated initials list**, for example `A.Z., L.J.`. Restricted matches instead use individual shield-and-initial rows whose visibility is controlled by the game. Fixed row slots can leave gaps: Lua cannot inspect secret visibility to compact the list. Tanks targeting different mobs get separate shields. Initials are sorted by readable full name so roster-slot changes do not shuffle the list. All detected role tanks are cached individually while their roles are secret; readable role changes and departures remove them. `/saboton tanktarget status` lists every tracked tank.

Marks tanks' current targets, not the mobs' targets or aggro holders. Detection runs in priority order: a manually picked tank (`/saboton tanktarget tank <name>`, tracking only that tank), all assigned TANK roles (including cached roles), all old-school main-tank assignments when no role tanks are available, then a single heuristic tank from threat (Warrior/Paladin/Druid or a pet, remembered for 15 seconds), the only tank-capable class in the group out of combat, or your own pet while solo (toggleable). Matching prefers direct tank-target plate lookup. If unavailable, your current plate uses `UnitIsUnit("target", tankTarget)` directly; other plates use readable GUIDs then nameplate-token comparisons. Secret booleans go directly to native `SetAlphaFromBoolean`, on the main shield for one tracked tank or on individual rows for multiple tanks. This does not read or reconstruct secret values. If Forever rejects native visibility, that shield or row is hidden and the error reported; your threat label remains independent. A secret boolean being available does not guarantee the client allows an addon to render it; instance support still needs in-game validation, including a sole remote tank. The mark is parented to the plate itself and anchors to whatever health bar is visible, so it survives nameplate addons (Plater, ElvUI, KUI, TidyPlates). The enabled state, solo-pet handling, and mark size are configurable in Options. Credit: the tank-target detection and secret-safe matching logic is based on the ScryWoW addon, which had this feature first.

### Spy Enhancement (`spyenhancement`)

Adds manual, bidirectional guild sync for Spy's existing player KoS and watched-guild lists, with optional player KoS reasons. It compares content fingerprints, requests missing/different records, and confirms an exchange only after peer acknowledgment. Combat and chat restrictions defer sending and imports; throttling and lost acknowledgments use bounded retries. An offline or restricted peer may require another manual sync.

Use Spy's UI and commands to manage those lists. There is no second KoS list, guild list, or list editor; the Saboton dashboard controls synchronization and can remove tracked imports. Imports are additive: existing entries/reasons are preserved, and other players cannot delete your entries. **Names are shared by default. Share KoS reasons is off by default; enabling it also publishes player preset reasons and custom Other text to guild peers. Guild reasons and unrelated metadata are not shared.** Removing an imported entry in Spy suppresses its return on subsequent syncs; `allowsync` or manually re-adding it permits sharing again.

Incoming player reasons only fill an absent or empty reason table, including when both clients already have the target. **Any non-empty reason on the receiver wins in its entirety**: no merging, replacement, or remote clearing, even if it differs from the sender or was imported earlier. The only exception is our own unchanged names-only placeholder, which can be filled when a sender later shares the actual reason. The decision is made when applying the record, so local edits during a transfer (including edits to a placeholder) are protected. Receiving reasons is enabled with guild sync independently of outbound reason sharing. Turning sharing on or off cancels pending local work; start a fresh sync afterward.

Newly received reasons display as **Guild: description** in Spy's reason column, alerts, and enabled reason tooltips. Preset labels (retained in the sender's language) and custom text are rendered together under the receiver's localized Other field; they are not selected as local preset checkboxes. Names-only imports show **Guild: imported KoS (no shared reason)** when there is no existing local reason. Original wire reasons are saved separately so forwarding does not accumulate prefixes, publish placeholders, or change content fingerprints. A local edit is shared as the user's new reason instead. Existing reasons from older builds are not relabeled because their authorship cannot safely be inferred.

Sync allows at most 64 reasons per player, 512 bytes per preset label, 2,048 bytes of custom text, and 4,096 bytes for the complete encoded reason field (hex encoding and headers count toward this total). Unsupported/oversized reasons fail visibly rather than being truncated. Leaving sharing off still permits names-only sync of those entries.

**Remove imported KoS** on the dashboard defaults to removing only player memberships recorded as imported by this module, including tracked imports from older betas without a Guild label. It cancels local sync work and suppresses removed names so another sync does not immediately restore them. In this default mode, local entries (even with a `Guild:` note), names already local before a sync, later explicit re-adds through Spy, private reasons, other player metadata, and watched guilds remain intact. Removal is unavailable during combat/chat restrictions and works with guild sync disabled. Use **Allow again** for one name or **Allow all** to permit every suppressed player and guild name on a future sync; neither action imports names immediately. With Spy's **Share KoS Between Characters** enabled, Spy's normal cross-character removal tombstones also apply. Untracked historical entries are never guessed from note text.

For older **untracked** imports, optionally check **Include suspected old imports (N candidates)** before pressing Remove. Candidates have no zone, level, or class (all three fields absent or empty, including missing player data). **This is a heuristic, not proof: Spy can also create local name-only KoS entries, so review Spy's list before opting in.** Known explicit local additions/re-additions observed by this addon are excluded and remembered across reloads. Any non-empty zone, level, or class excludes an untracked entry. Reasons do not affect candidacy and existing notes are preserved. The checkbox defaults off, is not saved, and resets after cleanup or reopening the panel; slash-command cleanup remains tracked-only. Metadata is checked again at removal time, and removed candidates receive the same future-sync suppression as confirmed imports.

Player imports populate both Spy's KoS membership and the player metadata/KoS marker used by its menu, including its central character-sharing store when enabled. Beta.5 also repairs incomplete metadata left by earlier imports after settings restoration, or once local restrictions clear. This repair preserves existing metadata and KoS timestamps and does not restore names you removed. No fresh transfer is required for names already present and tracked as imports.

All participants need the v4 implementation in beta.6 or later; old v2/v3 clients cannot participate, even for names-only sync. Exchanges use the guild addon channel, validate the guild roster and Spy list scope, and preserve Forever's `First-Surname` identities and ruleset-wide storage. No automatic login/change sync is implemented, and completion does not mean every guild member has converged. These are guild-channel messages, not encrypted private transfers.

Cyrillic analysis reports Ukrainian-compatible (Є, І, Ї, Ґ) and Russian-compatible (Ё, Ы, Э, Ъ) spelling indicators. These letters also occur in other languages: for example, І appears in Belarusian. Mixed indicators, shared Cyrillic letters and non-Cyrillic names are inconclusive. The results are not probabilities, evidence of nationality, or instructions to attack. To check a target, put `/saboton spyenhancement checkcyrillic` in a macro. It reports the first name, the surname when Forever's regional-name mode is enabled, and the currently available guild name separately; guild clues describe the guild, not necessarily the player. Restricted or unavailable data is reported rather than guessed. The command does not attack or alter Spy lists.

#### Sync quick start and recovery

1. Install Spy and Saboton Essentials beta.6 or later (v4 protocol) on both clients. Both characters must be in the same guild and use the same Spy ruleset/list scope.
2. Open `/saboton spyenhancement options` on each client and leave **Enable guild sync** checked. This enables replies and imports as well as manual starts.
3. Press **Sync Now on one client**. Either client can initiate, regardless of which has more entries; the exchange is bidirectional. Discovery normally takes at least 12 seconds after its first message is submitted, followed by paced transfers.
4. Wait for a confirmed exchange. For example, 9 targets on one client and 1 already shared target on the other should leave both with 9, unless a missing name is locally suppressed.

To send player KoS reasons, check **Share KoS reasons** on the sending client before starting. The receiver can leave that sharing option off; its existing non-empty reasons still take priority. Reason-only updates do not increase the imported-name count. Different preserved reasons can produce another record exchange on later syncs; confirmation means the receiver accepted its local-wins policy, not that conflicting reasons became identical.

If a reason is missing, verify sharing is enabled on the sender and start a fresh sync; names-only sync does not include descriptions. Inspect Spy's KoS statistics **Reason** column. For mouseover reasons, also enable Spy's **Display KoS Reason** option. A pre-existing receiver reason deliberately blocks incoming descriptions.

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

When Blizzard's Settings API is available, every module uses the same native controls under Game Menu > Options > AddOns > Saboton Essentials. Longer pages have short sections for related settings, and module categories have a stable alphabetical order. Dependent controls remain visible but gray out when their feature is off (for example text positioning without combo text, or threat colors without threat labels); their saved values are preserved. Without that API, `/saboton options` and the minimap button open a smaller panel with the four Extra Attack text position and timing sliders and a Spy Enhancement dashboard launcher; remaining settings use slash commands.

Spy Enhancement's Settings subcategory uses native sync, reason-sharing, and notification checkboxes with explanatory tooltips, just like the other modules. **Manage guild sync...** opens a separate live management window; routine **Sync Now** / **Cancel** actions are separated from **Import cleanup**. The window shows live state/list/import counts/requested-name progress, last confirmed exchange, **Remove imported KoS**, and a paged suppressed-name list with **Allow again** and **Allow all**. `/saboton spyenhancement options` or `/saboton options spyenhancement` opens Spy's Settings page. Without Settings support, those commands open the management window with preferences included; the shared fallback options also have a launcher. Allowing names does not immediately import them; run another sync. Progress is per active exchange, not a promise of guild-wide convergence.

### Minimap Button (`minimap`)

A draggable minimap button (Thunder Clap icon) that opens Options on left-click. Right-click for **Unlock bar movement** or **Lock bar movement** and to add the current target to the mob timer. Unlocking affects both the Gathering and Mob timer frames, showing placeholders when they have no visible timers; drag each with the left mouse button outside combat. If their lock states differ, the menu offers to unlock both. Locking hides idle placeholders without stopping timers. The button can be dragged around the minimap and hidden via a checkbox in Options or `/saboton minimap`. If the client menu API is unavailable, the individual `/saboton gather lock` / `unlock` and `/saboton mobtimer lock` / `unlock` commands remain available.

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
- `/saboton mobtimer options` - open the manual mob-timer editor
- `/saboton mobprobe start` / `watch` / `status` / `stop` - run the experimental mob-death diagnostic described above
- `/saboton squeak status` - print the current trigger and sound configuration
- `/saboton squeak test` - play the configured sound
- `/saboton squeak debug` - toggle debug messages
- `/saboton squeak mages` - toggle the friendly-class-in-party/raid trigger (on by default)
- `/saboton squeak hostile` - toggle playing the sound on any hostile unit's death (off by default, for testing)
- `/saboton squeak friendly` - toggle playing the sound on any friendly unit's death (off by default, for testing)
- `/saboton squeak class <token>` - set which class triggers the friendly-death sound (e.g. `MAGE`, `WARRIOR`); also available as a dropdown in Options
- `/saboton squeak sound <none|squeak|kaching>` - set which sound plays; also available as a dropdown in Options
- `/saboton extraattack status` - print the current enabled state, sound, text, combo window, and combo count
- `/saboton extraattack test` - simulate one extra attack (updates the combo and contributes to the current sound burst)
- `/saboton extraattack enable` - toggle the entire module on/off (on by default); also available as a checkbox in Options
- `/saboton extraattack debug` - toggle swing and burst diagnostics
- `/saboton extraattack window <seconds>` - adjust the combo streak's reset window (default 1 second)
- `/saboton extraattack text` - toggle the on-screen combo text (on by default); also available as a checkbox in Options
- `/saboton extraattack textformat <format>` - customize the combo text, `%d` is replaced with the combo count; also editable as a text box in Options
- `/saboton extraattack xoffset <number>` / `yoffset <number>` - shift the entire combo-text arc horizontally or vertically in UI units; positive values move right or up. Also available as sliders in Options
- `/saboton extraattack sound` - toggle the sound (on by default); also available as a checkbox in Options
- `/saboton extraattack soundkey <none|kaching|squeak|huagh>` - set which sound plays; also available as a dropdown in Options
- `/saboton extraattack minhits <1-10>` - minimum extra attacks in a burst for sound and text (default 1); also available as a slider in Options
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
- `/saboton gather minsound <key>` / `maxsound <key>` - set the expiry sounds (`none`, `ding`, `thud`, `kaching`, `squeak`, `huagh`)
- `/saboton gather celebrate <exact name|id>` - toggle an item's celebration
- `/saboton gather celebrationsound <exact name|id> <key>` - choose its celebration sound from the same sound keys
- `/saboton gather testcelebration <exact name|id>` - preview its sparkles and sound
- `/saboton gather toggle <name|id>` - toggle tracking for one gatherable (e.g. `toggle thorium`)
- `/saboton gather add <id|name> <ore|herb> <min> <max>` - add a custom gatherable
- `/saboton gather list` - list all gatherables and their state
- `/saboton tanktarget status` - print the enabled state, options, manual pick, and the currently detected tank with the detection reason
- `/saboton tanktarget enable` - toggle the module on/off (on by default); also available as a checkbox in Options
- `/saboton tanktarget pet` - toggle treating your pet as the tank while solo (on by default); also available as a checkbox in Options
- `/saboton tanktarget size <12-32>` - set the shield icon size; also available as a slider in Options
- `/saboton tanktarget tank <name|clear>` - manually pick the tank for this session, or clear the pick to resume automatic detection
- `/saboton tanktarget debug` - toggle update-error diagnostics
- `/saboton tanktarget guess` - toggle unassigned-group-tank guessing (saved, on by default)
- `/saboton tanktarget testshields` - toggle session-only unconditional shields on all enumerated nameplates for rendering tests
- `/saboton tanktarget threat` - toggle all threat labels (on by default); shield initials remain visible
- `/saboton tanktarget allthreat` - toggle per-mob threat on all nameplates (saved, off by default); requires threat labels enabled
- `/saboton tanktarget hostile` - toggle hostile-only filtering for the shield, initials, and threat text (on by default)
- `/saboton tanktarget threatmode <scaled|raw>` - choose the non-tanking percentage; tank lead always uses raw threat
- `/saboton tanktarget thresholds <lower> <upper>` - set DPS color boundaries (ordered integers 1-100; default 50 80)
- `/saboton tanktarget tankthresholds <lower> <upper>` - set tank-lead color boundaries (ordered integers 1-500; default 120 150)
- `/saboton spyenhancement sync` - manually reconcile Spy's KoS players and watched guilds with available guild peers; queues while restricted
- `/saboton spyenhancement options` - open the sync dashboard, including fallback UI when needed
- `/saboton spyenhancement removeimports` - remove tracked imported KoS players, preserving local memberships and suppressing removed names
- `/saboton spyenhancement cancel` - cancel queued/in-progress local sync work (already imported entries remain)
- `/saboton spyenhancement allowsync [player|guild] <name>` - allow a removed imported name to return on the next sync
- `/saboton spyenhancement status` - show Spy list counts, sync status, and Cyrillic cache counts
- `/saboton spyenhancement debug` - toggle session-only sync chat diagnostics (200-line limit per enable); shows identity/roster, send results, incoming frames, rejection reasons, and concurrent-start decisions. Enable on both clients before reproducing, then share the output. Status also includes send-call and received-frame counts. Diagnostics include character identities and guild scope, but not KoS target names or reason text.
- `/saboton spyenhancement detect [player|guild] <name>` - analyze one player or guild name
- `/saboton spyenhancement checkcyrillic` - show spelling clues from the current player target's name, available surname, and guild; suitable for a macro
- `/saboton spyenhancement detectkos` / `detectguilds` - scan Spy's KoS players and watched guilds for Cyrillic names
- `/saboton spyenhancement cyrillicstats` / `clearcyrillicache` - show or clear spelling-analysis cache (old-format results are discarded)
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
- The legacy `PLAYER_SWING(swingDuration, swingType)` detector catches extra attacks such as Hand of Justice and Ironfoe: an extra attack lands as a main-hand swing far earlier than the current swing duration allows. A threshold under 50% of the expected interval excludes parry-haste false positives; swing duration is learned from the event itself so haste/Flurry are tracked without touching `UnitAttackSpeed` (secret in combat). Windfury Totem (each rank procs its own spell: 8516/10608/10610 for Ranks 1-3) and Windfury Weapon (rank spells 8232/8235/10486/16362 plus proc spell 439440) are detected separately from their `SPELL_UPDATE_COOLDOWN` events; Weapon counts as two hits. With the experimental option, off by default, Seal of Command proc spell 20424 cooldown updates count as one hit each; activation spell IDs are not counted.
- Gathering Timer reads loot slots on `LOOT_READY`/`LOOT_OPENED`. When a readable source GUID is available, non-`GameObject` sources are rejected; otherwise the item match is used. Reopening a node restarts the timer, so the final pick wins.
- Gathering Timer uses `C_Timer` and StatusBar frames; dragging is gated on `InCombatLockdown()`.
- Tank Target wraps every unit API in `pcall` and treats secret values as unreadable: it prefers nameplate-frame identity comparisons (no values read), falls back to GUIDs, and passes secret `UnitIsUnit` booleans to `SetAlphaFromBoolean` so visibility is decided by the game. Mark frames are version-tagged, parented to the plate (not `plate.UnitFrame`), and anchored to a probed visible health bar (known addon fields, then a depth-limited child scan for the widest visible StatusBar). Updates run on target/roster/nameplate events plus a 0.25 s ticker, since tanks swap targets faster than events alone capture. The shield uses the `groupfinder-icon-role-large-tank` atlas with role-icon fallbacks. The design follows ScryWoW's tank-target feature (see credit in the module).
- `src\Options.lua` builds the shared settings panel using Blizzard's `Settings` API (`Settings.RegisterVerticalLayoutCategory`/`Settings.RegisterProxySetting`/`Settings.CreateCheckbox`/`Settings.CreateSlider`/`Settings.CreateDropdown`); it reads a `GetOptionsSchema()` method from any module that implements one and never touches module internals directly, keeping UI code separate from feature logic
- The vertical-list Settings API has no built-in free-text control, so a schema option of `type = "text"` is rendered via a small custom row template (`SabotonTextInputControlTemplate` in `src\Options.xml`), styled and positioned like the built-in checkbox/slider/dropdown rows, backed by `SabotonTextInputControlMixin` in `src\Options.lua`
- Where Blizzard's `Settings` API is unavailable, the Options command opens a small window for the combo-text position and timing sliders, plus a Spy dashboard launcher. The Spy dashboard also opens directly via its options command; use slash commands for remaining settings.
- The minimap button repositions itself by tracking cursor angle around the `Minimap` frame during drag (the common community pattern also used by libraries like LibDBIcon); left-click opens Options without touching the `Settings` API itself, and right-click opens the timer controls.

## Tests

Run the Lua files in `tests/` from the addon root with a Lua interpreter. They use mocked WoW APIs and do not replace in-game testing. For example, with Node.js available, run `npx --yes --package fengari-node-cli fengari tests/test_gathering_timer.lua`.

The guild-sync tests simulate multiple clients, restrictions, lost data/ACKs, throttling, concurrent initiators, invalid records, and transfer limits. Run `tests/test_guild_sync.lua` for the transport, `tests/test_guild_sync_recovery.lua` for twenty-client bursts, disconnects/reconnects and exact idle-timeout boundaries, `tests/test_spy_enhancement.lua` for the Spy adapter, and `tests/test_spy_options.lua` for modern/fallback dashboard controls, alongside the persistence/core tests. Basic two-client transfers were confirmed in-game on beta.3; twenty-client load, Forever sender/receiver combat, roster behavior, and visual layout still require in-game validation before release.

All fourteen Lua test suites passed with Fengari, including the mob timer and probe tests and the Tank Target suite's restricted threat formatting, secret-value matching, GUID/identity fallback, manual-pick, and enable/disable paths. The recovery tests verify bounded queue drainage and successful transfers under their simulated conditions, not guaranteed all-to-all convergence or real server throughput.

## Releases

Version `0.6.0` includes the Mob Spawn Timer, minimap timer controls, and gathering celebrations from the 0.5.2 betas. Detection remains subject to the client limitations described above.

Version `0.5.2-beta.3` adds minimap timer controls, current-target mob tracking, and an opaque mob editor background.

Version `0.5.2-beta.2` adds the experimental Mob Spawn Timer, including automatic death detection and manual previews; in-game validation is still required.

Version `0.5.2-beta.1` adds the experimental mob death probe for in-game testing. It retains the gathering changes from `0.5.2-beta`.

Version `0.5.2-beta` adds per-item gathering celebrations and updates the built-in respawn timer list. The visual effect and self-loot confirmation still need in-game testing on Forever.

Version `0.5.1` includes the `0.5.0-beta` changes below and fixes a Tank Target chat error on Forever: restricted threat percentages are displayed in neutral white without using a color curve.

To create a ZIP locally on Windows for manual CurseForge upload, run from the addon root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\package-release.ps1
```

The script reads the TOC version and writes `releases\SabotonEssentials-<version>.zip`. The `releases` directory is ignored by Git. It packages the current working files, including uncommitted changes, and refuses to overwrite an existing ZIP; move or remove that ZIP to rebuild the same version. Run the tests and check the addon in-game before uploading.

The `0.5.0-beta` package refreshes the settings UI with consistent native controls, grouped sections, and dependent controls that gray out without changing saved preferences. Spy's live sync management opens separately from its preferences, with import cleanup separated from routine sync. Tank Target adds an optional grouped-tank guessing toggle and limits threat labels to living, attackable units. It includes the session-only `/saboton tanktarget testshields` rendering diagnostic and saved, off-by-default all-nameplate threat option (`/saboton tanktarget allthreat`), querying each mob independently. Non-current tank-target shields inside instances remain under investigation; forced TEST shields bypass matching and filtering for diagnosis. Restricted multi-tank matches retain separate native-visibility shield-and-initial rows, which may leave gaps; readable matches retain comma-separated dotted initials. It retains previous Extra Attack, Spy, threat-display, and self-tank shield improvements, plus the v4 sync protocol; earlier v2/v3 clients must update. Existing archives are not updated when source or documentation changes. The UI refresh, restricted combat rendering, and large-group sync still require in-game testing.

Releases use the [BigWigs WoW Packager](https://github.com/BigWigsMods/packager). It builds a ZIP containing the `SabotonEssentials` addon directory, detects Forever from interface `16001`, and generates release notes from Git history. Tests and original media sources are excluded from the ZIP.

1. Update `## Version` in `SabotonEssentials.toc` and commit the change. The first release is `0.1.0`.
2. Create and push an annotated tag matching the version, for example `git tag -a v0.1.0 -m "Release 0.1.0"` followed by `git push origin v0.1.0`.
3. GitHub Actions runs the Lua tests, verifies the archive, and publishes it as a GitHub release and workflow artifact. Tags such as `v0.2.0-beta.1` or `v0.2.0-alpha.1` are marked as prereleases; the TOC version must match without the leading `v`.

For automatic CurseForge uploads, create the WoW addon project on CurseForge, add its numeric project ID as the GitHub Actions repository variable `CURSEFORGE_PROJECT_ID`, and add an [author API token](https://authors.curseforge.com/#/settings/api-tokens) as the repository secret `CF_API_TOKEN`. Both are required if either is configured. Without them the workflow still publishes the ZIP on GitHub, where it can be downloaded and uploaded manually. CurseForge processes and may review uploaded files before publication; check that it lists the intended Forever game version. Re-running a successful CurseForge upload can create a duplicate file.

The [CurseForge upload API](https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api) is separate from the public CurseForge mod-distribution API. The packager assigns the release type from the tag and looks up the game version using the TOC interface number. Update the interface only after testing against the target client.

For project submission, CurseForge requests an English description, an appropriate license and categories, and an original square PNG logo of at least 400x400 pixels. Verify that all bundled media can be redistributed. CurseForge's WoW processor expects a ZIP with folders at its root and a case-matching `SabotonEssentials/SabotonEssentials.toc`. New projects need an approved release or beta file to sync to the CurseForge app. See the [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips), [file types](https://support.curseforge.com/support/solutions/articles/9000197242-file-project-types-and-additional-fields), and [WoW file processor rules](https://support.curseforge.com/support/solutions/articles/9000210425-curseforge-file-processor-errors-per-game).
