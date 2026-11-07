# Saboton Essentials

A World of Warcraft Forever / Classic+ addon for small, reactive audio and animation moments. Built as a collection of independent modules under a shared `/saboton` command, so new features can be added without touching existing ones.

## AI disclaimer

Generative AI was heavily utilized in creation of this mod and the modules below.

## Modules

### Squeaky Toy (`squeak`)

When a player of a configurable class (Mage by default) in your party or raid dies, play a configurable sound (Squeaky Toy by default, or the "Ka-ching!" sound). Also has optional testing triggers for any hostile or any friendly unit's death.

### Extra Attack (`extraattack`)

When the player gets an extra attack (Windfury, Hand of Justice, Ironfoe, Sword Specialization, etc.), play a sound and track a combo streak on-screen. The combo text arcs rightward on each hit, then fades after the movement and streak window finish. Its position, movement time, and fade time are adjustable in Options. Detection uses the engine's `PLAYER_SWING` event: an extra attack arrives as a main-hand swing that lands far earlier than the current swing duration allows (extra attacks reset the swing timer), so it's exact rather than a guess. A single proc plays one sound; multiple hits from one swing play a staggered, rising cascade (ka-ka-ching) after a short settle window. The whole module can be disabled with one master switch; the sound, combo text, combo window, and burst stagger are all customizable.

### Gathering Timer (`gather`)

Starts two countdown bars (min and max respawn) when you loot a tracked ore or herb node. Direct node-spawn detection is not possible on the Forever client (no game-object enumeration, no spawn event, no minimap-blip read), so it's timer-based: the loot of a tracked gatherable is the trigger. The min bar ("node may be up") and max bar ("gone / taken") are independent — each can be toggled off, has its own duration, and plays its own sound (bell chime and impact thud by default). The bar frame is movable (drag while unlocked, out of combat only), resizable, and can fill horizontally or vertically. Each gatherable (Thorium, Arcane Crystal, Black Lotus, etc.) can be toggled on or off individually.

### Options (`options`)

A shared settings panel (via Blizzard's Settings API) that lists every module's basic toggles and sliders in one place, under Game Menu > Options > AddOns > Saboton Essentials. Modules don't build any UI themselves; they each expose a small declarative schema, and this module turns those schemas into the panel.

### Minimap Button (`minimap`)

A draggable minimap button (Thunder Clap icon) that opens the Options panel when clicked. Can be dragged around the minimap, and hidden via a checkbox in Options or `/saboton minimap`. Position and visibility are session-only (not saved between reloads/logins).

## Installation

Place this folder in:

```text
World of Warcraft\\_classic_\\Interface\\AddOns\\SabotonEssentials\\
```

Restart the game or run `/reload`.

## Configuration

Put the sound file at `Media\squeak.ogg`, then update the `SOUND_OPTIONS` table in `src\Modules\SqueakyToy.lua` if a file name changes. WoW's client may reject unsupported or missing custom media; the module reports a warning in chat when the sound cannot be played.
Put the "Ka-ching!" sound file at `Media\kaching.mp3`, then update the `SOUND_OPTIONS` table in `src\Modules\ExtraAttack.lua` if the file name changes.Gathering Timer uses `Media\clear-bell-chime.mp3` (node may be up) and `Media\impact-thud.mp3` (node gone / taken); update `SOUND_OPTIONS` in `src\Modules\GatheringTimer.lua` if the file names change.
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
- `/saboton squeak sound <squeak|kaching>` - set which sound plays; also available as a dropdown in Options
- `/saboton extraattack status` - print the current enabled state, sound, text, combo window, and combo count
- `/saboton extraattack test` - simulate an extra-attack proc (plays the sound and updates the combo)
- `/saboton extraattack enable` - toggle the entire module on/off (on by default); also available as a checkbox in Options
- `/saboton extraattack debug` - toggle debug messages, including the raw `UNIT_COMBAT`/`COMBAT_TEXT_UPDATE` events seen
- `/saboton extraattack window <seconds>` - adjust the combo streak's reset window (session-only, default 1 second)
- `/saboton extraattack text` - toggle the on-screen combo text (on by default); also available as a checkbox in Options
- `/saboton extraattack textformat <format>` - customize the combo text, `%d` is replaced with the combo count; also editable as a text box in Options
- `/saboton extraattack xoffset <number>` / `yoffset <number>` - shift the entire combo-text arc horizontally or vertically in UI units; positive values move right or up. Also available as sliders in Options
- `/saboton extraattack sound` - toggle the sound (on by default); also available as a checkbox in Options
- `/saboton extraattack soundkey <kaching|squeak>` - set which sound plays; also available as a dropdown in Options
- `/saboton extraattack stagger <seconds>` - time between the sounds of a multi-hit burst (default 0.09s); also available as a slider in Options
- `/saboton gather status` - print the current state, active timer, and which gatherables are tracked
- `/saboton gather test` - start short test bars (5s / 10s) without needing a node
- `/saboton gather clear` - stop and hide the current timers
- `/saboton gather enable` - toggle the module on/off
- `/saboton gather debug` - toggle debug messages
- `/saboton gather lock` / `unlock` - lock or unlock the bar frame for dragging (out of combat only)
- `/saboton gather width <px>` / `height <px>` - resize the bars
- `/saboton gather orient <h|v>` - horizontal or vertical fill
- `/saboton gather min <seconds>` / `max <seconds>` - set the respawn window
- `/saboton gather minsound <key>` / `maxsound <key>` - set the expiry sounds (`ding`, `thud`, `kaching`, `squeak`)
- `/saboton gather toggle <name|id>` - toggle tracking for one gatherable (e.g. `toggle thorium`)
- `/saboton gather add <id|name> <ore|herb> <min> <max>` - add a custom gatherable
- `/saboton gather list` - list all gatherables and their state
- `/saboton minimap` - toggle the minimap button's visibility; also available as a checkbox in Options
- `/saboton options` - open the shared settings panel

## Technical notes

- Lua 5.1-compatible WoW addon code
- `src\\Core.lua` bootstraps a shared addon namespace/module registry and the `/saboton` slash command dispatcher; it has no feature logic of its own
- Each feature lives in its own file under `src\Modules\` and self-registers via `addon.RegisterModule(name, module)`; a module implements `OnEnable()` (called once on `ADDON_LOADED`) and `HandleCommand(message)`
- A module can optionally implement `GetOptionsSchema()` to appear in the settings panel (see `src\Options.lua`); this is the only integration point between modules and the UI
- Squeaky Toy uses the `UNIT_DIED` frame event (as of Patch 12.0.0/Midnight, addons can no longer register `COMBAT_LOG_EVENT_UNFILTERED`)
- Uses `UnitGUID` to confirm the dead unit is in the current group for the friendly-mage trigger
- The hostile/any-friendly testing triggers additionally scan target/focus/mouseover/nameplate/boss/arena unit tokens, since those deaths aren't limited to the group
- Uses `UnitClass` to confirm the player is a Mage
- Extra Attack cannot use combat log events (addons can no longer register `COMBAT_LOG_EVENT_UNFILTERED`). It originally tried the public `COMBAT_TEXT_UPDATE` event with a plain (non-secret) `"EXTRA_ATTACKS"` message type (Blizzard's own floating combat text system uses it), but this was confirmed in-game to never fire for real procs, so that listener is kept only as a harmless fallback
- Detection uses the engine's `PLAYER_SWING(swingDuration, swingType)` event, which fires for every auto attack with plain (non-secret) numbers on the Forever client. An extra attack lands as a main-hand swing that arrives far earlier than the current swing duration allows (extra attacks reset the swing timer), which normal cadence cannot produce. A proportional threshold (under 50% of the expected interval) excludes parry-haste false positives, which land at 60-100%. The swing duration is learned from the event itself so haste/Flurry are tracked without touching `UnitAttackSpeed` (secret in combat)
- Gathering Timer triggers on `LOOT_READY`/`LOOT_OPENED` and reads `GetLootSlotInfo`/`GetLootSlotLink`/`GetLootSourceInfo`, all of which return plain values on Forever (verified by forever-addon-kit). Only `GameObject` loot sources (nodes, not mob corpses) start timers, and the same node re-opened is deduped on its GUID
- Gathering Timer's bars run on `C_Timer` and StatusBar frames; the frame is movable via `SetMovable`/`RegisterForDrag`/`StartMoving` and drag is gated on `InCombatLockdown()` (movement out of combat only). Position and settings are session-only (the client never loads saved variables)
- `src\Options.lua` builds the shared settings panel using Blizzard's `Settings` API (`Settings.RegisterVerticalLayoutCategory`/`Settings.RegisterProxySetting`/`Settings.CreateCheckbox`/`Settings.CreateSlider`/`Settings.CreateDropdown`); it reads a `GetOptionsSchema()` method from any module that implements one and never touches module internals directly, keeping UI code separate from feature logic
- The vertical-list Settings API has no built-in free-text control, so a schema option of `type = "text"` is rendered via a small custom row template (`SabotonTextInputControlTemplate` in `src\Options.xml`), styled and positioned like the built-in checkbox/slider/dropdown rows, backed by `SabotonTextInputControlMixin` in `src\Options.lua`
- Where Blizzard's `Settings` API is unavailable, the Options command opens a small window for the combo-text position and timing sliders; use slash commands for other settings. These settings are session-only.
- The minimap button repositions itself by tracking cursor angle around the `Minimap` frame during drag (the common community pattern also used by libraries like LibDBIcon); it opens Options by calling `addon.modules.options:HandleCommand()` directly rather than touching the `Settings` API itself, keeping Settings-API code confined to `src\Options.lua`
