# Dundu — minimal, native iOS

The interface follows Apple's current system design: standard SwiftUI navigation,
semantic system colors, SF typography, and content with minimal decoration.
On supported iOS versions, native tab bars and toolbars adopt Liquid Glass
automatically. Older supported versions retain their native appearance.

Reference: [Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

## What changed from the first redesign

| Before | After | Why |
| --- | --- | --- |
| Warm ivory and teal branding | System backgrounds, primary/secondary labels, blue tint | Matches iOS and adapts to appearance settings |
| Serif titles and brand labels | Native navigation titles in the system font | Removes decorative hierarchy |
| Custom five-control dock | Native TabView with three destinations | Gives navigation to the system |
| Capture actions inside the dock | Native toolbar actions for voice and add | Separates actions from destinations |
| Summary cards and greeting | Reminder content directly below list filters | Less to scan before reaching tasks |
| Separate card for every reminder | Standard grouped List rows | Denser, familiar, and supports native swipe actions |
| Large clock card and slogan | Small current-time readout above the timeline | Keeps the schedule primary |
| Marketing-style secondary screens | Plain copy, native controls, and quiet surfaces | Keeps the entire app consistent |

## Navigation

`DunduWorkspace` owns the native `TabView` and an independent `NavigationStack`
for Reminders, Today, and Inbox. Reminders remains the initial destination. Each
screen has native toolbar buttons for Settings, Record, and Add. Inbox displays
its pending count as a native tab badge.

Reminders uses native search, existing list filters, grouped rows, and an
expandable Completed section. Completion buttons, editing, both swipe directions,
drag-to-list moves, snooze presets, custom dates, and delete remain available.

Today keeps day paging, the current time, the schedule grid, meeting joins,
editing, reminder completion, and the existing untimed/overdue tray and overflow.
Inbox retains repair and routing decisions, edit, and dismiss.

## Visual rules

- Use native navigation, search, forms, pickers, and buttons wherever appropriate.
- Use semantic system backgrounds and labels; let light and dark mode resolve them.
- Use system text styles and Dynamic Type. No serif headings or repeated branding.
- Keep color for actions, events, and status. Keep content surfaces neutral.
- Avoid decorative summary panels, slogans, extra shadows, and nested tinted cards.
- Let the native tab bar reserve its own space. Scroll content only needs a small
  additional bottom margin; there is no custom floating dock to clear.
- Press feedback remains short and respects Reduce Motion.

Tokens live in `Shared/DesignTokens.swift`; shared controls and native workspace
navigation live in `iOS/DunduControls.swift`.

## Mac

The Mac shares system typography and semantic colors. Its compact menu, settings,
and black notch retain their existing controls and behavior with minimal branding.

## Functionality boundary

`Packages/DunduKit` remains unchanged. Persistence, Apple and Google sync,
intelligence, permissions, scheduling, and view mutation helpers retain their
existing implementations. Changes are limited to presentation and navigation.

## Verification

`Tools/DesignPreview` stages the real views and native workspace in a separate
Simulator app with memory-only sample data. It omits background sync and connected
accounts. See its README for capture commands. Preview images are generated under
`build.noindex/DesignReview`.
