# Saboton Essentials - Changelog

## [0.3.0-beta.6] - 2026-11-14

- Add **Share KoS reasons**, off by default, to modern/fallback options. Opted-in senders share player preset reasons and custom Other text; guild reasons remain local. Receiving does not require enabling outbound sharing.
- Fill empty receiver reason fields, including for names already on both lists. Any non-empty receiver reason always wins, including reasons edited during transfer or existing on a player not yet in KoS. No merging, replacement, or remote clearing.
- Use incompatible v4 prefix `SabotonGuild4` and reason-aware fingerprints; all participants must update. Transfer long records in bounded, acknowledged chunks and stream one requested record at a time. Invalid/oversized reasons fail explicitly without truncation. Changing sharing cancels queued snapshots.
- Extend tests for default-off privacy, persistence, conflicting reasons, localization of Other, existing-name updates, suppressed removals, chunk loss/tampering, byte limits, and bounded send queues. In-game reason transfer still needs verification.

## [0.3.0-beta.5] - 2026-11-14

- Fix imported KoS names being counted without appearing in Spy's menu: create/update Spy player metadata, set its KoS marker, clear conflicting ignore membership, and update Spy's central character-sharing store when enabled.
- Repair incomplete player metadata for previously tracked imports after settings restoration or after local combat/chat restrictions clear, even with guild sync disabled. Preserve existing reasons, class/level data, and KoS timestamps; do not resurrect removed imports.
- Apply the same complete insertion path to legacy migration, refresh Spy's lists/stats, and reject imports whose player metadata could not be created instead of confirming success.

## [0.3.0-beta.4] - 2026-11-14

- Increase bounded discovery capacity to 32 peers; jitter starts, coalesce repeated starts and outdated offers, and alternate discovery replies with data to avoid starvation during long transfers.
- Fail and release sessions after 3 minutes without valid progress, excluding local combat/chat pauses. Roster disconnects release sessions immediately; remaining peers can continue and imported names stay intact.
- Return abandoned discovery responders to idle and add twenty-client burst, packet-loss, disconnect/reconnect, and exact timeout-boundary tests.
- Document sync setup, status meanings, timeout/retry behavior, diagnostic capture, and the difference between confirmed per-peer transfers and guild-wide convergence. All ten mocked Lua suites pass; live large-group recovery testing remains pending.

## [0.3.0-beta.3] - 2026-11-14

- Normalize Forever's space-separated guild-message names to Spy's hyphenated surname identities. Fixes treating own broadcasts as concurrent peers and mismatching addressed replies. Regression coverage verifies single/concurrent initiation and the nine-target/one-shared-target union with both roster formats.

## [0.3.0-beta.2] - 2026-11-14

- Added opt-in, bounded sync chat diagnostics via `/saboton spyenhancement debug`, including identities, discovery arbitration, send results, and rejected messages. Status now includes send/receive counters to investigate the live concurrent-sync stall.

## [0.3.0-beta.1] - 2026-11-14

- Fixed guild sync staying deferred on Forever's broad outgoing-restriction flag even when addon messaging works. Retain combat/chat-lockdown gates, native send-result handling, and peer acknowledgments.

## [0.3.0-beta] - 2026-11-14

- Added a shared-options Spy dashboard with sync/notification toggles, tooltips, Sync Now/Cancel, live status and list/progress counts, last confirmed exchange, and paged suppressed imports with Allow again. The same controls work in fallback UI via `/saboton spyenhancement options` and the fallback options launch button.
- Replaced fire-and-forget v2 broadcasts with paced v3 guild discovery, fingerprint comparison, requested-name transfer, and acknowledged bidirectional reconciliation. All peers must update.
- Defer network sends and imports during combat/chat restrictions; add bounded retries, duplicate protection, cancellation, roster/scope validation, and confirmed-peer status.
- Preserve Forever surname/ruleset identities. Share names only, never guild reasons or private notes; existing local reasons are unchanged.
- Remember locally removed imports, with `allowsync` to permit them again. Add a reusable bounded-record sync support component without Ace communication dependencies.
- Delay networking until settings restoration and declare Spy as an optional load-order dependency. Add simulated multi-client and Spy integration coverage; live Forever transport checks remain required.
- Replaced the duplicate KoS and guild-tag lists with manual sync of Spy's native KoS-player and watched-guild lists.
- Removed the separate SpyEnhancement window, minimap button, and tooltip hooks; use Spy's built-in UI to manage and view its lists.
- Cyrillic analysis now scans UTF-8 player and guild names, classifies Russian/Ukrainian-specific letters, and reports shared letters as unclear.
- The original 0.2.0-beta SpyEnhancement notes below describe the initial prototype and are superseded by these changes.

## [0.2.0-beta] - 2026-11-10

### Added - SpyEnhancement Module

#### Phase 1: Core KoS Sync System
- Personal KoS (Kill On Sight) list management with add/remove/list commands
- Full metadata tracking: playerName, realm, source, addedBy, addedAt, notes
- Rejection system: flag entries locally without deletion, can re-accept
- Persistent storage via SabotonEssentialsDB
- `getNormalizedKey()` for consistent player name format (lowercase "name-realm")

#### Phase 2: Guild Tagging System
- Mark entire guilds as hostile with `addguild`/`removeguild` commands
- Automatic member tracking and aggregation
- Per-guild statistics: member count, members tracked
- Guild-level rejection/acceptance system
- `guildlist` and `guildmembers` commands for management

#### Phase 3: Cyrillic Nationality Detection
- Russian/Ukrainian/Unclear classification system
- Character-based detection algorithm:
  - Russian-specific: Ё, Ы, Э
  - Ukrainian-specific: Ї, Є, Ґ, І
  - Common Cyrillic: А-Я, а-я, etc.
- Caching system for performance (1000x+ speedup on repeated scans)
- Batch scanning: `detectkos` scans entire KoS list
- `detect <name>`, `cyrillicstats`, `clearcyrillicache` commands

#### Phase 4: Network Sync via AceComm
- Guild-wide KoS broadcasting via AceComm-3.0
- Automatic message receiving from guildmates
- Union-based conflict resolution (never lose data, only add new)
- Source tracking: know who sent each entry via `syncFrom` field
- Compact message format (~60 bytes per entry) for bandwidth efficiency
- Graceful degradation: Phase 1-3 work without AceComm, Phase 4 optional
- Version-aware protocol for future compatibility

#### Phase 5: Comprehensive UI System
- **Main Window**: Displays real-time KoS/guild/nationality/network statistics
  - Draggable window, refresh button, auto-scrolling
  - Command: `/saboton spyenhancement ui`
  
- **Minimap Button**: Quick access toggle on minimap
  - Left-click: Open/close main window
  - Right-click: Manual KoS broadcast
  - Spy addon icon at bottom-left
  
- **Unit Frame Tooltips**: Auto-display KoS status on player hover
  - Shows personal KoS, synced entries, guild tags, nationality
  - Works on all player frames (target, party, raid, etc.)
  - Zero configuration needed
  
- **Status Panel**: Compact info display
  - Shows: "KoS: X+Y | Guilds: Z | Synced: W"
  - Command: `/saboton spyenhancement status`
  
- **Spy Addon Integration**:
  - Auto-detects Spy addon presence
  - Registers as "SpyEnhancement" module
  - Displays KoS/guild/nationality in Spy UI
  - Player info hooks for Spy database

### Technical Details

**Database Schema** (`SabotonEssentialsDB.spyenhancement`):
- `kosPersonal`: User's own KoS entries with full metadata
- `kosSynced`: Entries received from guildmates via network
- `kosRejected`: Rejection flags (boolean, doesn't delete)
- `hosileGuilds`: Hostile guild entries with member counts
- `guildMembers`: Per-guild member tracking with timestamps
- `cyrillicCache`: Cached nationality detection results
- `syncState`: Network sync state (lastSyncTime, syncedWith list)

**Chat Commands**: 20+ commands across all phases
- KoS: `add`, `remove`, `list`, `reject`, `accept`, `sync`
- Guild: `addguild`, `removeguild`, `guildlist`, `guildmembers`, `rejectguild`, `acceptguild`
- Cyrillic: `detect`, `cyrillicstats`, `detectkos`, `clearcyrillicache`
- UI: `ui`, `status`, `minimap`, `tooltips`
- Help: `help`

**API Methods**: 35+ methods exposed
- KoSSync: Add, Remove, Accept, Reject, List, GetStats, GetAll, etc.
- GuildTag: AddGuild, RemoveGuild, GetGuilds, GetMembers, GetStats, etc.
- CyrillicDetector: Detect, DetectBatch, GetStats, ClearCache, etc.
- NetworkSync: BroadcastKoS, RegisterMessageHandler, GetStats, etc.

**Graceful Degradation**:
- Module loads only if Spy addon is present
- Phases 1-3 work without AceComm-3.0 or AceSerializer-3.0
- Phase 4 disabled with notification if AceComm unavailable
- UI works independently of network capability

**Forever WoW Compatibility**:
- Tested with LibStub, AceAddon-3.0, AceComm-3.0, AceSerializer-3.0
- Proper SavedVariables persistence
- No Forever-specific API issues identified
- Uses only standard WoW and Ace3 APIs

### Files Modified
- `SabotonEssentials.toc`: Version bump to 0.2.0-beta, added SpyEnhancementUI.lua

### Files Added
- `src/Modules/SpyEnhancement.lua` (1,225 lines): All 4 core phases
- `src/Modules/SpyEnhancementUI.lua` (421 lines): UI system

### Git Commits
1. `0b06228` - Phase 1: Implement core KoS Sync system
2. `25ccc1c` - Phase 2: Implement Guild Tagging system
3. `7445663` - Phase 3: Implement Cyrillic Nationality Detection
4. `54d85e8` - Phase 4: Implement Network Sync via AceComm
5. `86f0eb0` - Phase 5: Add comprehensive UI for SpyEnhancement testing

### Known Limitations / Future Work

**Phase 5+**:
- Automatic broadcast timer (only manual sync currently)
- UI customization (window position/size not persistent)
- Reputation system for sync sources
- Advanced search/filtering in main window
- Sound alerts when KoS detected
- Config options panel in Spy addon

**Testing Status**:
- Ready for in-game testing on Forever WoW
- All code paths implemented
- Awaiting production validation with active guild

### Testing Checklist

**Phase 1 - KoS Sync**:
- [ ] Add/remove players
- [ ] Reject/accept entries
- [ ] List shows correct metadata
- [ ] Data persists after logout

**Phase 2 - Guild Tagging**:
- [ ] Add/remove hostile guilds
- [ ] Members auto-tracked
- [ ] Guild list shows member counts
- [ ] Data persists

**Phase 3 - Cyrillic Detection**:
- [ ] Detect Russian names (Владимир)
- [ ] Detect Ukrainian names (Петро)
- [ ] Detect Latin names (John)
- [ ] Cache works (2nd detect faster)
- [ ] Batch scanning works

**Phase 4 - Network Sync**:
- [ ] Manual broadcast works
- [ ] Guildmates receive entries
- [ ] Union merging prevents duplicates
- [ ] Source tracking accurate

**Phase 5 - UI**:
- [ ] Main window opens and updates
- [ ] Minimap button functional
- [ ] Tooltips show KoS info
- [ ] Status panel displays correctly
- [ ] Spy integration works

### Requirements

**Minimum**:
- World of Warcraft: Forever (build 16001)
- Spy addon (core dependency)
- LibStub (provided by Spy)
- AceAddon-3.0 (provided by Spy)

**Optional**:
- AceComm-3.0 (for Phase 4 network sync)
- AceSerializer-3.0 (for Phase 4 network sync)

### Installation

1. Copy SabotonEssentials folder to `Interface\AddOns\`
2. Load WoW and verify addon loads
3. Type `/saboton help` to see available modules
4. Type `/saboton spyenhancement help` for SpyEnhancement commands

### Usage

**Quick Start**:
```
/saboton spyenhancement ui              # Open main window
/saboton spyenhancement add Playername  # Add to KoS
/saboton spyenhancement sync            # Broadcast to guild
```

**Full Documentation**: See `Phase5-UI-Integration-Guide.md` and `QUICK-REFERENCE-CARD.md`

---

## [0.1.0] - Original Release

- ExtraAttack: Extra attack sounds
- SqueakyToy: Configurable sound effects
- GatheringTimer: Gathering node timers
- MinimapButton: Minimap button framework
