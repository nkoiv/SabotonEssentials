# Saboton Essentials

A World of Warcraft Forever / Classic+ addon for small, reactive audio and animation moments. Built as a collection of independent modules under a shared `/saboton` command, so new features can be added without touching existing ones.

## AI disclaimer

Generative AI was heavily utilized in creation of this mod and the modules below.

## Modules

### Squeaky Toy (`squeak`)

When a player of a configurable class (Mage by default) in your party or raid dies, play a configurable sound (Squeaky Toy by default, or the "Ka-ching!" sound). Optional hostile and friendly death triggers are for testing and require a readable GUID and a matching visible unit token; secret values cannot be matched.

### Extra Attack (`extraattack`)

When the player gets an extra attack (Windfury, Hand of Justice, Ironfoe, Sword Specialization, etc.), play a sound and track a combo streak on-screen. The combo text arcs rightward on each hit, then fades after the movement and streak window finish. Its position, movement time, and fade time are adjustable in Options. Detection uses early main-hand `PLAYER_SWING` events as a heuristic for extra attacks; it cannot identify the triggering spell and unusual swing timing may affect detection. Multiple hits play a staggered, rising sound cascade after a short settle window.

### Gathering Timer (`gather`)

Starts two countdown bars (min and max respawn) when you loot a tracked ore or herb node. Direct node-spawn detection is not possible on the Forever client (no game-object enumeration, no spawn event, no minimap-blip read), so it's timer-based: the loot of a tracked gatherable is the trigger. The min bar ("node may be up") and max bar ("gone / taken") are independent — each can be toggled off, has its own duration, and plays its own sound (bell chime and impact thud by default). The bar frame is movable (drag while unlocked, out of combat only), resizable, and can fill horizontally or vertically. Each gatherable (Thorium, Arcane Crystal, Black Lotus, etc.) can be toggled on or off individually.

### Options (`options`)

When Blizzard's Settings API is available, a shared panel lists module options under Game Menu > Options > AddOns > Saboton Essentials. Without that API, `/saboton options` and the minimap button open a smaller panel with the four Extra Attack text position and timing sliders; other settings use slash commands.

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
- `/saboton minimap` - toggle the minimap button's visibility; also available as a checkbox in Options
- `/saboton options` - open the shared settings panel

## Technical notes

- Lua 5.1-compatible WoW addon code
- `src\Core.lua` bootstraps the shared namespace, module registry, slash command dispatcher, and settings persistence.
- Each feature lives in its own file under `src\Modules\` and self-registers via `addon.RegisterModule(name, module)`; a module implements `OnEnable()` (called once on `ADDON_LOADED`) and `HandleCommand(message)`
- A module can optionally implement `GetOptionsSchema()` to appear in the settings panel (see `src\Options.lua`); this is the only integration point between modules and the UI
- Squeaky Toy uses the `UNIT_DIED` frame event (as of Patch 12.0.0/Midnight, addons can no longer register `COMBAT_LOG_EVENT_UNFILTERED`)
- Uses `UnitGUID` to confirm the dead unit is in the current group for the friendly-mage trigger
- The hostile/any-friendly testing triggers additionally scan target/focus/mouseover/nameplate/boss/arena unit tokens, since those deaths aren't limited to the group
- Uses `UnitClass` to check the matched group member's configured class.
- Extra Attack cannot use combat log events (addons can no longer register `COMBAT_LOG_EVENT_UNFILTERED`). Its previously tested `COMBAT_TEXT_UPDATE` fallback did not fire for real procs on the tested Forever client and has been removed.
- Detection uses the engine's `PLAYER_SWING(swingDuration, swingType)` event, which fires for every auto attack with plain (non-secret) numbers on the Forever client. An extra attack lands as a main-hand swing that arrives far earlier than the current swing duration allows (extra attacks reset the swing timer), which normal cadence cannot produce. A proportional threshold (under 50% of the expected interval) excludes parry-haste false positives, which land at 60-100%. The swing duration is learned from the event itself so haste/Flurry are tracked without touching `UnitAttackSpeed` (secret in combat)
- Gathering Timer reads loot slots on `LOOT_READY`/`LOOT_OPENED`. When a readable source GUID is available, non-`GameObject` sources are rejected; otherwise the item match is used. Reopening a node restarts the timer, so the final pick wins.
- Gathering Timer uses `C_Timer` and StatusBar frames; dragging is gated on `InCombatLockdown()`.
- `src\Options.lua` builds the shared settings panel using Blizzard's `Settings` API (`Settings.RegisterVerticalLayoutCategory`/`Settings.RegisterProxySetting`/`Settings.CreateCheckbox`/`Settings.CreateSlider`/`Settings.CreateDropdown`); it reads a `GetOptionsSchema()` method from any module that implements one and never touches module internals directly, keeping UI code separate from feature logic
- The vertical-list Settings API has no built-in free-text control, so a schema option of `type = "text"` is rendered via a small custom row template (`SabotonTextInputControlTemplate` in `src\Options.xml`), styled and positioned like the built-in checkbox/slider/dropdown rows, backed by `SabotonTextInputControlMixin` in `src\Options.lua`
- Where Blizzard's `Settings` API is unavailable, the Options command opens a small window for the combo-text position and timing sliders; use slash commands for other settings.
- The minimap button repositions itself by tracking cursor angle around the `Minimap` frame during drag (the common community pattern also used by libraries like LibDBIcon); it opens Options by calling `addon.modules.options:HandleCommand()` directly rather than touching the `Settings` API itself, keeping Settings-API code confined to `src\Options.lua`

## Tests

Run the Lua files in `tests/` from the addon root with a Lua interpreter. They use mocked WoW APIs and do not replace in-game testing. For example, with Node.js available, run `npx --yes --package fengari-node-cli fengari tests/test_gathering_timer.lua`.

## Releases

To create a ZIP locally on Windows for manual CurseForge upload, run from the addon root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\package-release.ps1
```

The script reads the TOC version and writes `releases\SabotonEssentials-<version>.zip`. The `releases` directory is ignored by Git. It packages the current working files, including uncommitted changes, and refuses to overwrite an existing ZIP; move or remove that ZIP to rebuild the same version. Run the tests and check the addon in-game before uploading.

Releases use the [BigWigs WoW Packager](https://github.com/BigWigsMods/packager). It builds a ZIP containing the `SabotonEssentials` addon directory, detects Forever from interface `16001`, and generates release notes from Git history. Tests and original media sources are excluded from the ZIP.

1. Update `## Version` in `SabotonEssentials.toc` and commit the change. The first release is `0.1.0`.
2. Create and push an annotated tag matching the version, for example `git tag -a v0.1.0 -m "Release 0.1.0"` followed by `git push origin v0.1.0`.
3. GitHub Actions runs the Lua tests, verifies the archive, and publishes it as a GitHub release and workflow artifact. Tags such as `v0.2.0-beta.1` or `v0.2.0-alpha.1` are marked as prereleases; the TOC version must match without the leading `v`.

For automatic CurseForge uploads, create the WoW addon project on CurseForge, add its numeric project ID as the GitHub Actions repository variable `CURSEFORGE_PROJECT_ID`, and add an [author API token](https://authors.curseforge.com/#/settings/api-tokens) as the repository secret `CF_API_TOKEN`. Both are required if either is configured. Without them the workflow still publishes the ZIP on GitHub, where it can be downloaded and uploaded manually. CurseForge processes and may review uploaded files before publication; check that it lists the intended Forever game version. Re-running a successful CurseForge upload can create a duplicate file.

The [CurseForge upload API](https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api) is separate from the public CurseForge mod-distribution API. The packager assigns the release type from the tag and looks up the game version using the TOC interface number. Update the interface only after testing against the target client.

For project submission, CurseForge requests an English description, an appropriate license and categories, and an original square PNG logo of at least 400x400 pixels. Verify that all bundled media can be redistributed. CurseForge's WoW processor expects a ZIP with folders at its root and a case-matching `SabotonEssentials/SabotonEssentials.toc`. New projects need an approved release or beta file to sync to the CurseForge app. See the [submission guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips), [file types](https://support.curseforge.com/support/solutions/articles/9000197242-file-project-types-and-additional-fields), and [WoW file processor rules](https://support.curseforge.com/support/solutions/articles/9000210425-curseforge-file-processor-errors-per-game).
