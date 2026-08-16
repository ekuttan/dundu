# Dundu — design system (iOS)

What the iPhone app is built from, and why. Tokens live in
[`Shared/DesignTokens.swift`](Shared/DesignTokens.swift), the shared views in
[`iOS/DunduControls.swift`](iOS/DunduControls.swift), and the bar's
scroll behaviour in [`iOS/BarChrome.swift`](iOS/BarChrome.swift). Nothing in
a screen file should define its own spacing, radius or colour.

## The five rules

1. **One white page.** The ground and a card are the same white. Content is
   separated by space, not by a change of surface, so a list of reminders
   reads as one page rather than a stack of tiles.
2. **No outlines.** A surface is told apart by its fill. Borders and
   separators are the exception that has to earn its place — `hairline` is
   for dividing rows *inside* one card, nothing else.
3. **Type carries the hierarchy.** One large title per screen, everything
   under it much smaller. There is no navigation bar to do this job.
4. **One accent, spent once.** Blue means "this does something": the add
   button, a badge, a live recording. Chrome — a selected tab, a heading, a
   primary button — is ink and grey. Spending the accent twice makes neither
   read.
5. **Chrome floats, content scrolls under it.** The bar is a material
   capsule over the page, never a strip framing it.

## Tokens

| Group | Values | Use |
|---|---|---|
| `Spacing` | `xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 32` | padding and stack spacing |
| `Radius` | `chip 14 · block 18 · card 22 · sheet 28` | corner radii, always `.continuous` |
| `Layout` | `gutter 20 · control 44 · headerButton 38 · barHeight 56 · barInset 152` | margins, tap targets, the bar's footprint |
| `Shadow` | `floating · accent` | only under things that hover |
| `Anim` | `content · chrome · notchSpring` | springs; content moves, chrome snaps |

### Colour

| Token | Means |
|---|---|
| `ground` | the page |
| `card` | a raised surface (same white in light mode — see rule 1) |
| `fill` | a quieter fill *inside* a card: chips, wells, chrome buttons, the selected tab |
| `ink` / `quiet` / `faint` | first, second and third rank type |
| `hairline` | a divider between rows inside one card |
| `accent` | the one blue signal, flat (the gradient's two stops sit close enough to read as one colour) |
| `hueMeeting` / `hueTask` / `hueTravel` / `hueUrgent` / `hueDone` | category hues, only ever shown at `blockFill` strength (14%) |
| `overdue` / `dueSoon` / `meeting` | status colours, shared with the Mac notch |

`paper` and `surface` are kept as aliases of `card` and `fill` so the Mac
surfaces keep compiling; new code should use the current names.

### Type

All SF Rounded — the warmth of the app comes mostly from that one choice.
`largeTitle 34` · `screenTitle 20` · `cardTitle 17` · `sectionTitle 15` ·
`body 16` · `blockTitle 13` · `label 13` · `caption 12` · `rail 10`.

## Surfaces

- `cardSurface(_:radius:)` — flat fill, big corners, no border. The single
  surface treatment in the app.
- `floatingSurface(_ shape:)` — `.regularMaterial`, a half-point highlight
  and one soft shadow. Only the tab bar and its action capsule use it.
- `dunduFormBackground()` — drops the grouped-grey backdrop from a stock
  `Form` so it sits on our ground. Real forms stay real forms.
- `clearsFloatingBar()` — bottom content margin of `Layout.barInset` so a
  scroll view's last row clears the bar. Every scrolling screen needs it;
  anything presented as a sheet does not.

## Components

| View | What it is |
|---|---|
| `ScreenHeader` | the large title, an optional subtitle, and round actions on the right |
| `CompactHeader` | actions only, for screens where the content is the title |
| `CircleButton` | a glyph in a soft circle — `.soft`, `.accent`, `.onCard` |
| `SoftCard` | a padded card, optionally washed with a hue |
| `CardHeader` | a card's tinted heading line: glyph, title, trailing detail |
| `TrayChip` | the compact card the Today tray is made of |
| `PillButton` | the one filled control on a screen — `.primary`, `.accent`, `.quiet` |
| `PressableStyle` | everything tappable sinks 4% |
| `QuietEmptyState` | replaces `ContentUnavailableView`, which brings its own list styling |
| `plainRow(inset:)` | a `List` row with none of `List`'s decoration |

## Navigation

Three destinations — Reminders, Today, Inbox — in a floating glass pill, and
the two things you *do* beside it in their own capsule: the mic, and the
accent-filled add button. Both capsules are `barHeight` tall so they read as
one piece of chrome.

Settings is not a destination. It opens as a sheet from the gear in the
Reminders header, and everything under it (Apple Reminders, Google Calendar,
Profile context) pushes inside that sheet.

`BarChrome` collapses the bar while the user is reading: scrolling down
slides the tab pill and the mic out behind the add button, scrolling up or
settling near the top brings them back. A screen opts in by taking a
`BarChrome`, putting `ScrollProbe()` as the first row of its scroll content,
and adding `.tracksScroll(chrome)` to the scroll view. (iOS 18 has
`onScrollGeometryChange` for this; the deployment target is 17, so a probe
it is.)

## Things deliberately not done

- **No colour dots in front of names.** At 6pt an arbitrary Reminders colour
  reads as debris. The selected filter chip carries its list's colour
  instead, and headings are plain type.
- **No labels under the tab glyphs.** A second row of type there competes
  with the screen's own title.
- **No gradient on the accent.** A gradient reads as decoration; this colour
  is meant to read as a signal.
- **No shadows on cards.** Only floating chrome casts one.

## The Mac side

The notch and menu bar share `Spacing`, `Radius`, `Anim` and the status
colours, and nothing else. They are a different surface with different
constraints, and the iOS card language does not transfer to a panel hanging
off the notch.
