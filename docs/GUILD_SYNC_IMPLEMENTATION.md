# Guild sync implementation

## Current validation and release status

- `0.3.0-beta.3`: basic two-client transfer confirmed in-game after normalizing
  space-separated guild-message sender names to Spy's hyphenated identities.
- `0.3.0-beta.4`: burst/disconnect hardening packaged for testing, with all ten
  Lua suites passing with Fengari. Earlier beta ZIPs do not include this work.
- `0.3.0-beta.5`: complete Spy player-metadata insertion and repair of earlier
  tracked imports. Earlier transfer confirmations only verified KoS membership,
  not visibility in Spy's menu; the metadata fix still needs in-game validation.
- `0.3.0-beta.6`: opt-in player KoS reasons, local-wins reason collisions,
  content fingerprints, and bounded continuation chunks over incompatible v4.
  Update both clients; reason transfer still needs in-game validation.
- `0.3.1`: tracked-import cleanup, opt-in suspected legacy cleanup, Guild-labeled
  native reason display, and names-only placeholders. All ten Lua suites pass,
  including cleanup/reload and rendering tests; live verification remains pending.
  Existing beta.6 ZIPs do not include these changes. The v4 protocol is unchanged.
- `0.3.2-beta`: track each Windfury Totem and Windfury Weapon rank spell for
  extra-attack sounds, and add opt-in experimental Seal of Command proc detection.
- `0.3.2-beta.2`: add **Allow all** to clear player and guild import suppressions
  in one action. Allowed names remain absent until the next sync.
- Still unverified in-game: twenty-client load, restriction transitions,
  disconnect/reconnect recovery, and modern/fallback dashboard layout.
- The Windfury rank and Seal of Command spell IDs still require in-game proc
  verification; Seal detection is disabled by default.
- User-facing setup, status meanings, and diagnostic steps are in the
  [README sync guide](../README.md#sync-quick-start-and-recovery).

## Scope and design

Replace SpyEnhancement's v2 full-list broadcasts with manual, bidirectional,
additive reconciliation. Spy remains authoritative. No automatic login sync,
remote deletion or alternate-channel bypasses. Player KoS reasons (including
custom Other text) can be shared explicitly; guild reasons remain local.

The reusable part is `src/Support/GuildSync.lua`: a small bounded-record sync
engine, not a general networking framework. Its provider supplies scope,
identity normalization, record validation/keying, optional content keying, snapshots, apply, and
confirmation callbacks. `SpyEnhancement.lua` owns Spy-specific persistence,
imports, suppression, settings, and commands.

### Deliberate choices

- New prefix `SabotonGuild4`, leaving incompatible v2/v3 clients isolated.
  Updating both clients is required, including names-only users.
- GUILD-only discovery and addressed exchange. Roster validation and matching
  scope are mandatory. WHISPER optimization awaits live Forever verification.
- Names by default: player KoS and watched-guild names. Share KoS reasons is a
  saved setting, off by default, controlling outbound reasons only. Incoming
  reasons fill absent/empty reason tables; any non-empty receiver reason wins
  unchanged, including local edits during a transfer and previously imported
  reasons. Only an unchanged generated names-only placeholder may be filled
  later. No real reason merging, replacement, or deletion. Guild reasons and other
  metadata are excluded. Changing the option cancels frozen/queued snapshots.
- Plain bounded records, no deserializer or compression. Native APIs exist but
  their decompressor has no documented output-allocation limit. Compression is
  unnecessary for the initial protocol and would complicate resource guarantees.
- Direct native sends at most once per 1.25 seconds, with result-aware retries.
  Unlike passing a full transfer into AceComm/CTL, this permits checking gates at
  the actual send call and requires no incidental Ace load order. This limits
  this addon's traffic, not other addons or server-configured throttles; never
  increase global CTL settings. Existing CTL hooks can account for these sends.
- Freeze snapshots per session; changes during a transfer appear on the next
  manual sync. Fingerprints compare canonical identity plus encoded shared
  reason content, not timestamps. Bookkeeping/suppression remains name-based.
  Thus reason-only differences are requested even for already-known names.
  Preserved conflicts may cause another transfer next round without overwrites.
- Forever's `First-Surname` names and Spy's ruleset-wide `StoreRealm` are
  preserved. Guild-message `First Surname` identities are normalized to the same
  hyphenated form for self-filtering, roster checks, arbitration and routing.
  Do not append internal realm names to regional identities.

## Protocol

Every physical frame is <=255 bytes; prefix <=16 bytes. Tab-separated envelope:
`operation, round/session ID, recipient (empty for discovery), sequence, payload`.
Names cannot contain control characters. Record wire format is `P<TAB>name`
with optional `<TAB>encodedReason`, or `G<TAB>name` (no reason).
The reason field contains sorted, length-prefixed hex strings: `B<length>:<hex>`
for preset text and `O<length>:<hex>` for custom Other text. Lengths count hex
bytes. At most 64 entries, 512 bytes/preset label, 2,048 bytes/custom text and
4,096 bytes/complete encoded field. Aggregate encoding overhead can reduce the
usable custom-text length. No NUL, arbitrary tables, or executable deserialization.
Malformed/oversized reasons fail visibly rather than truncating.
Preset labels remain in the sender's language. For native display, combine labels
and custom text into a sorted `Guild: description` under the receiver's localized
Other key, escaping pipes for literal display. Names-only imports with no local
reason receive `Guild: imported KoS (no shared reason)`. Keep the original encoded
reason and an independent copy of the generated display in character-scoped
bookkeeping. Forward the original only while the displayed table still matches;
otherwise encode the local edit normally. Placeholders never become wire reasons.
This keeps content hashes and byte limits independent of presentation and avoids
prefix growth across relays. Real existing reasons, including older unmarked
imports, are not rewritten. Rendering tests mirror SpyStats/tooltip iteration;
live UI verification is still required. Spy's DisplayKOSReason option gates tooltips.
Fingerprints are deterministic paired modular hashes, used for comparison only,
not authentication or encryption.

1. Manual start queues H (scope + snapshot digest) and collects bounded O offers.
   Discovery and offers use random delay to spread guild-wide traffic.
   Concurrent initiators use deterministic identity ordering to avoid opening
   competing sessions.
2. Select peers serially, suppressing duplicate content digests after a confirmed
   exchange. A failed peer does not suppress alternate sources.
3. B opens a session with an offered peer. Both directions use independent
   stop-and-wait sequences. ACKs are unsequenced and prioritized.
4. S exchanges snapshot digests. Identical sets send no manifests or records.
5. N requests a manifest; M pages contain record fingerprints; E terminates it
   with the advertised digest. Validate the entire manifest before requesting.
6. Q requests missing content fingerprints; R terminates requests. After R,
   stream requested records one at a time: zero or more C continuation pages,
   followed by a final D page. Each page uses the existing sequence/ACK/retry
   rules. Only a fully assembled record (maximum 8,192 bytes), matching a wanted
   manifest fingerprint, reaches the provider. T terminates data and rejects
   incomplete assembly. Do not expand an entire large snapshot into send chunks.
7. F acknowledges successful application (or already-present/suppressed records)
   of the peer snapshot. Complete only after peer F and acknowledgment of own F.
   Never interpret API submission as peer receipt. Streaming sessions must
   also drain all requested records and their T page before completing.
8. Retain bounded completed-session ACK state for the session lifetime so final
   ACK loss followed by combat does not immediately discard receipt evidence.

Limits are constants beside the implementation: 1,000 records, 128-byte names,
96-byte routing identities, two concurrent sessions, 32 offers/completed
sessions, 2,048 queued frames per session, 524,288 total queued payload bytes,
64 deferred incoming frames, and a two-hour absolute session/round lifetime.
Pages have at most four accepted-send attempts with exponential ACK waits;
native throttling/lockdown rejection uses a separate bounded backoff.
Repeated start coalesces. Cancel/disable/guild
changes invalidate active work. A busy peer may be retried on the next sync.

### Burst and disconnect recovery

- Repeated starts coalesce with both initiated rounds and inbound exchanges.
  At most 33 discovery/control messages are queued; a newer unsent offer for
  the same peer replaces its predecessor. Ready controls alternate with data
  pages, after ACKs, so long transfers do not starve discovery.
- A session with no new valid page or matching ACK for 180 unrestricted local
  seconds fails visibly and releases its queues. Duplicate/replayed traffic
  does not extend this deadline. Local combat/chat pauses stop this clock;
  a remote peer staying restricted can still time out and be retried manually.
- An explicit roster offline/left indication releases a peer's session and
  queued offers immediately. Missing disconnect events fall back to the
  progress timeout. Other offered peers can still be reconciled.
- A responder that never receives a begin page returns to idle after 180
  unrestricted seconds, rather than displaying "responding" indefinitely.
  Its bounded offer authorization remains valid until the two-hour lifetime
  because another peer may be completing earlier exchanges in a long round.
- Already applied imports survive interruption; unconfirmed peers are never recorded
  as successful. A fresh manual sync after reconnection reconciles missing
  records or differing reason content. There is no automatic restart loop or all-to-all guild convergence
  guarantee: snapshots are frozen per exchange, discovery is best-effort, and
  busy/offline peers may require another manual round.

## Restriction lifecycle

- Require initialized provider, restored settings, guild and roster availability.
- Check chat lockdown, Chat restriction, and combat immediately before every
  native send and received-record apply. Do not preflight with
  `AreOutgoingAddonChatMessagesRestricted`: it stays true on the tested Forever
  realm even while CraftCritic successfully transfers data. Native send results
  govern submission failures; peer acknowledgments still govern completion.
- Honor `ADDON_RESTRICTION_STATE_CHANGED`'s Activating/Active state; the query
  predicate intentionally returns false during event dispatch.
- Resume from the timer after deactivation/combat exit/world transition, never
  directly within restriction-event dispatch.
- While restricted, retain at most bounded active work, do not consume retry
  timeouts, and do not process incoming data into Spy. A bounded incoming queue
  allows received final pages/ACKs to be processed after restrictions end.
- A hard wall-clock lifetime still expires abandoned sessions. Throttle results
  retry with capped exponential backoff; local lockdown waits for the gates to
  clear. Repeated server rejections without observable local restrictions stop
  with an error. Permanent errors fail visibly.

## Spy integration

- Add optional Spy dependency and load support before the feature module.
- Initialize networking after settings restoration; OnEnable only prepares
  integration/event handling.
- Player insertion mirrors Spy's ToggleKOSPlayer data updates without its
  chat/sound side effects: UpdatePlayerStatus, AddKOSData, RemoveIgnoreData,
  PlayerData.kos, optional central character-sharing regeneration, list/stat
  refresh. Validate the player metadata and membership before accepting a new
  import. Incoming reasons only fill empty receiver fields before central-store
  regeneration and refresh. Existing reasons and learned details stay unchanged.
- Repair missing/incomplete player metadata only for tracked imports still in
  KOSData. Run after restoration and restriction clearance, even when sync is
  disabled, and before snapshots when unrestricted. Do not reset KoS timestamps
  or re-add removed names; the normal suppression logic handles removals.
- Scan for removal of imported records before snapshots/apply/persistence.
  Store player bookkeeping per Spy character + ruleset and guild bookkeeping
  per ruleset. Suppressed imports remain absent until explicitly allowed or
  manually re-added through Spy. The dashboard supports allowing one name or
  clearing all player and guild suppressions at once; allowing names does not
  immediately import them, and requires a subsequent sync.
- Player import provenance records the KoS membership timestamp; upgrade older
  boolean records in place. A passive secure post-hook on Spy:ToggleKOSPlayer
  records explicit local adds/removals, including re-adds within the same second;
  internal imports do not call this UI method. A changed timestamp also releases
  membership from cleanup ownership when no UI hook observed the change. Reason provenance
  is separate: importing a reason onto an already-local player never makes that
  membership removable. Do not infer either provenance from a `Guild:` prefix.
- Remove imported KoS cancels local sessions and uses Spy:RemoveKOSData for
  tracked player memberships only, then regenerates central data and refreshes
  lists/stats. Suppress every successfully removed name and save. Preserve any
  reason not equal to our generated display, along with other player metadata;
  leave watched guilds unchanged. Use native cross-character removal tombstones
  when sharing is enabled. Reject cleanup during local combat/chat restrictions
  or missing APIs, and report a failed native removal explicitly. Cleanup works
  even with guild sync disabled. Untracked historical imports cannot safely be
  distinguished from local entries automatically; default cleanup leaves them alone.
- A dashboard-only, unsaved **Include suspected old imports** checkbox opts into
  heuristic cleanup once. Show a live candidate count and visible warning;
  reset on show and after cleanup. Candidate membership is untracked, not known
  explicitly local, and has no zone/level/class (each nil or empty string, or
  no PlayerData). Skip malformed data and restricted metadata rather than
  interpreting them as missing. Reasons do not prove provenance. Recompute
  candidates immediately before removal, never promote them to confirmed imports
  during scans, and apply normal native removal/preservation/suppression rules.
  Spy's local ToggleKOSPlayer also calls UpdatePlayerStatus with no class/level
  or zone, so false positives are possible and the warning is essential.
  Persist local-add timestamps observed by the secure UI post-hook and timestamp
  changes; exclude those memberships from heuristics across reloads. The slash
  command never includes heuristic candidates.
- Sync commands: options, sync, cancel, removeimports, status, debug,
  allowsync [player|guild] <name>.
- The options dashboard exposes those actions, live state/counts, and paged
  suppression recovery. `/saboton spyenhancement options` opens a Settings canvas
  or the same controls in a fallback window. Widget code stays in Options and
  communicates only through schema callbacks.
- Sync toggle cancels pending traffic; notification toggle gates routine
  completion notices, not errors.
- Reason sharing is available in both modern/fallback dashboards. Receiving
  reasons does not opt into publishing them. Debug logs omit record/reason
  payloads; a reason-only update does not increment the imported-name counter.
- Keep Cyrillic analysis and legacy list migration working independently.
- Use Spy's existing quiet guild-add API. It still controls its own list-add
  sounds and options refresh; this integration does not patch Spy or temporarily
  override its global sound settings. One record per paced page limits UI bursts.
- Persist bounded metadata, never serialized network queues. Save after imports
  and confirmations. Preserve existing legacy lastSyncTime as historical only.

## Work and validation

1. Implemented support engine and simulated multi-client network tests.
2. Integrated Spy adapter, persistence/suppression, lifecycle, TOC and commands.
3. Updated README/changelog and implemented the shared options dashboard. All
   ten Lua suites passed with Fengari, including modern/fallback UI and saved
   settings, a 1,000-record transfer, and maximum frame/routing/record byte-length
   cases.
4. Basic two-client transfers were confirmed in-game on beta.3 after fixing
   Forever's space-separated chat sender identities. Still pending in-game:
   - twenty concurrent starts and repeated clicks with normal addon traffic;
   - sender/receiver/both in combat;
   - Chat Activating and lingering restrictions after combat;
   - zoning/loading, offline peer, guild change and reload;
   - ruleset/surname identities and real roster names;
   - native send-result values and simultaneous normal addon traffic;
   - Settings/fallback dashboard layout, actions, and suppression recovery.

Automated acceptance:

- Every frame fits; identical lists send no D; one missing entry sends one D.
- Equal counts with different records reconcile in both directions.
- No send/apply while blocked, including activation-event predicate false.
- Missing ACKs retry idempotently; dropped data/final ACKs recover.
- No confirmation without peer application; retries/session/queue limits bound work.
- Reject invalid scope/roster/session/sequence/manifest/record/oversized frames.
- Local imported removals stay removed; reasons and other module behavior survive.
- Cleanup preserves local/shared-local/re-added names and watched guilds, handles
  older boolean provenance, survives reload with sync disabled, reports native
  failures, respects restrictions, and suppresses names through subsequent sync.
  Same-second explicit remove/re-adds preserve local ownership.
- Legacy candidates require all three fields absent/empty, exclude any known
  local membership or any populated field, update counts as metadata arrives,
  preserve private notes, and remain suppressed after opted-in removal.
  Both dashboards test opt-in/reset and candidate-only button enablement.
- The modern and fallback dashboards test per-name allowance, bulk allowance,
  empty-list button state, and refresh after suppressed names change.
- Newly imported reasons render in Spy's localized Other slot; one-hop forwarding
  retains original fingerprints without accumulating prefixes. In-place local
  edits override both stale tracked wire text and names-only placeholders.
  Exact-limit original reasons still forward when display decoration is larger
  than the custom wire-text bound; placeholders never become wire descriptions.
- Disabled saved settings prevent networking before restore.
- Queue-count/byte/session limits and a full blocked inbox are tested explicitly;
  ASCII and Cyrillic records at the name-byte limit fit the routing envelope.
- Twenty simultaneous initiators, repeated clicks, staggered starts with packet
  loss, and a disconnected participant drain all active queues. A clean burst
  reconciles all 20 distinct source sets into the surviving initiator.
- Exact 180-second idle thresholds, duplicate traffic, local restriction pauses,
  roster-driven disconnect cleanup, fallback timeout, abandoned responders, and
  reconnecting/manual retry are covered by the recovery suite.
- Reason-sharing tests cover default-off privacy and reload persistence,
  existing-name updates, new names with existing receiver reasons, non-merging
  conflicts, edits during transfer, empty tables, localized Other, suppressed
  removals, opt-out cancellation, and malformed/oversized reason fields.
- Chunk tests verify exact 8,192/8,193-byte boundaries, lost/tampered chunks,
  one-time apply, incomplete-assembly rejection, and one-record-at-a-time
  queueing rather than unbounded snapshot expansion.

Live transport results cannot be inferred from mocks. Document remaining
client-only checks rather than claiming in-game verification.

## Research references

- [Forever restrictions and event ordering](https://github.com/Ketho/wow-ui-source-forever/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua)
- [Forever restriction enums](https://github.com/Ketho/wow-ui-source-forever/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua)
- [Addon message limits and result semantics](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)
- [RCLootCouncil sync](https://github.com/evil-morfar/RCLootCouncil2/blob/master/Modules/Sync.lua)
- [ChatThrottleLib](https://github.com/WoWUIDev/Ace3/blob/master/AceComm-3.0/ChatThrottleLib.lua)
- Local CraftCritic `src/Modules/Sync.lua` and `src/Data/Serializer.lua`.
