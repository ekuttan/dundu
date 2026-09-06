# Isolated UI preview

Stage the actual iOS views with a separate app entry point and sample SwiftData
content. The fixture uses memory-only storage, disables CloudKit, and omits
RootView's background sync tasks. It is for visual inspection only: capture/add/settings
toolbar actions are placeholders, while the underlying screen controls are the real
views. Do not grant this preview app access to Reminders or connect accounts.

```sh
python3 Tools/DesignPreview/stage.py
xcodebuild -project /private/tmp/dundu-design-preview/Dundu.xcodeproj \
  -scheme Dundu-iOS -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/dundu-preview-build \
  PRODUCT_BUNDLE_IDENTIFIER=app.scoop.dundu.designpreview \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted /private/tmp/dundu-preview-build/Build/Products/Debug-iphonesimulator/Dundu.app
xcrun simctl launch booted app.scoop.dundu.designpreview reminders
```

Other launch arguments: `today`, `inbox`, `settings`, `edit`, `onboarding`.
Terminate the preview app before launching a different route. Use `simctl ui`
to switch appearance or Dynamic Type size. Screenshots are captured with
`xcrun simctl io booted screenshot /absolute/output.png`.

After changing the source views, rerun staging and the build. Production builds
continue using the original `iOS/DunduApp.swift` and the unchanged DunduKit.

To capture all six routes and light/dark/larger-text variants:

```sh
python3 Tools/DesignPreview/capture.py build.noindex/DesignReview DEVICE_UUID
```

The capture script restores the Simulator’s original appearance and text size.
It waits for launch transitions to settle before saving screenshots.
