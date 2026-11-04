# AstraTest for iOS and macOS

```swift
.package(url: "https://github.com/Kiswani/astra-test-swift", from: "0.1.0")
```

```swift
import AstraTest
AstraTest.start(key: "pk_test_…")
AstraTest.identify(email: user.email, name: user.name)
```

- Report button floating over the app; shake on iPhone and iPad; ⇧⌥R on the Mac; or `AstraTest.showReport()`.
- Screenshots black out secure text fields and any view with `astraPrivate = true`.
- URLSession traffic (including `.default`/`.ephemeral` sessions, Alamofire) and stdout/stderr are recorded. Call `AstraTest.instrument(config)` for a configuration you build yourself.
- `Demo/` is a SwiftUI checkout app (`xcodegen generate`, then run on a simulator; pass `-astraOpen` to open the sheet at launch).
