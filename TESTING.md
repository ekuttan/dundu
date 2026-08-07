# Dundu — pending testing checklist

Everything below is built and unit-tested but needs a human with real
accounts and devices. Work through it in order; each item says what to do
and what "working" looks like. Report anything off and it gets fixed.

## 1. Google Calendar (needs your sign-in — highest value)

- [ ] **Sign in**: iPhone → Settings → Google Calendar → Add Google Account.
      Google's page loads (verified); completing sign-in should land you
      back in Dundu with your calendars listed. If Google shows
      "access_denied", your address isn't in the OAuth test users list in
      Google Cloud Console.
- [ ] **Roles**: toggle sync on for your three calendars and set their
      roles (Personal / Work A / Work B). Roles are what AI routing targets.
- [ ] **Pull**: events from the last ~3 months and upcoming should appear
      on Today (today's ones) within a minute.
- [ ] **Two-way**: create an event in Google Calendar web → appears in
      Dundu within 5 min (or on app foreground). Rename it in Dundu (no
      edit UI yet — via a future build; skip if blocked).
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

## 4. Intelligence (fill Profile Context first)

- [ ] Settings → Profile context: add your businesses, aliases, people
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

- [ ] Today → mic button → speak several tasks in one go, e.g. the spec's
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
| Event edit UI on iOS | Events are sync + display only so far; edits flow Google→Dundu |
| Recurring event edits | v1 rule: single instances only, series edits open Google Calendar |
| Focus suppression | Dormant until Focus Status capability is enabled on the App ID in Xcode |
| Mac Google sign-in | Sign in on iPhone; Mac reads the synced events via CloudKit. Direct Mac sign-in works too but each device authenticates separately |
| Apple TV (M19–21) | Parked until everything else is tested |

## Fixes queued from your last feedback (already live in /Applications)

- Launch-time Reminders permission ask + menu bar banner when sync is off
- Added items never vanish from the menu bar (scrolling, due-first list)
- Quick add + due date as one control, color-coded chips, explicit Remove
- Deterministic notch peek, bouncier animation, ⋯ menu for Settings/Quit
