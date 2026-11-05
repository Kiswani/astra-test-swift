# AstraTest for iOS and macOS

In-app bug reporting for Astra Test. Testers shake the device, press ⇧⌥R on the Mac, or use a "Report a problem" item; point at what's wrong and say it in their own words. Reports arrive with a screenshot, recent requests, log lines and device details.

## Install

Swift Package Manager, **app target only** (never widgets, share, notification service or other extensions):

```swift
.package(url: "https://github.com/Kiswani/astra-test-swift", from: "0.2.0")
```

In Xcode: File › Add Package Dependencies, paste the URL, "Up to Next Major". To use a local checkout instead: File › Add Package Dependencies › Add Local…, or `.package(path: "../AstraTest/sdks/apple")`.

## Start it in test builds only

```swift
import AstraTest

@main
struct MyApp: App {
    init() {
        AstraTest.start(key: "pk_test_…", enabledIn: .testBuilds)
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

`.testBuilds` is on in Xcode, Simulator, development/ad hoc and TestFlight builds, and off in App Store builds:

- **iOS:** provisioning profile (development/ad hoc), then the sandbox receipt (TestFlight), then the App Store transaction environment.
- **macOS:** no App Store receipt means an Xcode or direct build; otherwise the App Store transaction environment.
- If your app already knows (e.g. a `TESTFLIGHT` compile flag), pass it: `options: .init(testBuild: true)` decides instead of detecting.

Use this rather than your own check. `AppTransaction.environment` alone doesn't always say sandbox on TestFlight iPhone builds.

`start` prints one line saying what it decided: `[AstraTest] Running (TestFlight build).` or `[AstraTest] Not running: App Store build…`. In code: `AstraTest.isRunning`, `AstraTest.status`, `AstraTest.updateAvailable` (set when a newer SDK is out) and the `AstraTest.statusDidChange` notification. Show it to testers, for example in Settings › About:

```swift
Section("About") { AstraTestStatus() }
```

It also shows "Update available" when Astra Test has a newer SDK than the app's.

## A visible way to report

The floating Report button shows for test keys unless you pass `showButton: false`. Either way, add an entry people can find:

```swift
// iOS: a Settings row
Button("Report a problem") { AstraTest.showReport() }

// macOS: the Help menu
.commands { CommandGroup(after: .help) { Button("Report a Problem…") { AstraTest.showReport() } } }
```

Shake (iOS and iPadOS, including SwiftUI-lifecycle apps) and ⇧⌥R (macOS) also open it. Hide your entries when `AstraTest.isRunning` is false.

## Who sent it

```swift
AstraTest.identify(id: user.id, email: user.email, name: user.name)
```

Call it when sign-in completes and when the account changes. At launch, accounts may still be restoring.

## Privacy

- Secure text fields are always blacked out in screenshots.
- SwiftUI: `.astraPrivate()` on any view. UIKit/AppKit: `view.astraPrivate = true`.
- `excludeHosts: ["gmail.googleapis.com"]`: those requests are neither recorded nor routed through the SDK (subdomains included).
- `captureNetwork: false` and `captureLogs: false` turn those off entirely.

For apps with email, messages, health, finance or restricted Google scopes, consider all of the above. It's the app owner's call.

## How capture works

- **Network:** a `URLProtocol`, plus swizzled `URLSessionConfiguration.default` and `.ephemeral`, so `URLSession.shared`, Alamofire and most clients are recorded: method, URL without the query string, status and timing, never bodies. For a configuration you build yourself, call `AstraTest.instrument(config)` before creating the session.
- **Logs:** stdout and stderr (`print`, `NSLog`) are mirrored into a ring buffer; your app's own output is unchanged.
- **Screenshot:** the app's key window, with private views blacked out.
- Version and build come from `CFBundleShortVersionString` and `CFBundleVersion`.

## Checklist

- [ ] Key added, `enabledIn: .testBuilds`
- [ ] Privacy choice confirmed with the app owner
- [ ] A visible "Report a problem" entry, plus shake / ⇧⌥R
- [ ] `identify()` after sign-in
- [ ] Not in app extensions
- [ ] A test report sent from a TestFlight build and seen in Astra Test

`Demo/` is a SwiftUI checkout app (`xcodegen generate`, then run on a simulator; `-astraOpen` opens the sheet, `-astraSend` sends a report).
