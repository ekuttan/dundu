# Dundu

A reminders and calendar app for iOS and macOS with its own local-first store, syncing two ways with Apple Reminders and Google Calendar. On the Mac it lives in the notch: hidden most of the time, appearing when something is due or a meeting is about to start.

Two things make it different from other reminders clients:

1. **It knows your context.** Dundu holds a small on-device profile of your businesses, calendars, and the people around them. When a new item arrives, it picks the right calendar or list on its own.
2. **It fixes what Siri got wrong.** Dictated items arrive garbled, usually on names and company words. Dundu flags them and offers a correction instead of leaving you to find the mistake three days later.

All intelligence runs on-device through Apple's Foundation Models framework. Nothing about your businesses or contacts leaves the device.

## Status

Early development. Currently at **M0** of the build plan: project skeleton, data models, and both app shells build and pass tests. See [Roadmap](#roadmap).

## Architecture

**No backend.** Dundu is local-first with Apple-hosted sync:

| Layer | What | Where it runs |
|---|---|---|
| Source of truth for the UI | SwiftData store | on each device |
| Device-to-device sync | CloudKit private database | your own iCloud account |
| Apple Reminders | EventKit, two-way | on-device |
| Google Calendar | Google Calendar REST API, two-way | direct from the client |
| AI | Apple Foundation Models | on-device |

A core rule: **every calendar has exactly one sync path.** Google-backed calendars that appear inside EventKit (because the account is added in System Settings) are auto-excluded from EventKit sync — the Google bridge owns them. EventKit owns Reminders. Neither overlaps, which is what prevents duplicate items.

### Project layout

```
Dundu/
├─ Packages/DunduKit/        Everything except views. Platform-agnostic.
│  ├─ Models/                SwiftData models (CloudKit-compatible shapes)
│  ├─ Store/                 ModelContainer, queries, mutation helpers
│  ├─ Bridges/
│  │  ├─ EventKit/           Apple Reminders bridge
│  │  └─ Google/             OAuth, REST client, syncToken engine
│  ├─ Sync/                  SyncBridge protocol, SyncCoordinator actor
│  ├─ Intelligence/          IntelligenceProvider protocol, ProfileContext
│  └─ Scheduling/            next-due / next-meeting calculation
├─ iOS/                      iPhone app shell
├─ macOS/                    agent app (LSUIElement) + notch panel
└─ Shared/                   design tokens, formatters
```

Both sync bridges implement one protocol, so the coordinator treats Apple and Google the same way:

```swift
protocol SyncBridge: Actor {
    var id: BridgeID { get }
    func pull() async throws -> [RemoteChange]
    func push(_ changes: [LocalChange]) async throws -> [PushResult]
    func observeChanges() -> AsyncStream<Void>
}
```

Sync mappings carry a `baseSnapshot` — the field values at last successful sync — which turns a two-way diff into a field-level three-way merge.

### Design decisions worth knowing

- **SwiftData shaped for CloudKit from day one**: every property has a default or is optional, no `@Attribute(.unique)` — uniqueness on external IDs is enforced in store code.
- **Tombstones, not deletes**: deletions set `tombstonedAt` so they propagate through sync; purged after 30 days.
- **Completion beats uncompletion** in merge conflicts, regardless of timestamps. Resurrecting a finished task annoys people more than the reverse.
- **Date math never goes to the model.** The AI marks that a deadline was spoken; Swift's `Calendar` resolves "tomorrow evening" against the actual clock and time zone.
- **Location alarms are fired by the system, not Dundu.** They map to EventKit alarms, so Apple Reminders monitors the geofence — no Always-location permission, no battery cost.

## Requirements

- Xcode 26+
- Base targets: iOS 17, macOS 14
- AI features (Phase 3): iOS 26 / macOS 26 with Apple Intelligence hardware, with a rules-based fallback everywhere else

## Building

```sh
# Package tests
cd Packages/DunduKit && swift test

# iOS app
xcodebuild -project Dundu.xcodeproj -scheme Dundu-iOS \
  -destination "generic/platform=iOS Simulator" build

# macOS agent app
xcodebuild -project Dundu.xcodeproj -scheme Dundu-macOS build
```

Or open `Dundu.xcodeproj` in Xcode and run either scheme. The macOS app is an agent (no Dock icon) — look for the menu bar extra.

## Secrets and privacy

There are no API keys, tokens, or credentials in this repository, and none should ever be committed:

- Google OAuth uses PKCE from the client; refresh tokens live in the **Keychain**, never on disk or in the store.
- The profile context (businesses, people, aliases) is a local JSON file in Application Support, deliberately outside SwiftData so it can never ride along with CloudKit sync — and it is never committed.
- The AI layer is entirely on-device. No prompts or content leave the machine.

## Roadmap

**Phase 1 — the app.** ✅ M0 skeleton → M1 EventKit read → M2 one-way push → M3 full two-way Reminders sync (mappings, three-way merge, tombstones, echo suppression) → M4 macOS notch panel → M5 due scheduler, peek, snooze → M6 iOS UI → M7 CloudKit → M8 polish.

**Phase 2 — calendar.** M9 Google OAuth + read → M10 two-way event sync (syncTokens, etags, idempotent writes) → M11 meeting peek + Join button in the notch.

**Phase 3 — intelligence.** M12 profile context editor → M13 routing with confidence bands → M14 garbled-text repair via phonetic matching → M15 the Inbox → M16 location alarms → M17 voice capture → M18 decision logging and band tuning.

**Phase 4 — Apple TV.** M19 read-only tvOS board → M20 App Group snapshots → M21 Top Shelf extension.

The principle behind the ordering: a reliable reminders app with a notch is already useful; an unreliable one with clever AI is not.

## License

Personal project. All rights reserved.
