import SwiftUI
import AstraTest

@main
struct DemoApp: App {
    init() {
        AstraTest.start(key: ProcessInfo.processInfo.environment["ASTRA_KEY"] ?? "pk_test_f2463b056a52fafa6684fe6e",
                        enabledIn: .testBuilds,
                        options: .init(excludeHosts: ["example.com"]))
        AstraTest.setScreen("Checkout")
    }
    var body: some Scene {
        WindowGroup("Checkout") {
            CheckoutView()
                .onAppear {
                    // In a real app, call identify once sign-in completes.
                    AstraTest.identify(email: "sdk-e2e@astratest.dev", name: "Apple demo")
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-astraOpen") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { AstraTest.showReport() }
                    }
                    #if os(iOS)
                    if args.contains("-astraShake") {
                        // Same path as a real shake: UIKit calls motionEnded on the key window.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            let w = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
                            w?.motionEnded(.motionShake, with: nil)
                            print("ASTRA_SHOOK")
                        }
                    }
                    #endif
                    if args.contains("-astraSend") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            AstraTest.send(description: "Apple SDK 0.2 check: the card number row should be blacked out in this screenshot.") { r in
                                switch r {
                                case .success(let s): print("ASTRA_SENT \(s.ref)")
                                case .failure(let e): print("ASTRA_FAILED \(e.localizedDescription)")
                                }
                            }
                        }
                    }
                }
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .help) { Button("Report a Problem…") { AstraTest.showReport() } }
        }
        #endif
    }
}

struct CheckoutView: View {
    @State private var code = "WELCOME20"
    @State private var password = "secret-password"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SABLE").font(.title2).tracking(4)
            HStack { Text("Ceramic pour-over set"); Spacer(); Text("AED 240.00") }
            HStack { Text("Single-origin beans"); Spacer(); Text("AED 65.00") }
            HStack { Text("Card"); Spacer(); Text("4242 4242 4242 4242") }
                .padding(10).background(Color.yellow.opacity(0.3))
                .astraPrivate()
            TextField("Promo code", text: $code).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
            HStack { Text("Total").bold(); Spacer(); Text("AED 304.80").bold() }
            Button("Pay AED 304.80") { print("Pay tapped; total still 304.80") }.buttonStyle(.borderedProminent)
            Button("Report a problem") { AstraTest.showReport() }
            Spacer()
            AstraTestStatus()
        }
        .padding(24)
        .task {
            // One request that's recorded and one to an excluded host that isn't.
            _ = try? await URLSession.shared.data(from: URL(string: "https://astratest.dev/v1/health")!)
            _ = try? await URLSession.shared.data(from: URL(string: "https://example.com/api/promo?code=WELCOME20")!)
        }
    }
}
