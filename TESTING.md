# Dundu — pending testing checklist

Everything below is built and unit-tested but needs a human with real
accounts and devices. Work through it in order; each item says what to do
and what "working" looks like. Report anything off and it gets fixed.

## 1. Google Calendar (needs your sign-in — highest value)

- [ ] **Sign in**: iPhone → Reminders → gear (top right) → Google Calendar
      → Add Google Account.
      Google's page loads (verified); completing sign-in should land you
      back in Dundu with your calendars listed. If Google shows
      "access_denied", your address isn't in the OAuth test users list in
      Google Cloud Console.
- [ ] **Roles**: toggle sync on for your three calendars and set their
      roles (Personal / Work A / Work B). Roles are what AI routing targets.
- [ ] **Pull**: events from the last ~3 months and upcoming should appear
      on Today (today's ones) within a minute.
- [ ] **Two-way**: create an event in Google Calendar web → appears in
      Dundu within 5 min (or on app foreground). Tap the event on Today →
      edit sheet → rename it → the change lands in Google Calendar (etag'd
      patch). Deleting there removes it from Google too.
- [ ] **Meeting peek**: a Meet event starting within 5 minutes should drop
      the notch pill; expanded panel shows a Join button that opens Meet.
- [ ] **Repeat sign-ins**: testing mode kills tokens after 7 days — the
      account row will show "needs signing in again" when that happens.

## 2. CloudKit device-to-device (needs both devices, same iCloud)

- [ ] Run the iOS app on your iPhone (Xcode → Dundu-iOS scheme → your
      phone) and the Mac app together.
- [ ] Add a reminder on iPhone → Mac menu bar/notch shows it within ~30s.
- [ ] Complete on Mac → iPhone follows.

## 3. Apple Reminders sync on real data

- [ ] First sync pulls all your real lists and reminders.
- [ ] Edit the same reminder on both sides before syncing → field-level
      merge (title from one side, notes from the other survive).
- [ ] Completion set in Apple Reminders while Dundu is closed arrives on
      next foreground.

## 3b. iPhone shell (after the design pass)

- [ ] Tab bar: three destinations in the floating pill, with ＋ and the mic
      stacked in the right-hand corner column. Both reachable from every
      tab; the pill and the stack stay clear of the last row on every
      screen (scroll Reminders and Inbox to the bottom to check).
- [ ] Settings is off the bar: the gear in the Reminders header opens it as
      a sheet, ✕ closes it, and everything under it (Apple Reminders,
      Google Calendar, Profile context) pushes and pops inside that sheet.
- [ ] Reminders: each item is its own white card on the grey ground, list
      headings and filter chips carry no colour dots, and the selected
      filter chip picks up its list's colour.
- [ ] Light and dark: cards stay readable against the ground in both, and
      the bar's material still separates it from what scrolls under it.

## 4. Intelligence (fill Profile Context first)

- [ ] Reminders → gear → Profile context: add your businesses, aliases, people
      (Contacts picker), keywords, and map each to a calendar role.
- [ ] Dictate a reminder to Siri with a name it garbles → Inbox card with
      the proposed fix; accepting writes the fix back to Apple Reminders.
- [ ] A reminder naming a business should route to its list silently
      (check the decision log if curious: Application Support/Dundu/decisions.jsonl).
- [ ] On your iPhone (15 Pro+ / iOS 26): the Foundation Models path judges
      repairs; elsewhere the rules fallback runs. Both should behave.

## 5. Notch behaviors (Mac, current build in /Applications)

- [ ] Peek appears exactly when an item becomes due, not after random syncs.
- [ ] Expanding then leaving = dismissed; it doesn't re-peek for the same
      items. A snoozed item returning peeks again.
- [ ] Hover any time shows Due now + Next up (reminders and meetings mixed).
- [ ] Quick add from the notch (＋ in the panel header); Escape cancels;
      typing there doesn't steal focus until you click the field.
- [ ] Full-screen video suppresses automatic peeks; hover still works.
- [ ] `DUNDU_NOTCH_DEMO=1` launch shows fake items incl. a Join button.

## 6. Location alarms

- [ ] Reminder → Add location alert → pick a place you'll actually pass →
      the system notification should fire exactly like a native Reminders
      geofence (works with Dundu closed).

## 7. Notifications

- [ ] A garbled item due within 24h fires an immediate notification with
      "Use suggested title" / "Keep original" action buttons that work
      without opening the app.
- [ ] The daily 9am Inbox nudge arrives only when something is pending.

## 8. Voice capture (new — needs your mic)

- [ ] Tab bar → mic button in the corner stack (above ＋, on any tab) →
      speak several tasks in one go, e.g. the spec's
      own example: "Call the CA about the DIFC filing before Thursday,
      pick up the car from service tomorrow evening, and remind me when I
      reach the office to send Joby the deck."
- [ ] Live transcript shows while talking; transcription is on-device.
- [ ] Stop → one editable card per action, with resolved dates ("tomorrow
      evening" becomes an actual timestamp), proposed lists, and location
      conditions.
- [ ] Confirm → reminders save (with geofences for arrive/leave) and sync
      to Apple Reminders. Cancel mid-review → cards park in the Inbox.
- [ ] On Apple Intelligence hardware the model splits; elsewhere a
      conservative rules splitter runs — cards are editable either way.

## Known gaps / not built yet

| Item | Status |
|---|---|
| Voice capture on Mac | iOS only for now; menu bar record option is a follow-up |
| M18 band tuning | Runs on your usage data; decision log already collecting |
| Recurring event edits | v1 rule: single instances only, series edits open Google Calendar |
| Focus suppression | Dormant until Focus Status capability is enabled on the App ID in Xcode |
| Mac Google sign-in | Sign in on iPhone; Mac reads the synced events via CloudKit. Direct Mac sign-in works too but each device authenticates separately |
| Apple TV (M19–21) | Parked until everything else is tested |

## Fixes queued from your last feedback (already live in /Applications)

- Launch-time Reminders permission ask + menu bar banner when sync is off
- Added items never vanish from the menu bar (scrolling, due-first list)
- Quick add + due date as one control, color-coded chips, explicit Remove
- Deterministic notch peek, bouncier animation, ⋯ menu for Settings/Quit
- Notch responsiveness: hover and hit testing both in screen coordinates,
  geometry validated on every refresh, panel self-heals if it drifts
- The notch's gear opens settings — `showSettingsWindow:` never reached the
  scene from a nonactivating panel in an LSUIElement app, so Dundu owns the
  window now; the ⋯ menu uses the same opener

## UI redesign verification — 7 September 2026

- iOS Simulator app build: passed (`Dundu-iOS`, signing disabled).
- macOS app build: passed (`Dundu-macOS`, signing disabled).
- Existing DunduKit suite: 126 tests in 20 suites passed.
- Confirmed no changes to `Packages/DunduKit`; compared 23 existing view action,
  persistence, date-resolution, and capture functions against the prior revision.
- Inspected Simulator renders of Reminders, Today, Inbox, onboarding, the reminder
  editor, and Settings. Checked the reminder screen in dark mode and with
  accessibility-medium Dynamic Type.
- Inspected native Mac renders of the menu bar view and settings window.
- Visual fixtures used memory-only stores and separate preview bundle identifiers.
  Real account synchronization, microphone capture, physical-device notch behavior,
  and end-to-end external integrations were not exercised in this pass.

Preview instructions are in `Tools/DesignPreview/README.md`. Local screenshots
are generated under `build.noindex/DesignReview` and are intentionally ignored by
Git. Test builds and logs are local artifacts; the production entry points and
account settings are unchanged.

### Minimal native iOS revision

The follow-up revision replaces the custom dock with native TabView and toolbar
controls, uses semantic system colors and SF text styles, and removes decorative
summary panels and branding. Both iOS and Mac production targets build. The same
23 behavior functions and the entire DunduKit package remain unchanged. Native
Simulator screens were checked in light mode, dark mode, and accessibility-medium
text. Preview staging now removes obsolete Swift files when source views are deleted.

### Reminder identity regression — 2026-09-07

- Full DunduKit suite: **143 tests in 22 suites passed** (17 new identity and history-replay tests).
- iOS Simulator, signed iOS device and macOS builds passed.
- Installed and launched the signed update on the paired iPhone 16 and Mac.
- Migrated an isolated, CloudKit-disabled copy of the existing Mac store:
  all 889 reminder records survived; 415 external identities were saved.
- The initial live Mac migration retained all 415 active reminders and identities.
  A subsequent CloudKit history import replayed 380 old deletion flags and
  duplicate mappings. Apple still contained all 414 expected records after
  the one deliberate duplicate removal. Sync was paused while the issue was
  diagnosed; additional regression tests cover that history replay.
- The final live audit verified 414 active Mac records with 414 unique Apple
  identities and exactly one instance of the user-identified duplicate title.
  Comparing the live Apple IDs with the original backup confirmed that the
  selected duplicate was the only record removed.
- A second isolated rehearsal restored all 414 Apple identities locally and
  a subsequent plan proposed zero local or remote writes. Its logs are in
  `/private/tmp/dundu-reconcile-copy.log`.
- Identity regressions cover an imported item arriving without its mapping,
  an already-claimed remote, edits during mapping delivery, EventKit delivery
  lag, a mapping arriving first, conflicting/repeated mappings, new typed and
  voice reminders, and persistence without a mapping record.
- The targeted repair tool's live refusal checks rejected equal IDs, a wrong
  title and an invalid review token without changing reminders.
- A user-identified duplicate pair was reviewed and reduced to one Apple
  reminder, retaining the record with additional start-date metadata. The
  before/after review and a consistent store backup are under the ignored
  `build.noindex/SyncRepair/` directory; no personal records are committed.

The regression suite simulates partial delivery; it does not prove every
CloudKit interleaving. Divergent local edits and legacy imported items with no recoverable identity
are retained without exporting new copies. Only identical local copies already
linked to the same observed Apple identity are consolidated. Old unmarked
tombstones cannot delete restored Apple records; explicit current-client
deletions still propagate. Dangling mappings get a five-minute delivery grace
period before the existing Apple record can be imported again. Equal
names alone are never authority to delete reminders. Google account flows,
voice permissions and every interaction on physical hardware still require
full end-to-end acceptance testing.

### Login and bottom navigation refinement — 2026-09-07

- Signed macOS and iOS device builds passed; isolated Simulator build passed.
- Installed the Mac update and verified `SMAppService.mainApp.status` changed
  from `.notFound` (3) to `.enabled` (1) after registration. Diagnostic log:
  `/private/tmp/dundu-login-final.log`. No logout or restart was performed.
- The default setup handles both missing and unregistered services. It marks
  setup complete only after registration/approval state is established, or
  after the user explicitly disables automatic launch.
- Inspected sample-data screenshots for the three grouped destinations,
  separate voice button, retained Add button, and no initial search field.
  Light, dark and larger-text captures are in `build.noindex/DockReview/`.
- Search still filters titles and notes, with a focused text field, Clear and
  Cancel controls. Settings is reached from the footer of Reminders.
- These changes do not modify the tested reminder/calendar sync code.
- The revised iPhone build installed and launched successfully on the paired
  phone after it was reconnected. Runtime layout inspection for this revision
  was performed in Simulator.

## 9. Coding activity and live agent sessions (Mac)

Two setup steps, both one-time.

**Grant the folder.** Notch → chart icon → Connect Claude Code → choose
`~/.claude` (the picker opens there with hidden files shown). Same for
`~/.codex`. Dundu is sandboxed, so without this it genuinely cannot see them.

**Install the hooks**, for the live list and done alerts:

```bash
Tools/agent-hooks/install.sh
```

It merges into `~/.claude/settings.json`, backs the file up first, leaves any
other tool's hooks alone, and is safe to run twice. Undo with `--remove`.
Restart any running Claude Code session afterwards.

- [ ] Dashboard: tokens, sessions, tool calls, streak, a year heatmap, top
      model and last-active, switchable between Claude Code and Codex.
- [ ] First scan takes ~30s on a large corpus and shows a progress bar; every
      later open is instant. Only the session being written is re-read.
- [ ] Live list: start a Claude Code task → it appears as "working". A
      permission prompt flips it to "needs you" and sorts it to the top.
- [ ] Done alert: finish a task → a notification naming the project and what
      was asked. Finishing again does not re-alert for the same state.
- [ ] Close the lid mid-task: the stranded "working" row ages out after two
      hours rather than sitting there forever.
